//+------------------------------------------------------------------+
//|                                               SafetyGuard.mqh   |
//|                              MultiAssetEA v2 - Quant Trading     |
//|  Kill-switch, Heartbeat monitor, News Blackout                   |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Team"
#property version   "2.00"

#include "Definitions.mqh"

class CSafetyGuard {
private:
   datetime m_lastHeartbeat;
   int      m_heartbeatTimeoutSec;
   bool     m_heartbeatEnabled;
   bool     m_killSwitchActive;
   bool     m_newsBlackoutActive;

   // News blackout events (UTC time strings)
   struct NewsEvent {
      datetime time;
      string   name;
      int      blackoutMinBefore;
      int      blackoutMinAfter;
   };
   NewsEvent m_events[50];
   int       m_eventCount;

public:
   CSafetyGuard() {
      m_lastHeartbeat       = TimeCurrent();
      m_heartbeatTimeoutSec = 30;
      m_heartbeatEnabled    = false;
      m_killSwitchActive    = false;
      m_newsBlackoutActive  = false;
      m_eventCount          = 0;
   }

   void Init(int heartbeatTimeoutSec, bool enableHeartbeat = false) {
      m_heartbeatTimeoutSec = heartbeatTimeoutSec;
      m_heartbeatEnabled    = enableHeartbeat;
      m_lastHeartbeat       = TimeCurrent();
      Print("[SafetyGuard] Khởi tạo. Heartbeat timeout: ", heartbeatTimeoutSec, "s | Enabled: ", enableHeartbeat);
   }

   // Brain gọi hàm này mỗi chu kỳ để xác nhận còn sống
   void RefreshHeartbeat() {
      m_lastHeartbeat = TimeCurrent();
   }

   // Kiểm tra heartbeat từ Python Brain
   bool CheckHeartbeat() {
      if(!m_heartbeatEnabled) return true;
      datetime elapsed = TimeCurrent() - m_lastHeartbeat;
      if(elapsed > m_heartbeatTimeoutSec) {
         PrintFormat("[SAFETY] Mất kết nối Python Brain %d giây! Chuyển chế độ bảo vệ.", (int)elapsed);
         return false;
      }
      return true;
   }

   // Kill switch - đọc file hoặc nhận lệnh qua Telegram/Bridge
   void ActivateKillSwitch(string reason = "Manual halt") {
      m_killSwitchActive = true;
      PrintFormat("[KILL SWITCH] Kích hoạt! Lý do: %s", reason);
   }
   void DeactivateKillSwitch() { m_killSwitchActive = false; Print("[SAFETY] Kill switch đã tắt."); }
   bool IsKillSwitchActive() const { return m_killSwitchActive; }

   // Thêm sự kiện tin tức vào danh sách blackout
   void AddNewsEvent(datetime evtTime, string evtName, int minBefore = 30, int minAfter = 30) {
      if(m_eventCount >= 50) return;
      m_events[m_eventCount].time             = evtTime;
      m_events[m_eventCount].name             = evtName;
      m_events[m_eventCount].blackoutMinBefore = minBefore;
      m_events[m_eventCount].blackoutMinAfter  = minAfter;
      m_eventCount++;
   }

   void ClearNewsEvents() { m_eventCount = 0; }

   // Kiểm tra có đang trong vùng blackout tin tức không
   bool IsInNewsBlackout(const string &symbolsAffected[]) {
      datetime now = TimeCurrent();
      for(int i = 0; i < m_eventCount; i++) {
         datetime start = m_events[i].time - (m_events[i].blackoutMinBefore * 60);
         datetime end_  = m_events[i].time + (m_events[i].blackoutMinAfter  * 60);
         if(now >= start && now <= end_) {
            PrintFormat("[SAFETY] News Blackout: %s (±%d phút). Bỏ qua lệnh mới.",
                        m_events[i].name, m_events[i].blackoutMinBefore);
            return true;
         }
      }
      return false;
   }

   // Kiểm tra giờ giao dịch theo phiên
   bool IsTradingSessionActive(const string symbol) {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;

      // Tránh rollover / đóng phiên thứ Sáu
      if(dt.day_of_week == 5 && hour >= 21) return false;
      if(dt.day_of_week == 6 || dt.day_of_week == 0) return false;

      // Tokyo session: 00:00 - 09:00 UTC
      // London session: 07:00 - 16:00 UTC
      // New York session: 13:00 - 22:00 UTC

      bool isGold  = (StringFind(symbol, "XAU") >= 0);
      bool isIndex = (StringFind(symbol, "US30") >= 0 || StringFind(symbol, "NAS") >= 0);
      bool isOil   = (StringFind(symbol, "OIL") >= 0 || StringFind(symbol, "USOIL") >= 0);

      // Chỉ số và Dầu chỉ giao dịch phiên NY
      if((isIndex || isOil) && (hour < 13 || hour >= 22)) return false;

      // Vàng: London + NY
      if(isGold && (hour < 7 || hour >= 22)) return false;

      return true;
   }

   bool IsSystemOperational() {
      if(m_killSwitchActive) return false;
      if(!CheckHeartbeat())  return false;
      return true;
   }
};
