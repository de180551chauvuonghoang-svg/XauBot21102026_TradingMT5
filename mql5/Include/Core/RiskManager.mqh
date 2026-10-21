//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|                              MultiAssetEA v2 - Quant Trading     |
//|  Risk Officer: quyền phủ quyết tuyệt đối, không phụ thuộc AI   |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Team"
#property version   "2.00"

#include "Definitions.mqh"

class CRiskManager {
private:
   // --- Config
   double m_riskPctPerTrade;      // % equity rủi ro mỗi lệnh (default 0.5)
   double m_maxOpenRiskPct;       // Tổng rủi ro vị thế mở (default 2.0)
   double m_maxDailyLossPct;      // Lỗ ngày tối đa (default 2.0)
   double m_maxWeeklyLossPct;     // Lỗ tuần tối đa (default 4.0)
   double m_maxTotalDDPct;        // DD tổng tối đa (default 10.0)
   double m_kellyFractionCap;     // Giới hạn Kelly (default 0.25)
   double m_maxSpreadAtrRatio;    // Spread/ATR tối đa (default 0.15)
   int    m_maxSlippagePoints;    // Slippage tối đa (default 20)
   int    m_consecutiveLossCap;   // Giảm size sau N lệnh thua (default 3)
   int    m_newsBlackoutMinutes;  // Phút chặn quanh tin (default 30)

   // --- State
   double   m_dailyStartEquity;
   double   m_weeklyStartEquity;
   datetime m_lastDayReset;
   datetime m_lastWeekReset;
   bool     m_halted;
   int      m_consecutiveLosses;
   double   m_backtestMaxDD;      // Từ backtest - tự động dừng nếu live DD > 1.5x

public:
   CRiskManager() {
      m_riskPctPerTrade     = 0.5;
      m_maxOpenRiskPct      = 2.0;
      m_maxDailyLossPct     = 2.0;
      m_maxWeeklyLossPct    = 4.0;
      m_maxTotalDDPct       = 10.0;
      m_kellyFractionCap    = 0.25;
      m_maxSpreadAtrRatio   = 0.15;
      m_maxSlippagePoints   = 20;
      m_consecutiveLossCap  = 3;
      m_newsBlackoutMinutes = 30;
      m_halted              = false;
      m_consecutiveLosses   = 0;
      m_backtestMaxDD       = 10.0;
      m_dailyStartEquity    = 0;
      m_weeklyStartEquity   = 0;
      m_lastDayReset        = 0;
      m_lastWeekReset       = 0;
   }

   void Init(double riskPct, double maxDailyLoss, double maxWeeklyLoss,
             double maxTotalDD, double backtestMaxDD,
             int newsBlackoutMin = 30, int maxSlippage = 20) {
      m_riskPctPerTrade     = riskPct;
      m_maxDailyLossPct     = maxDailyLoss;
      m_maxWeeklyLossPct    = maxWeeklyLoss;
      m_maxTotalDDPct       = maxTotalDD;
      m_backtestMaxDD       = backtestMaxDD;
      m_newsBlackoutMinutes = newsBlackoutMin;
      m_maxSlippagePoints   = maxSlippage;
      m_dailyStartEquity    = AccountInfoDouble(ACCOUNT_EQUITY);
      m_weeklyStartEquity   = AccountInfoDouble(ACCOUNT_EQUITY);
      m_halted              = false;
      Print("[RiskManager] Khởi tạo. Daily limit: ", maxDailyLoss, "% | Weekly: ", maxWeeklyLoss, "% | Total DD: ", maxTotalDD, "%");
   }

   // Gọi mỗi tick - cập nhật state và kiểm tra giới hạn
   bool CheckAllLimits() {
      if(m_halted) return false;

      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      double balance  = AccountInfoDouble(ACCOUNT_BALANCE);

      // Reset ngày
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
      if(today != m_lastDayReset) {
         m_dailyStartEquity = equity;
         m_lastDayReset = today;
         PrintFormat("[RiskManager] Ngày mới (%s). Starting equity: %.2f", TimeToString(today, TIME_DATE), equity);
      }

      // Reset tuần (Thứ Hai)
      if(dt.day_of_week == 1 && today != m_lastWeekReset) {
         m_weeklyStartEquity = equity;
         m_lastWeekReset = today;
      }

      // Kiểm tra lỗ ngày
      if(m_dailyStartEquity > 0) {
         double dailyDD = (m_dailyStartEquity - equity) / m_dailyStartEquity * 100.0;
         if(dailyDD >= m_maxDailyLossPct) {
            if(!m_halted) {
               PrintFormat("[RISK HALT] Daily loss %.2f%% >= limit %.2f%%. Dừng giao dịch hôm nay!", dailyDD, m_maxDailyLossPct);
               m_halted = true;
            }
            return false;
         }
      }

      // Kiểm tra lỗ tuần
      if(m_weeklyStartEquity > 0) {
         double weeklyDD = (m_weeklyStartEquity - equity) / m_weeklyStartEquity * 100.0;
         if(weeklyDD >= m_maxWeeklyLossPct) {
            if(!m_halted) {
               PrintFormat("[RISK HALT] Weekly loss %.2f%% >= limit %.2f%%. Dừng đến tuần sau!", weeklyDD, m_maxWeeklyLossPct);
               m_halted = true;
            }
            return false;
         }
      }

      // Kiểm tra total DD
      if(balance > 0) {
         double totalDD = (balance - equity) / balance * 100.0;
         if(totalDD >= m_maxTotalDDPct) {
            if(!m_halted) {
               PrintFormat("[RISK HALT] Total floating DD %.2f%% >= limit %.2f%%!", totalDD, m_maxTotalDDPct);
               m_halted = true;
            }
            return false;
         }

         // Dừng nếu live DD > 1.5x backtest DD
         if(totalDD > m_backtestMaxDD * 1.5) {
            if(!m_halted) {
               PrintFormat("[RISK HALT] Live DD %.2f%% vượt 1.5x Backtest DD %.2f%%. Edge có thể đã mất!", totalDD, m_backtestMaxDD);
               m_halted = true;
            }
            return false;
         }
      }

      return true;
   }

   // Kiểm tra spread theo ATR
   bool IsSpreadOk(const string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1) {
      double atr[];
      int handle = iATR(symbol, tf, 14);
      if(handle == INVALID_HANDLE) return true;
      if(CopyBuffer(handle, 0, 0, 1, atr) < 1) { IndicatorRelease(handle); return true; }
      IndicatorRelease(handle);

      double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
      double ratio  = (atr[0] > 0) ? spread / atr[0] : 0;

      if(ratio > m_maxSpreadAtrRatio) {
         PrintFormat("[RiskManager] %s spread/ATR = %.3f > limit %.3f. Bỏ qua.", symbol, ratio, m_maxSpreadAtrRatio);
         return false;
      }
      return true;
   }

   // Tính lot theo % rủi ro trên equity (ATR-based SL distance)
   double CalcLot(const string symbol, double entryPrice, double slPrice) {
      double slDist = MathAbs(entryPrice - slPrice);
      if(slDist <= 0) { Print("[RiskManager] SL distance = 0, dùng lot tối thiểu"); return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN); }

      double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskAmt   = equity * (m_riskPctPerTrade / 100.0);

      // Giảm size sau chuỗi thua
      if(m_consecutiveLosses >= m_consecutiveLossCap) {
         double reduction = 1.0 - (0.1 * (m_consecutiveLosses - m_consecutiveLossCap + 1));
         if(reduction < 0.3) reduction = 0.3;
         riskAmt *= reduction;
         PrintFormat("[RiskManager] Giảm size %.0f%% sau %d lệnh thua liên tiếp", (1.0 - reduction) * 100, m_consecutiveLosses);
      }

      double point   = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double tickSz  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickVal = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSz <= 0 || tickVal <= 0 || point <= 0) return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

      double slPoints      = slDist / point;
      double valuePerPoint = tickVal * (point / tickSz);
      double lossPerLot    = slPoints * valuePerPoint;
      if(lossPerLot <= 0) return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

      double rawLot = riskAmt / lossPerLot;

      // Kelly cap
      double kellyLot = equity * m_kellyFractionCap / (lossPerLot * 100.0);
      if(rawLot > kellyLot) rawLot = kellyLot;

      return NormalizeLot(symbol, rawLot);
   }

   double NormalizeLot(const string symbol, double vol) {
      double minL = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxL = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0) return minL;
      double normalized = MathFloor(vol / step) * step;
      if(normalized < minL) normalized = minL;
      if(normalized > maxL) normalized = maxL;
      return NormalizeDouble(normalized, 2);
   }

   void OnTradeResult(bool isWin) {
      if(isWin) {
         if(m_consecutiveLosses > 0) m_consecutiveLosses = 0;
      } else {
         m_consecutiveLosses++;
         PrintFormat("[RiskManager] Chuỗi thua: %d lệnh liên tiếp", m_consecutiveLosses);
      }
   }

   void ForceHalt(string reason)  { m_halted = true; PrintFormat("[RISK HALT] %s", reason); }
   void ResetHalt()               { m_halted = false; m_consecutiveLosses = 0; Print("[RiskManager] Halt đã được reset thủ công."); }
   bool IsHalted() const          { return m_halted; }
   int  GetConsecutiveLosses() const { return m_consecutiveLosses; }
   double GetDailyStartingEquity() const { return m_dailyStartEquity; }
};
