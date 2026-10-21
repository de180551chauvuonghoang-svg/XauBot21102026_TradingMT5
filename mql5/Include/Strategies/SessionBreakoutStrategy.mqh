//+------------------------------------------------------------------+
//|                                      SessionBreakoutStrategy.mqh |
//|                              MultiAssetEA v2 - Quant Trading     |
//|  London / NY Open Breakout với xác nhận volume/biến động         |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Team"
#property version   "2.00"

#include "StrategyBase.mqh"

class CSessionBreakoutStrategy : public CStrategyBase {
private:
   // Asian session: 00:00-07:00 UTC → Range hình thành
   // London open:   07:00-09:00 UTC → Breakout
   // NY open:       13:00-15:00 UTC → Breakout

   double m_atrSlMult;      // SL bên kia vùng range + ATR buffer (default 0.5)
   double m_rrRatio;        // R:R tối thiểu (default 1.5)
   double m_minRangePips;   // Range tối thiểu để vào lệnh (tránh phá vỡ giả)
   double m_maxRangePips;   // Range tối đa (tránh range quá rộng, rủi ro cao)
   double m_minAtrExpansionFactor; // ATR hiện tại / ATR trung bình > factor thì có biến động đủ

   // State: vùng range phiên Á hôm nay
   double   m_asianHigh;
   double   m_asianLow;
   datetime m_rangeDate;
   bool     m_brokeUp;
   bool     m_brokeDn;

   // Kiểm tra đang trong cửa sổ phiên breakout
   bool IsBreakoutWindow() {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour, m = dt.min;
      // London open: 07:00-09:30 UTC
      bool london = (h == 7 || h == 8 || (h == 9 && m <= 30));
      // NY open: 13:00-15:30 UTC
      bool ny     = (h == 13 || h == 14 || (h == 15 && m <= 30));
      return london || ny;
   }

   // Tính vùng range phiên Á (00:00-07:00 UTC) cho ngày hiện tại
   void CalcAsianRange() {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));

      if(m_rangeDate == today) return;  // Đã tính hôm nay rồi

      m_asianHigh = 0; m_asianLow = 0;
      datetime asianEnd = today + 7 * 3600; // 07:00 UTC

      // Lấy bars trong phiên Á
      MqlRates rates[];
      int cnt = CopyRates(m_symbol, PERIOD_M15, today, asianEnd, rates);
      if(cnt < 5) return;

      m_asianHigh = rates[0].high;
      m_asianLow  = rates[0].low;
      for(int i = 1; i < cnt; i++) {
         if(rates[i].high > m_asianHigh) m_asianHigh = rates[i].high;
         if(rates[i].low  < m_asianLow)  m_asianLow  = rates[i].low;
      }

      m_rangeDate = today;
      m_brokeUp   = false;
      m_brokeDn   = false;

      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      PrintFormat("[Breakout] Phiên Á %s: High=%.5f | Low=%.5f | Range=%.1f pts",
                  m_symbol, m_asianHigh, m_asianLow,
                  (m_asianHigh - m_asianLow) / point);
   }

public:
   CSessionBreakoutStrategy() :
      m_atrSlMult(0.5), m_rrRatio(1.5),
      m_minRangePips(15.0), m_maxRangePips(200.0),
      m_minAtrExpansionFactor(1.2),
      m_asianHigh(0), m_asianLow(0), m_rangeDate(0),
      m_brokeUp(false), m_brokeDn(false)
   {
      m_name = "SessionBreakout_AsianRange";
   }

   void Configure(double atrSlMult = 0.5, double rrRatio = 1.5,
                  double minRangePips = 15.0, double maxRangePips = 200.0) {
      m_atrSlMult    = atrSlMult;
      m_rrRatio      = rrRatio;
      m_minRangePips = minRangePips;
      m_maxRangePips = maxRangePips;
   }

   ENUM_MARKET_REGIME GetSuitableRegime() override { return REGIME_BREAKOUT; }

   bool GenerateSignal(SignalPacket &sig) override {
      sig.symbol       = m_symbol;
      sig.timeframe    = m_tf;
      sig.strategyName = m_name;
      sig.type         = SIGNAL_NONE;
      sig.confidence   = 0.0;

      // Chỉ hoạt động trong cửa sổ breakout
      if(!IsBreakoutWindow()) return false;

      // Tính range phiên Á nếu chưa có
      CalcAsianRange();
      if(m_asianHigh == 0 || m_asianLow == 0) return false;

      double point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double atr    = GetATR(14, 0);
      double atrH4  = 0;
      {
         double buf[];
         int h = iATR(m_symbol, PERIOD_H4, 14);
         if(h != INVALID_HANDLE && CopyBuffer(h, 0, 0, 20, buf) >= 20) {
            double sum = 0;
            for(int i = 1; i < 20; i++) sum += buf[i];
            atrH4 = sum / 19.0;
            IndicatorRelease(h);
         }
      }

      // Kiểm tra range hợp lệ
      double rangePips = (m_asianHigh - m_asianLow) / point;
      if(rangePips < m_minRangePips || rangePips > m_maxRangePips) return false;

      // Kiểm tra ATR expansion (biến động đủ để phá vỡ thật)
      bool atrExpanded = (atrH4 > 0 && atr > atrH4 * m_minAtrExpansionFactor);

      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      ENUM_SIGNAL_TYPE signalType = SIGNAL_NONE;
      double entry = 0, sl = 0, tp1 = 0, tp2 = 0, confidence = 0;

      // Phá vỡ lên (chưa phá lần này)
      if(!m_brokeUp && ask > m_asianHigh + 2 * point) {
         signalType = SIGNAL_BUY;
         entry  = ask;
         sl     = NormalizeDouble(m_asianLow - atr * m_atrSlMult, digits);
         double slDist = entry - sl;
         tp1    = NormalizeDouble(entry + slDist * m_rrRatio * 0.7, digits);
         tp2    = NormalizeDouble(entry + slDist * m_rrRatio, digits);
         confidence = atrExpanded ? 0.70 : 0.55;
         m_brokeUp = true;
      }
      // Phá vỡ xuống
      else if(!m_brokeDn && bid < m_asianLow - 2 * point) {
         signalType = SIGNAL_SELL;
         entry  = bid;
         sl     = NormalizeDouble(m_asianHigh + atr * m_atrSlMult, digits);
         double slDist = sl - entry;
         tp1    = NormalizeDouble(entry - slDist * m_rrRatio * 0.7, digits);
         tp2    = NormalizeDouble(entry - slDist * m_rrRatio, digits);
         confidence = atrExpanded ? 0.70 : 0.55;
         m_brokeDn = true;
      }

      if(signalType == SIGNAL_NONE) return false;

      sig.type        = signalType;
      sig.entryPrice  = entry;
      sig.stopLoss    = sl;
      sig.takeProfit1 = tp1;
      sig.takeProfit2 = tp2;
      sig.confidence  = confidence;
      sig.signalTime  = TimeCurrent();
      sig.regime      = REGIME_BREAKOUT;
      sig.comment     = StringFormat("Asian range %.1f pts breakout %s | ATR expansion: %s",
                                     rangePips, (signalType==SIGNAL_BUY?"UP":"DN"),
                                     (atrExpanded?"YES":"NO"));

      PrintFormat("[Breakout] %s %s | %s | Confidence: %.0f%%",
                  m_symbol, (signalType==SIGNAL_BUY?"BUY":"SELL"), sig.comment, confidence*100);
      return true;
   }
};
