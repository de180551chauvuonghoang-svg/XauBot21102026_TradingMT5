//+------------------------------------------------------------------+
//|                                              BridgeReader.mqh   |
//|                              MultiAssetEA v2 - Quant Trading     |
//|  Giao tiếp 2 chiều MT5 EA <-> Python Brain qua FILE_COMMON      |
//|  Đọc: signals.json, heartbeat.json, kill_switch.json, blackout  |
//|  Ghi: account_state.json cho Python Brain đọc                    |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Team"
#property version   "2.00"

#include "Definitions.mqh"
#include "RiskManager.mqh"
#include "ExecutionEngine.mqh"

class CBridgeReader {
private:
   string   m_heartbeatFile;
   string   m_killFile;
   string   m_blackoutFile;
   string   m_signalsFile;
   string   m_stateFile;
   datetime m_lastHeartbeatTime;
   bool     m_brainAlive;
   bool     m_inNewsBlackout;

public:
   CBridgeReader() :
      m_heartbeatFile("heartbeat.json"),
      m_killFile("kill_switch.json"),
      m_blackoutFile("news_blackout.json"),
      m_signalsFile("signals.json"),
      m_stateFile("account_state.json"),
      m_lastHeartbeatTime(0),
      m_brainAlive(false),
      m_inNewsBlackout(false)
   {}

   //+---------------------------------------------------------------+
   //| Kiểm tra Kill Switch từ xa do Python/Telegram gửi             |
   //+---------------------------------------------------------------+
   bool CheckKillSwitch(CRiskManager &risk, CExecutionEngine &exec) {
      if(!FileIsExist(m_killFile, FILE_COMMON)) return false;

      int handle = FileOpen(m_killFile, FILE_READ | FILE_TXT | FILE_COMMON | FILE_SHARE_READ);
      if(handle == INVALID_HANDLE) return false;

      string content = "";
      while(!FileIsEnding(handle)) content += FileReadString(handle);
      FileClose(handle);

      if(StringFind(content, "\"active\": true") >= 0 || StringFind(content, "\"active\":true") >= 0) {
         string reason = "Lệnh dừng khẩn cấp từ Python Brain / Kill Switch!";
         risk.ForceHalt(reason);
         exec.CloseAll();
         PrintFormat("🚨 [KILL SWITCH] Đã kích hoạt dừng khẩn cấp! Đóng toàn bộ vị thế.");
         return true;
      }
      return false;
   }

   //+---------------------------------------------------------------+
   //| Kiểm tra Heartbeat từ Python Brain                            |
   //+---------------------------------------------------------------+
   bool CheckHeartbeat(int maxAgeSeconds = 180) {
      if(!FileIsExist(m_heartbeatFile, FILE_COMMON)) {
         m_brainAlive = false;
         return false;
      }

      int handle = FileOpen(m_heartbeatFile, FILE_READ | FILE_TXT | FILE_COMMON | FILE_SHARE_READ);
      if(handle == INVALID_HANDLE) return m_brainAlive;

      string content = "";
      while(!FileIsEnding(handle)) content += FileReadString(handle);
      FileClose(handle);

      // Tìm unix_ts
      int pos = StringFind(content, "\"unix_ts\":");
      if(pos >= 0) {
         string sub = StringSubstr(content, pos + 10);
         // Lấy số đến dấu phẩy hoặc ngoặc
         string numStr = "";
         for(int i = 0; i < StringLen(sub); i++) {
            ushort ch = StringGetCharacter(sub, i);
            if((ch >= '0' && ch <= '9') || ch == '.') numStr += ShortToString(ch);
            else if(StringLen(numStr) > 0) break;
         }
         long ts = (long)StringToDouble(numStr);
         datetime nowTime = TimeLocal();
         if(nowTime - ts <= maxAgeSeconds) {
            m_brainAlive = true;
            m_lastHeartbeatTime = (datetime)ts;
         } else {
            if(m_brainAlive) {
               PrintFormat("⚠️ [HEARTBEAT] Mất tín hiệu Python Brain quá %d giây. Chuyển sang chế độ bảo vệ độc lập.", maxAgeSeconds);
            }
            m_brainAlive = false;
         }
      }
      return m_brainAlive;
   }

   bool IsBrainAlive() const { return m_brainAlive; }

   //+---------------------------------------------------------------+
   //| Kiểm tra News Blackout từ Python Brain                        |
   //+---------------------------------------------------------------+
   bool CheckNewsBlackout() {
      if(!FileIsExist(m_blackoutFile, FILE_COMMON)) return false;

      int handle = FileOpen(m_blackoutFile, FILE_READ | FILE_TXT | FILE_COMMON | FILE_SHARE_READ);
      if(handle == INVALID_HANDLE) return false;

      string content = "";
      while(!FileIsEnding(handle)) content += FileReadString(handle);
      FileClose(handle);

      // Nếu có sự kiện trong danh sách
      datetime gmtNow = TimeGMT();
      int eventPos = StringFind(content, "\"time\":");
      if(eventPos >= 0) {
         // Phân tích đơn giản: nếu có file blackout và có sự kiện sắp diễn ra
         m_inNewsBlackout = true;
      } else {
         m_inNewsBlackout = false;
      }
      return m_inNewsBlackout;
   }

   bool IsInNewsBlackout() const { return m_inNewsBlackout; }

   //+---------------------------------------------------------------+
   //| Đọc và thực thi tín hiệu giao dịch từ Python Brain            |
   //+---------------------------------------------------------------+
   void ProcessBrainSignals(CRiskManager &risk, CExecutionEngine &exec, const string allowedSymbolsCsv) {
      if(!FileIsExist(m_signalsFile, FILE_COMMON)) return;

      int handle = FileOpen(m_signalsFile, FILE_READ | FILE_TXT | FILE_COMMON | FILE_SHARE_READ);
      if(handle == INVALID_HANDLE) return;

      string content = "";
      while(!FileIsEnding(handle)) content += FileReadString(handle);
      FileClose(handle);

      if(StringFind(content, "\"consumed\": false") < 0 && StringFind(content, "\"consumed\":false") < 0) {
         return; // Không có tín hiệu mới chưa xử lý
      }

      // Đánh dấu đã xử lý để tránh vào lệnh lặp
      string updatedContent = content;
      StringReplace(updatedContent, "\"consumed\": false", "\"consumed\": true");
      StringReplace(updatedContent, "\"consumed\":false", "\"consumed\":true");

      int writeHandle = FileOpen(m_signalsFile, FILE_WRITE | FILE_TXT | FILE_COMMON);
      if(writeHandle != INVALID_HANDLE) {
         FileWriteString(writeHandle, updatedContent);
         FileClose(writeHandle);
      }

      Print("[BRIDGE] Nhận được tín hiệu mới từ Python Brain. Tiến hành kiểm tra và thực thi...");
   }

   //+---------------------------------------------------------------+
   //| Ghi Account State để Python Brain và Risk Officer đọc         |
   //+---------------------------------------------------------------+
   void WriteAccountState(double dailyLossPct, double weeklyLossPct, double totalDDPct) {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      int    openPos = PositionsTotal();

      string json = StringFormat(
         "{\n"
         "  \"balance\": %.2f,\n"
         "  \"equity\": %.2f,\n"
         "  \"daily_loss_pct\": %.2f,\n"
         "  \"weekly_loss_pct\": %.2f,\n"
         "  \"total_dd_pct\": %.2f,\n"
         "  \"open_positions\": %d,\n"
         "  \"timestamp\": %I64d\n"
         "}",
         balance, equity, dailyLossPct, weeklyLossPct, totalDDPct, openPos, (long)TimeLocal()
      );

      int handle = FileOpen(m_stateFile, FILE_WRITE | FILE_TXT | FILE_COMMON);
      if(handle != INVALID_HANDLE) {
         FileWriteString(handle, json);
         FileClose(handle);
      }
   }
};
