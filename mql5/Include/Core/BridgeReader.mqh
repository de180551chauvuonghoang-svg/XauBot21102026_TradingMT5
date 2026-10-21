//+------------------------------------------------------------------+
//|                                              BridgeReader.mqh   |
//|                              MultiAssetEA v2 - Quant Trading     |
//|  Giao tiếp 2 chiều MT5 EA <-> Python Brain qua FILE_COMMON      |
//|  Đọc: sig_<id>.json, heartbeat.json, kill_switch.json, blackout |
//|  Ghi: ack_<id>.json, account_state.json                          |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Team"
#property version   "2.10"

#include "Definitions.mqh"
#include "RiskManager.mqh"
#include "ExecutionEngine.mqh"
#include "SafetyGuard.mqh"
#include "PortfolioManager.mqh"

class CBridgeReader {
private:
   string   m_heartbeatFile;
   string   m_killFile;
   string   m_blackoutFile;
   string   m_stateFile;
   datetime m_lastHeartbeatTime;
   bool     m_brainAlive;
   bool     m_lastHeartbeatReported;
   bool     m_inNewsBlackout;
   datetime m_lastBlackoutCheck;
   datetime m_lastStateWriteTime;

public:
   CBridgeReader() :
      m_heartbeatFile("heartbeat.json"),
      m_killFile("kill_switch.json"),
      m_blackoutFile("news_blackout.json"),
      m_stateFile("account_state.json"),
      m_lastHeartbeatTime(0),
      m_brainAlive(false),
      m_lastHeartbeatReported(false),
      m_inNewsBlackout(false),
      m_lastBlackoutCheck(0),
      m_lastStateWriteTime(0)
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
   //| Kiểm tra Heartbeat từ Python Brain (A5 FIX: TimeGMT UTC)      |
   //+---------------------------------------------------------------+
   bool CheckHeartbeat(int maxAgeSeconds = 180) {
      if(!FileIsExist(m_heartbeatFile, FILE_COMMON)) {
         if(m_brainAlive) {
            PrintFormat("⚠️ [HEARTBEAT] File heartbeat.json không tồn tại. Mất kết nối Brain.");
         }
         m_brainAlive = false;
         return false;
      }

      int handle = FileOpen(m_heartbeatFile, FILE_READ | FILE_TXT | FILE_COMMON | FILE_SHARE_READ);
      if(handle == INVALID_HANDLE) return m_brainAlive;

      string content = "";
      while(!FileIsEnding(handle)) content += FileReadString(handle);
      FileClose(handle);

      int pos = StringFind(content, "\"unix_ts\":");
      if(pos >= 0) {
         string sub = StringSubstr(content, pos + 10);
         string numStr = "";
         for(int i = 0; i < StringLen(sub); i++) {
            ushort ch = StringGetCharacter(sub, i);
            if((ch >= '0' && ch <= '9') || ch == '.') numStr += ShortToString(ch);
            else if(StringLen(numStr) > 0) break;
         }
         long ts = (long)StringToDouble(numStr);
         datetime gmtNow = TimeGMT(); // A5 FIX: Dùng TimeGMT() thay vì TimeLocal()
         long age = (long)gmtNow - ts;

         if(age >= 0 && age <= maxAgeSeconds) {
            if(!m_brainAlive && m_lastHeartbeatReported) {
               PrintFormat("✅ [HEARTBEAT] Kết nối Python Brain đã được khôi phục (tuổi tín hiệu: %d giây).", (int)age);
            }
            m_brainAlive = true;
            m_lastHeartbeatTime = (datetime)ts;
            m_lastHeartbeatReported = true;
         } else {
            if(m_brainAlive) {
               PrintFormat("⚠️ [HEARTBEAT] Mất tín hiệu Python Brain (%d giây > %d giây). Ngừng nhận tín hiệu Brain, EA tự vận hành độc lập.",
                           (int)age, maxAgeSeconds);
            }
            m_brainAlive = false;
            m_lastHeartbeatReported = true;
         }
      }
      return m_brainAlive;
   }

   bool IsBrainAlive() const { return m_brainAlive; }

   //+---------------------------------------------------------------+
   //| Kiểm tra News Blackout từ Python Brain (A4 FIX: Cửa sổ UTC)   |
   //+---------------------------------------------------------------+
   bool CheckNewsBlackout(int windowMinutes = 30) {
      datetime gmtNow = TimeGMT();
      // Cache 30 giây tránh đọc đĩa liên tục mỗi tick
      if(gmtNow - m_lastBlackoutCheck < 30) {
         return m_inNewsBlackout;
      }
      m_lastBlackoutCheck = gmtNow;

      if(!FileIsExist(m_blackoutFile, FILE_COMMON)) {
         m_inNewsBlackout = false;
         return false;
      }

      int handle = FileOpen(m_blackoutFile, FILE_READ | FILE_TXT | FILE_COMMON | FILE_SHARE_READ);
      if(handle == INVALID_HANDLE) return m_inNewsBlackout;

      string content = "";
      while(!FileIsEnding(handle)) content += FileReadString(handle);
      FileClose(handle);

      // Tìm các mốc time_utc trong danh sách sự kiện
      m_inNewsBlackout = false;
      int searchPos = 0;
      while(true) {
         int pos = StringFind(content, "\"time_utc\":", searchPos);
         if(pos < 0) {
            pos = StringFind(content, "\"time_utc\": ", searchPos);
            if(pos < 0) break;
            pos += 12;
         } else {
            pos += 11;
         }

         string sub = StringSubstr(content, pos);
         string numStr = "";
         for(int i = 0; i < StringLen(sub); i++) {
            ushort ch = StringGetCharacter(sub, i);
            if(ch >= '0' && ch <= '9') numStr += ShortToString(ch);
            else if(StringLen(numStr) > 0) break;
         }

         if(StringLen(numStr) > 0) {
            long eventTs = (long)StringToDouble(numStr);
            long diff = (long)gmtNow - eventTs;
            long windowSec = windowMinutes * 60;
            if(diff >= -windowSec && diff <= windowSec) {
               m_inNewsBlackout = true;
               PrintFormat("[SAFETY] Đang trong vùng News Blackout (cách sự kiện %d giây). Tạm ngừng mở lệnh mới.", (int)diff);
               break;
            }
         }
         searchPos = pos + 10;
      }

      return m_inNewsBlackout;
   }

   bool IsInNewsBlackout() const { return m_inNewsBlackout; }

   //+---------------------------------------------------------------+
   //| Xử lý tín hiệu giao dịch Brain (A3 FIX: File riêng sig_<id>)  |
   //+---------------------------------------------------------------+
   void ProcessBrainSignals(CRiskManager &risk, CExecutionEngine &exec,
                            CSafetyGuard &safety, CPortfolioManager &portfolio,
                            const string allowedSymbolsCsv) {
      string filename;
      long searchHandle = FileFindFirst("sig_*.json", filename, FILE_COMMON);
      if(searchHandle == INVALID_HANDLE) return;

      do {
         ProcessSingleSignalFile(filename, risk, exec, safety, portfolio);
      } while(FileFindNext(searchHandle, filename));

      FileFindClose(searchHandle);
   }

   void ProcessSingleSignalFile(const string filename, CRiskManager &risk,
                                CExecutionEngine &exec, CSafetyGuard &safety,
                                CPortfolioManager &portfolio) {
      int handle = FileOpen(filename, FILE_READ | FILE_TXT | FILE_COMMON | FILE_SHARE_READ);
      if(handle == INVALID_HANDLE) return;

      string content = "";
      while(!FileIsEnding(handle)) content += FileReadString(handle);
      FileClose(handle);

      if(StringLen(content) < 10) {
         FileDelete(filename, FILE_COMMON);
         return;
      }

      string id       = ExtractJsonString(content, "id");
      string sym      = ExtractJsonString(content, "symbol");
      string typeStr  = ExtractJsonString(content, "type");
      double sl       = ExtractJsonDouble(content, "stop_loss");
      double tp       = ExtractJsonDouble(content, "take_profit1");
      ulong  magic    = (ulong)ExtractJsonDouble(content, "magic");
      long   sigTs    = (long)ExtractJsonDouble(content, "created_at_utc");

      if(id == "") id = filename;
      if(magic == 0) magic = MAGIC_BRAIN_AI;

      // 1. Kiểm tra tuổi tín hiệu (< 60 giây theo A3)
      long gmtNow = (long)TimeGMT();
      long age = gmtNow - sigTs;
      if(sigTs > 0 && (age > 60 || age < -10)) {
         PrintFormat("[BRIDGE] Tín hiệu %s (%s %s) bị TỪ CHỐI vì quá hạn (age: %d giây > 60s)", id, sym, typeStr, age);
         WriteAck(id, "REJECTED", StringFormat("stale_signal_age_%d_seconds", age));
         FileDelete(filename, FILE_COMMON);
         return;
      }

      // 2. Chuỗi kiểm tra an toàn bắt buộc trước khi mở lệnh
      // Bước 2.1: CheckAllLimits (Daily / Weekly / Total DD Halt)
      if(!risk.CheckAllLimits()) {
         PrintFormat("[BRIDGE] Tín hiệu %s bị TỪ CHỐI do RiskManager Halt (%s)", id, risk.GetHaltReason());
         WriteAck(id, "REJECTED", StringFormat("risk_manager_halt_%s", risk.GetHaltReason()));
         FileDelete(filename, FILE_COMMON);
         return;
      }

      // Bước 2.2: News Blackout
      if(CheckNewsBlackout()) {
         PrintFormat("[BRIDGE] Tín hiệu %s bị TỪ CHỐI do đang trong vùng News Blackout", id);
         WriteAck(id, "REJECTED", "news_blackout_active");
         FileDelete(filename, FILE_COMMON);
         return;
      }

      // Bước 2.3: Giờ phiên giao dịch theo UTC (A10)
      if(!safety.IsTradingSessionActive(sym)) {
         PrintFormat("[BRIDGE] Tín hiệu %s bị TỪ CHỐI: Ngoài phiên giao dịch hoạt động của %s", id, sym);
         WriteAck(id, "REJECTED", "session_inactive");
         FileDelete(filename, FILE_COMMON);
         return;
      }

      // Bước 2.4: Kiểm tra Spread theo ATR (an toàn vốn)
      if(!risk.IsSpreadOk(sym)) {
         PrintFormat("[BRIDGE] Tín hiệu %s bị TỪ CHỐI: Spread của %s quá cao so với ATR", id, sym);
         WriteAck(id, "REJECTED", "spread_too_high");
         FileDelete(filename, FILE_COMMON);
         return;
      }

      // Bước 2.5: Giới hạn danh mục và tương quan (Portfolio Manager)
      ENUM_SIGNAL_TYPE sigType = (typeStr == "BUY") ? SIGNAL_BUY : SIGNAL_SELL;
      if(!portfolio.CanOpenNew(sym, sigType)) {
         PrintFormat("[BRIDGE] Tín hiệu %s bị TỪ CHỐI do chạm giới hạn tổng lệnh/tương quan danh mục", id);
         WriteAck(id, "REJECTED", "portfolio_limits_exceeded");
         FileDelete(filename, FILE_COMMON);
         return;
      }

      // Bước 2.6: Tính lot size động theo rủi ro 0.5% vốn qua CalcLot (A7 & P0 #4)
      double entryPrice = (sigType == SIGNAL_BUY) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
      double lot = risk.CalcLot(sym, entryPrice, sl);
      if(lot <= 0) {
         PrintFormat("[BRIDGE] Tín hiệu %s bị TỪ CHỐI: CalcLot trả về 0.0 (rủi ro thực vượt hạn mức cho tài khoản nhỏ)", id);
         WriteAck(id, "REJECTED", "lot_below_broker_minimum");
         FileDelete(filename, FILE_COMMON);
         return;
      }

      // Bước 2.7: Kiểm tra tổng rủi ro mở không vượt 2% equity (A8 FIX)
      if(!risk.CheckOpenRisk(sym, lot, entryPrice, sl)) {
         PrintFormat("[BRIDGE] Tín hiệu %s bị TỪ CHỐI: Vượt quá tổng rủi ro mở 2%%", id);
         WriteAck(id, "REJECTED", "max_open_risk_exceeded_2pct");
         FileDelete(filename, FILE_COMMON);
         return;
      }

      // Bước 2.8: Mở lệnh chính thức qua ExecutionEngine
      SignalPacket pkt;
      pkt.symbol = sym;
      pkt.type = sigType;
      pkt.timeframe = PERIOD_M15;
      pkt.regime = REGIME_UNKNOWN;
      pkt.entryPrice = entryPrice;
      pkt.stopLoss = sl;
      pkt.takeProfit1 = tp;
      pkt.takeProfit2 = 0.0;
      pkt.confidence = 0.70;
      pkt.strategyName = "BrainAI";
      pkt.comment = StringFormat("Brain:%s", id);
      pkt.signalTime = TimeCurrent();
      pkt.magic = magic;

      bool ok = exec.OpenOrder(pkt, lot);
      if(ok) {
         PrintFormat("[BRIDGE] ✅ ĐÃ THỰC THI TÍN HIỆU BRAIN %s: %s %s %.2f lot @ %.5f", id, sym, typeStr, lot, entryPrice);
         WriteAck(id, "EXECUTED", StringFormat("Order opened successfully with %.2f lot", lot));
      } else {
         PrintFormat("[BRIDGE] ❌ THỰC THI THẤT BẠI cho tín hiệu %s", id);
         WriteAck(id, "FAILED", "Execution failed on MT5 server");
      }

      // Xóa file tín hiệu sau khi xử lý xong (A3)
      FileDelete(filename, FILE_COMMON);
   }

   //+---------------------------------------------------------------+
   //| Ghi file phản hồi ack_<id>.json cho Python Brain đọc (A3)     |
   //+---------------------------------------------------------------+
   void WriteAck(const string id, const string status, const string reason) {
      string cleanId = id;
      StringReplace(cleanId, "sig_", "");
      StringReplace(cleanId, ".json", "");

      string ackFilename = "ack_" + cleanId + ".json";
      string json = StringFormat(
         "{\n"
         "  \"id\": \"%s\",\n"
         "  \"status\": \"%s\",\n"
         "  \"reason\": \"%s\",\n"
         "  \"timestamp_utc\": %I64d\n"
         "}",
         cleanId, status, reason, (long)TimeGMT()
      );

      int handle = FileOpen(ackFilename, FILE_WRITE | FILE_TXT | FILE_COMMON);
      if(handle != INVALID_HANDLE) {
         FileWriteString(handle, json);
         FileClose(handle);
      }
   }

   //+---------------------------------------------------------------+
   //| Ghi Account State định kỳ cho Python Brain đọc (A6 FIX)       |
   //+---------------------------------------------------------------+
   void WriteAccountState(CRiskManager &risk) {
      datetime gmtNow = TimeGMT();
      // Giới hạn ghi file tối đa 1 lần mỗi 3 giây
      if(gmtNow - m_lastStateWriteTime < 3) return;
      m_lastStateWriteTime = gmtNow;

      double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      double peakEq   = risk.GetPeakEquity();
      if(peakEq <= 0) peakEq = balance;

      double startDayEq  = risk.GetDailyStartingEquity();
      double startWeekEq = risk.GetWeeklyStartingEquity();

      double dailyLossPct  = (startDayEq > 0 && equity < startDayEq) ? (startDayEq - equity) / startDayEq * 100.0 : 0.0;
      double weeklyLossPct = (startWeekEq > 0 && equity < startWeekEq) ? (startWeekEq - equity) / startWeekEq * 100.0 : 0.0;
      double totalDDPct    = (peakEq > 0 && equity < peakEq) ? (peakEq - equity) / peakEq * 100.0 : 0.0;
      double openRiskPct   = (equity > 0) ? (risk.GetTotalOpenRisk() / equity * 100.0) : 0.0;
      int    openPos       = PositionsTotal();

      string json = StringFormat(
         "{\n"
         "  \"balance\": %.2f,\n"
         "  \"equity\": %.2f,\n"
         "  \"peak_equity\": %.2f,\n"
         "  \"daily_loss_pct\": %.2f,\n"
         "  \"weekly_loss_pct\": %.2f,\n"
         "  \"total_dd_pct\": %.2f,\n"
         "  \"open_risk_pct\": %.2f,\n"
         "  \"open_positions\": %d,\n"
         "  \"halted\": %s,\n"
         "  \"halt_reason\": \"%s\",\n"
         "  \"timestamp_utc\": %I64d\n"
         "}",
         balance, equity, peakEq, dailyLossPct, weeklyLossPct, totalDDPct,
         openRiskPct, openPos, (risk.IsHalted() ? "true" : "false"), risk.GetHaltReason(), (long)gmtNow
      );

      int handle = FileOpen(m_stateFile, FILE_WRITE | FILE_TXT | FILE_COMMON);
      if(handle != INVALID_HANDLE) {
         FileWriteString(handle, json);
         FileClose(handle);
      }
   }

   string ExtractJsonString(const string json, const string key) {
      string search = "\"" + key + "\": \"";
      int start = StringFind(json, search);
      if(start < 0) {
         search = "\"" + key + "\":\"";
         start = StringFind(json, search);
         if(start < 0) return "";
         start += StringLen(search);
      } else {
         start += StringLen(search);
      }
      int end = StringFind(json, "\"", start);
      if(end < 0) return "";
      return StringSubstr(json, start, end - start);
   }

   double ExtractJsonDouble(const string json, const string key) {
      string search = "\"" + key + "\": ";
      int start = StringFind(json, search);
      if(start < 0) {
         search = "\"" + key + "\":";
         start = StringFind(json, search);
         if(start < 0) return 0.0;
         start += StringLen(search);
      } else {
         start += StringLen(search);
      }
      int end = StringFind(json, ",", start);
      if(end < 0) end = StringFind(json, "}", start);
      if(end < 0) return 0.0;
      return StringToDouble(StringSubstr(json, start, end - start));
   }
};
