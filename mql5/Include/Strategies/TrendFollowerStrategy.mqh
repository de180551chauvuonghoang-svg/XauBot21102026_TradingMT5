//+------------------------------------------------------------------+
//|                                        TrendFollowerStrategy.mqh |
//|                              MultiAssetEA v2 - Quant Trading     |
//|  Trend Following: EMA đa khung + ATR SL | R:R >= 1:2           |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Team"
#property version   "2.00"

#include "StrategyBase.mqh"

class CTrendFollowerStrategy : public CStrategyBase {
private:
   // Tham số cấu hình
   int    m_emaFast;       // EMA nhanh (default 21)
   int    m_emaSlow;       // EMA chậm (default 50)
   int    m_emaTrend;      // EMA xu hướng lớn trên H4 (default 200)
   double m_atrSlMult;     // SL = ATR * multiplier (default 1.5)
   double m_rrRatio;       // Risk:Reward tối thiểu (default 2.0)
   double m_adxMin;        // ADX tối thiểu để xác nhận trend (default 25)
   double m_minConfidence; // Ngưỡng confidence tối thiểu (default 0.6)

   // Lần tín hiệu cuối để tránh tín hiệu lặp
   ENUM_SIGNAL_TYPE m_lastSignal;
   datetime         m_lastSignalTime;

public:
   CTrendFollowerStrategy() :
      m_emaFast(21), m_emaSlow(50), m_emaTrend(200),
      m_atrSlMult(1.5), m_rrRatio(2.0), m_adxMin(25.0),
      m_minConfidence(0.6), m_lastSignal(SIGNAL_NONE), m_lastSignalTime(0)
   {
      m_name = "TrendFollower_EMA";
   }

   void Configure(int emaFast, int emaSlow, int emaTrend,
                  double atrSlMult = 1.5, double rrRatio = 2.0, double adxMin = 25.0) {
      m_emaFast    = emaFast;
      m_emaSlow    = emaSlow;
      m_emaTrend   = emaTrend;
      m_atrSlMult  = atrSlMult;
      m_rrRatio    = rrRatio;
      m_adxMin     = adxMin;
   }

   ENUM_MARKET_REGIME GetSuitableRegime() override { return REGIME_TREND; }

   bool GenerateSignal(SignalPacket &sig) override {
      sig.symbol       = m_symbol;
      sig.timeframe    = m_tf;
      sig.strategyName = m_name;
      sig.confidence   = 0.0;
      sig.type         = SIGNAL_NONE;

      // --- Kiểm tra đủ bars
      int bars = iBars(m_symbol, m_tf);
      if(bars < m_emaTrend + 50) return false;

      // --- Chỉ tạo tín hiệu khi nến mới hoàn thành (không tạo 2 lệnh 1 nến)
      datetime lastBar[];
      if(CopyTime(m_symbol, m_tf, 0, 1, lastBar) < 1) return false;
      if(lastBar[0] == m_lastSignalTime) return false;

      // --- Đọc giá trị EMA (khung hiện tại)
      double emaF0 = GetEMA(m_emaFast, 0);
      double emaF1 = GetEMA(m_emaFast, 1);
      double emaS0 = GetEMA(m_emaSlow, 0);
      double emaS1 = GetEMA(m_emaSlow, 1);
      if(emaF0 == 0 || emaS0 == 0) return false;

      // --- Lọc xu hướng H4 (EMA 200 trên khung lớn hơn)
      double emaT_H4 = 0;
      {
         double buf[];
         int hH4 = iMA(m_symbol, PERIOD_H4, m_emaTrend, 0, MODE_EMA, PRICE_CLOSE);
         if(hH4 != INVALID_HANDLE && CopyBuffer(hH4, 0, 0, 1, buf) >= 1) emaT_H4 = buf[0];
         IndicatorRelease(hH4);
      }

      // --- ADX xác nhận xu hướng
      double adxBuf[];
      int adxH = iADX(m_symbol, m_tf, 14);
      bool adxOk = false;
      if(adxH != INVALID_HANDLE && CopyBuffer(adxH, 0, 0, 1, adxBuf) >= 1) adxOk = (adxBuf[0] > m_adxMin);
      IndicatorRelease(adxH);

      if(!adxOk) return false; // ADX chưa đủ mạnh

      // --- ATR cho SL và TP
      double atr = GetATR(14, 0);
      if(atr <= 0) return false;

      double close = iClose(m_symbol, m_tf, 0);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

      double sl = 0, tp1 = 0, tp2 = 0;
      ENUM_SIGNAL_TYPE signalType = SIGNAL_NONE;
      double confidence = 0.0;

      // --- EMA Cross + H4 Filter
      bool emaBullCross  = (emaF0 > emaS0 && emaF1 <= emaS1);  // Golden Cross
      bool emaBearCross  = (emaF0 < emaS0 && emaF1 >= emaS1);  // Death Cross
      bool bullH4Filter  = (emaT_H4 > 0 && close > emaT_H4);   // Giá trên EMA200 H4
      bool bearH4Filter  = (emaT_H4 > 0 && close < emaT_H4);   // Giá dưới EMA200 H4

      if(emaBullCross && bullH4Filter) {
         signalType = SIGNAL_BUY;
         sl         = NormalizeDouble(close - atr * m_atrSlMult, digits);
         tp1        = NormalizeDouble(close + atr * m_atrSlMult * m_rrRatio * 0.7, digits); // 70% khoảng cách
         tp2        = NormalizeDouble(close + atr * m_atrSlMult * m_rrRatio, digits);        // 100% = trailing
         confidence = 0.65 + (adxBuf[0] > 35 ? 0.1 : 0.0);
      } else if(emaBearCross && bearH4Filter) {
         signalType = SIGNAL_SELL;
         sl         = NormalizeDouble(close + atr * m_atrSlMult, digits);
         tp1        = NormalizeDouble(close - atr * m_atrSlMult * m_rrRatio * 0.7, digits);
         tp2        = NormalizeDouble(close - atr * m_atrSlMult * m_rrRatio, digits);
         confidence = 0.65 + (adxBuf[0] > 35 ? 0.1 : 0.0);
      }

      if(signalType == SIGNAL_NONE || confidence < m_minConfidence) return false;

      // Ghi lại tín hiệu
      sig.type        = signalType;
      sig.entryPrice  = close;
      sig.stopLoss    = sl;
      sig.takeProfit1 = tp1;
      sig.takeProfit2 = tp2;
      sig.confidence  = confidence;
      sig.signalTime  = lastBar[0];
      sig.comment     = StringFormat("EMA%d/%d cross | ADX=%.1f | ATR=%.5f", m_emaFast, m_emaSlow, adxBuf[0], atr);
      sig.regime      = REGIME_TREND;

      m_lastSignal     = signalType;
      m_lastSignalTime = lastBar[0];

      PrintFormat("[TrendFollower] %s %s tín hiệu: %s | Confidence: %.0f%% | %s",
                  m_symbol, TimeToString(lastBar[0]),
                  (signalType==SIGNAL_BUY ? "BUY" : "SELL"), confidence*100, sig.comment);
      return true;
   }
};
