//+------------------------------------------------------------------+
//|                                      MeanReversionStrategy.mqh   |
//|                              MultiAssetEA v2 - Quant Trading     |
//|  Mean Reversion: RSI + Bollinger Bands trong regime Range        |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Team"
#property version   "2.00"

#include "StrategyBase.mqh"

class CMeanReversionStrategy : public CStrategyBase {
private:
   int    m_rsiPeriod;       // default 14
   double m_rsiOversold;     // default 30
   double m_rsiOverbought;   // default 70
   int    m_bbPeriod;        // default 20
   double m_bbDeviation;     // default 2.0
   double m_adxMax;          // ADX phải THẤP hơn ngưỡng này (sideway) - default 20
   double m_rrRatio;         // R:R tối thiểu (default 1.2 - TP gần vì mean reversion)
   double m_atrSlMult;       // SL = ATR * multiplier (default 1.0)

   ENUM_SIGNAL_TYPE m_lastSignal;
   datetime         m_lastSignalTime;

public:
   CMeanReversionStrategy() :
      m_rsiPeriod(14), m_rsiOversold(30.0), m_rsiOverbought(70.0),
      m_bbPeriod(20), m_bbDeviation(2.0), m_adxMax(20.0),
      m_rrRatio(1.2), m_atrSlMult(1.0),
      m_lastSignal(SIGNAL_NONE), m_lastSignalTime(0)
   {
      m_name = "MeanReversion_RSI_BB";
   }

   void Configure(int rsiPeriod = 14, double rsiOS = 30.0, double rsiOB = 70.0,
                  int bbPeriod = 20, double bbDev = 2.0, double adxMax = 20.0,
                  double rrRatio = 1.2, double atrSlMult = 1.0) {
      m_rsiPeriod     = rsiPeriod;
      m_rsiOversold   = rsiOS;
      m_rsiOverbought = rsiOB;
      m_bbPeriod      = bbPeriod;
      m_bbDeviation   = bbDev;
      m_adxMax        = adxMax;
      m_rrRatio       = rrRatio;
      m_atrSlMult     = atrSlMult;
   }

   ENUM_MARKET_REGIME GetSuitableRegime() override { return REGIME_RANGE; }

   bool GenerateSignal(SignalPacket &sig) override {
      sig.symbol       = m_symbol;
      sig.timeframe    = m_tf;
      sig.strategyName = m_name;
      sig.type         = SIGNAL_NONE;
      sig.confidence   = 0.0;

      int bars = iBars(m_symbol, m_tf);
      if(bars < m_bbPeriod + 20) return false;

      // Chỉ tạo tín hiệu khi nến mới hoàn thành
      datetime lastBar[];
      if(CopyTime(m_symbol, m_tf, 0, 1, lastBar) < 1) return false;
      if(lastBar[0] == m_lastSignalTime) return false;

      // Kiểm tra ADX (phải thấp - đang sideway)
      double adxBuf[];
      int adxH = iADX(m_symbol, m_tf, 14);
      if(adxH == INVALID_HANDLE) return false;
      if(CopyBuffer(adxH, 0, 0, 1, adxBuf) < 1) { IndicatorRelease(adxH); return false; }
      IndicatorRelease(adxH);
      if(adxBuf[0] > m_adxMax) return false;  // Đang trend, không dùng chiến lược này

      // RSI: Sử dụng ArraySetAsSeries để rsiBuf[0] là nến vừa đóng (bar 1), rsiBuf[1] là nến trước (bar 2)
      double rsiBuf[];
      ArraySetAsSeries(rsiBuf, true);
      int rsiH = iRSI(m_symbol, m_tf, m_rsiPeriod, PRICE_CLOSE);
      if(rsiH == INVALID_HANDLE) return false;
      if(CopyBuffer(rsiH, 0, 1, 2, rsiBuf) < 2) { IndicatorRelease(rsiH); return false; }
      IndicatorRelease(rsiH);
      double rsi1 = rsiBuf[0]; // Nến đã đóng (shift 1)
      double rsi2 = rsiBuf[1]; // Nến trước đó (shift 2)

      // Bollinger Bands: Lấy theo nến đã đóng (shift 1)
      double bbUpper[], bbLower[], bbMid[];
      ArraySetAsSeries(bbUpper, true);
      ArraySetAsSeries(bbLower, true);
      ArraySetAsSeries(bbMid, true);
      int bbH = iBands(m_symbol, m_tf, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
      if(bbH == INVALID_HANDLE) return false;
      bool bbOk = (CopyBuffer(bbH, 1, 1, 1, bbUpper) >= 1 &&
                   CopyBuffer(bbH, 2, 1, 1, bbLower) >= 1 &&
                   CopyBuffer(bbH, 0, 1, 1, bbMid)   >= 1);
      IndicatorRelease(bbH);
      if(!bbOk) return false;

      // P1 FIX: Đánh giá tín hiệu trên nến đã hoàn thành (shift 1) để triệt tiêu repaint
      double close1 = iClose(m_symbol, m_tf, 1);
      double atr    = GetATR(14, 1);
      int    digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      ENUM_SIGNAL_TYPE signalType = SIGNAL_NONE;
      double confidence = 0.0;
      double sl = 0, tp1 = 0, tp2 = 0;

      // BUY: Nến trước quá bán, nến này RSI ngóc lên + giá đóng dưới/sát dải BB dưới -> Đảo chiều
      bool buyCondition  = (rsi2 < m_rsiOversold && rsi1 > rsi2 && close1 < bbLower[0] + atr * 0.3);
      // SELL: Nến trước quá mua, nến này RSI quay xuống + giá đóng trên/sát dải BB trên -> Đảo chiều
      bool sellCondition = (rsi2 > m_rsiOverbought && rsi1 < rsi2 && close1 > bbUpper[0] - atr * 0.3);

      if(buyCondition) {
         signalType = SIGNAL_BUY;
         sl         = NormalizeDouble(close1 - atr * m_atrSlMult, digits);
         tp1        = NormalizeDouble(bbMid[0], digits);
         tp2        = NormalizeDouble(bbUpper[0], digits);
         confidence = 0.60 + (rsi1 < 25 ? 0.1 : 0.0);
      } else if(sellCondition) {
         signalType = SIGNAL_SELL;
         sl         = NormalizeDouble(close1 + atr * m_atrSlMult, digits);
         tp1        = NormalizeDouble(bbMid[0], digits);
         tp2        = NormalizeDouble(bbLower[0], digits);
         confidence = 0.60 + (rsi1 > 75 ? 0.1 : 0.0);
      }

      if(signalType == SIGNAL_NONE || confidence < 0.6) return false;

      // Kiểm tra R:R tối thiểu
      double slDist = MathAbs(close1 - sl);
      double tpDist = MathAbs(tp1 - close1);
      if(slDist <= 0 || tpDist / slDist < m_rrRatio) return false;

      sig.type        = signalType;
      sig.entryPrice  = close1;
      sig.stopLoss    = sl;
      sig.takeProfit1 = tp1;
      sig.takeProfit2 = tp2;
      sig.confidence  = confidence;
      sig.signalTime  = lastBar[0];
      sig.magic       = MAGIC_MEAN_REVERSION;
      m_lastSignalTime = lastBar[0];
      sig.signalTime  = lastBar[0];
      sig.regime      = REGIME_RANGE;
      sig.comment     = StringFormat("RSI=%.1f BB touch | ADX=%.1f (sideway)", rsi1, adxBuf[0]);

      m_lastSignal     = signalType;
      m_lastSignalTime = lastBar[0];

      PrintFormat("[MeanReversion] %s %s | RSI=%.1f | ADX=%.1f | Conf: %.0f%%",
                  m_symbol, (signalType==SIGNAL_BUY?"BUY":"SELL"), rsi1, adxBuf[0], confidence*100);
      return true;
   }
};
