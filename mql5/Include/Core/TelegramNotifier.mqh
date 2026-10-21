//+------------------------------------------------------------------+
//|                                           TelegramNotifier.mqh  |
//|                              MultiAssetEA v2 - Quant Trading     |
//|  Gửi thông báo Telegram: lệnh, PnL ngày, cảnh báo rủi ro        |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Team"
#property version   "2.00"

class CTelegramNotifier {
private:
   string m_botToken;
   string m_chatId;
   bool   m_enabled;
   string m_lastMessage;
   datetime m_lastSendTime;
   int    m_minIntervalSec;

   bool SendRaw(const string text) {
      if(!m_enabled || m_botToken == "" || m_chatId == "") return false;

      // Throttle: không gửi quá 1 tin / N giây
      if(TimeCurrent() - m_lastSendTime < m_minIntervalSec) return false;

      string url  = "https://api.telegram.org/bot" + m_botToken + "/sendMessage";
      string body = "{\"chat_id\":\"" + m_chatId + "\",\"text\":\"" + text + "\",\"parse_mode\":\"HTML\"}";

      char bodyArr[];
      StringToCharArray(body, bodyArr, 0, StringLen(body));

      char result[];
      string headers = "Content-Type: application/json\r\n";
      string resHeaders;

      int code = WebRequest("POST", url, headers, 5000, bodyArr, result, resHeaders);
      m_lastSendTime = TimeCurrent();

      if(code != 200) {
         PrintFormat("[Telegram] Lỗi gửi tin: HTTP %d", code);
         return false;
      }
      return true;
   }

public:
   CTelegramNotifier() : m_enabled(false), m_lastSendTime(0), m_minIntervalSec(3) {}

   void Init(string botToken, string chatId, bool enabled = true, int minIntervalSec = 3) {
      m_botToken       = botToken;
      m_chatId         = chatId;
      m_enabled        = enabled;
      m_minIntervalSec = minIntervalSec;
      if(enabled) Print("[Telegram] Thông báo đã được kích hoạt.");
   }

   void NotifyOrderOpen(string symbol, string dir, double lot, double price, double sl, double tp, string strategy) {
      string icon = (dir == "BUY") ? "🟢" : "🔴";
      string msg  = StringFormat("%s <b>%s %s</b>\n", icon, dir, symbol)
                  + StringFormat("📊 Chiến lược: <i>%s</i>\n", strategy)
                  + StringFormat("💰 Lot: %.2f | Giá: %.5f\n", lot, price)
                  + StringFormat("🛡 SL: %.5f | 🎯 TP1: %.5f", sl, tp);
      SendRaw(msg);
   }

   void NotifyOrderClose(string symbol, double pnl, string reason, int totalTrades, double winRate) {
      string icon = (pnl >= 0) ? "✅" : "❌";
      string msg  = StringFormat("%s Đóng lệnh <b>%s</b>\n", icon, symbol)
                  + StringFormat("💵 P&L: <b>%.2f USD</b>\n", pnl)
                  + StringFormat("📝 Lý do: %s\n", reason)
                  + StringFormat("📈 Tổng lệnh: %d | Win Rate: %.1f%%", totalTrades, winRate);
      SendRaw(msg);
   }

   void NotifyRiskAlert(string alertType, string detail) {
      string msg = StringFormat("⚠️ <b>CẢNH BÁO RỦI RO: %s</b>\n%s", alertType, detail);
      SendRaw(msg);
   }

   void NotifyHalt(string reason) {
      string msg = StringFormat("🚨 <b>BOT DỪNG HOẠT ĐỘNG</b>\nLý do: %s\nThời điểm: %s",
                                reason, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
      SendRaw(msg);
   }

   void NotifyDailyReport(double balance, double equity, double dailyPnL, double dailyDD, int tradesCount, double profitFactor) {
      string pnlIcon = (dailyPnL >= 0) ? "📈" : "📉";
      string msg = StringFormat("📊 <b>BÁO CÁO NGÀY - %s</b>\n", TimeToString(TimeCurrent(), TIME_DATE))
                 + StringFormat("💼 Balance: %.2f | Equity: %.2f\n", balance, equity)
                 + StringFormat("%s P&L ngày: <b>%.2f USD (%.2f%%)</b>\n", pnlIcon, dailyPnL, dailyDD)
                 + StringFormat("📋 Số lệnh: %d | Profit Factor: %.2f", tradesCount, profitFactor);
      SendRaw(msg);
   }

   void NotifyHeartbeat(string status = "OK") {
      // Gửi ngắn gọn để báo bot còn sống
      string msg = StringFormat("💓 Bot heartbeat: %s | %s", status, TimeToString(TimeCurrent(), TIME_MINUTES));
      SendRaw(msg);
   }
};
