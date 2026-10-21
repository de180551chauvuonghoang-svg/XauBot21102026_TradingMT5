//+------------------------------------------------------------------+
//|                                                StrategyBase.mqh |
//|                              MultiAssetEA v2 - Quant Trading     |
//|  Interface trừu tượng + Regime Detector cho mọi chiến lược       |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Team"
#property version   "2.00"

#include "../Core/Definitions.mqh"

//+------------------------------------------------------------------+
//| Phát hiện Regime thị trường (Trend / Range / Volatile)           |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME DetectRegime(const string symbol, ENUM_TIMEFRAMES tf = PERIOD_H4) {
   double adxBuf[], bbWidthBuf[], atrBuf[], atrNormBuf[];

   // ADX để đo sức mạnh xu hướng
   int adxH = iADX(symbol, tf, 14);
   if(adxH == INVALID_HANDLE) return REGIME_UNKNOWN;
   if(CopyBuffer(adxH, 0, 0, 1, adxBuf) < 1) { IndicatorRelease(adxH); return REGIME_UNKNOWN; }
   IndicatorRelease(adxH);
   double adx = adxBuf[0];

   // ATR để đo biến động tuyệt đối
   int atrH = iATR(symbol, tf, 14);
   if(atrH == INVALID_HANDLE) return REGIME_UNKNOWN;
   if(CopyBuffer(atrH, 0, 0, 20, atrBuf) < 20) { IndicatorRelease(atrH); return REGIME_UNKNOWN; }
   IndicatorRelease(atrH);
   double atrCurrent = atrBuf[0];

   // ATR percentile (so sánh với 20 nến trước)
   double atrMax = atrBuf[0], atrMin = atrBuf[0];
   for(int i = 1; i < 20; i++) {
      if(atrBuf[i] > atrMax) atrMax = atrBuf[i];
      if(atrBuf[i] < atrMin) atrMin = atrBuf[i];
   }
   double atrPctile = (atrMax > atrMin) ? (atrCurrent - atrMin) / (atrMax - atrMin) : 0.5;

   // Xác định regime
   if(atrPctile > 0.85) return REGIME_VOLATILE;     // Biến động bất thường → đứng ngoài
   if(adx > 25)         return REGIME_TREND;         // Xu hướng rõ ràng
   if(adx < 18)         return REGIME_RANGE;         // Sideway / Range
   return REGIME_BREAKOUT;                            // Vùng trung gian
}

//+------------------------------------------------------------------+
//| Lớp trừu tượng cho tất cả chiến lược                             |
//+------------------------------------------------------------------+
class CStrategyBase {
protected:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   string          m_name;

public:
   CStrategyBase() : m_symbol(""), m_tf(PERIOD_H1), m_name("BaseStrategy") {}
   virtual ~CStrategyBase() {}

   virtual void    Init(const string symbol, ENUM_TIMEFRAMES tf) {
      m_symbol = symbol;
      m_tf     = tf;
   }

   // Hàm chính: mỗi chiến lược tự implement
   virtual bool    GenerateSignal(SignalPacket &outSig) = 0;

   // Regime phù hợp với chiến lược này (để PortfolioManager kiểm tra)
   virtual ENUM_MARKET_REGIME GetSuitableRegime() = 0;

   string GetName()   const { return m_name;   }
   string GetSymbol() const { return m_symbol; }

   // Helper: Tính ATR
   double GetATR(int period = 14, int shift = 0) {
      double buf[];
      int h = iATR(m_symbol, m_tf, period);
      if(h == INVALID_HANDLE) return 0;
      if(CopyBuffer(h, 0, shift, 1, buf) < 1) { IndicatorRelease(h); return 0; }
      IndicatorRelease(h);
      return buf[0];
   }

   // Helper: Tính EMA
   double GetEMA(int period, int shift = 0) {
      double buf[];
      int h = iMA(m_symbol, m_tf, period, 0, MODE_EMA, PRICE_CLOSE);
      if(h == INVALID_HANDLE) return 0;
      if(CopyBuffer(h, 0, shift, 1, buf) < 1) { IndicatorRelease(h); return 0; }
      IndicatorRelease(h);
      return buf[0];
   }
};
