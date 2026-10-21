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
   double   m_peakEquity;         // Đỉnh equity cao nhất từng đạt
   datetime m_lastDayReset;
   datetime m_lastWeekReset;
   bool     m_dailyHalted;        // Dừng trong ngày hiện tại
   bool     m_weeklyHalted;       // Dừng trong tuần hiện tại
   bool     m_permanentHalted;    // Dừng vĩnh viễn (Total DD hoặc thủ công)
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
      m_dailyHalted         = false;
      m_weeklyHalted        = false;
      m_permanentHalted     = false;
      m_consecutiveLosses   = 0;
      m_backtestMaxDD       = 10.0;
      m_dailyStartEquity    = 0;
      m_weeklyStartEquity   = 0;
      m_peakEquity          = 0;
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
      m_dailyHalted         = false;
      m_weeklyHalted        = false;
      m_permanentHalted     = false;
      Print("[RiskManager] Khởi tạo. Daily limit: ", maxDailyLoss, "% | Weekly: ", maxWeeklyLoss, "% | Total DD: ", maxTotalDD, "%");
   }

   // Gọi mỗi tick - cập nhật state và kiểm tra giới hạn
   bool CheckAllLimits() {
      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      double balance  = AccountInfoDouble(ACCOUNT_BALANCE);

      // 0. Cập nhật đỉnh Equity (Peak Equity)
      if(equity > m_peakEquity) m_peakEquity = equity;

      // 1. Tự động Reset ngày mới (Reset Daily Circuit Breaker)
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
      if(today != m_lastDayReset) {
         m_dailyStartEquity = equity;
         m_lastDayReset = today;
         if(m_dailyHalted) {
            m_dailyHalted = false;
            PrintFormat("[RiskManager] Ngày mới (%s). Tự động mở lại giao dịch (Reset Daily Halt). Starting equity: %.2f", TimeToString(today, TIME_DATE), equity);
         }
      }

      // 2. Tự động Reset tuần mới (Reset Weekly Circuit Breaker vào thứ Hai)
      if(dt.day_of_week == 1 && today != m_lastWeekReset) {
         m_weeklyStartEquity = equity;
         m_lastWeekReset = today;
         if(m_weeklyHalted) {
            m_weeklyHalted = false;
            PrintFormat("[RiskManager] Tuần mới (%s). Reset Weekly Halt. Starting equity: %.2f", TimeToString(today, TIME_DATE), equity);
         }
      }

      // Nếu đang bị dừng vĩnh viễn (Total DD hoặc kill switch) -> Bác bỏ toàn bộ
      if(m_permanentHalted) return false;
      if(m_weeklyHalted)    return false;
      if(m_dailyHalted)     return false;

      // 3. Kiểm tra lỗ ngày
      if(m_dailyStartEquity > 0) {
         double dailyDD = (m_dailyStartEquity - equity) / m_dailyStartEquity * 100.0;
         if(dailyDD >= m_maxDailyLossPct) {
            if(!m_dailyHalted) {
               PrintFormat("[RISK HALT] Daily loss %.2f%% >= limit %.2f%%. Tự động dừng giao dịch hôm nay (sẽ mở lại ngày mai)!", dailyDD, m_maxDailyLossPct);
               m_dailyHalted = true;
            }
            return false;
         }
      }

      // 4. Kiểm tra lỗ tuần
      if(m_weeklyStartEquity > 0) {
         double weeklyDD = (m_weeklyStartEquity - equity) / m_weeklyStartEquity * 100.0;
         if(weeklyDD >= m_maxWeeklyLossPct) {
            if(!m_weeklyHalted) {
               PrintFormat("[RISK HALT] Weekly loss %.2f%% >= limit %.2f%%. Dừng đến tuần sau!", weeklyDD, m_maxWeeklyLossPct);
               m_weeklyHalted = true;
            }
            return false;
         }
      }

      // 5. Kiểm tra total Drawdown (tính theo Đỉnh Equity thay vì so với Balance - A6 FIX)
      if(m_peakEquity > 0) {
         double totalDD = (m_peakEquity - equity) / m_peakEquity * 100.0;
         if(totalDD >= m_maxTotalDDPct) {
            if(!m_permanentHalted) {
               PrintFormat("[RISK HALT] Total equity DD %.2f%% (Peak: %.2f, Current: %.2f) >= limit %.2f%%! Dừng vĩnh viễn để bảo toàn vốn.",
                           totalDD, m_peakEquity, equity, m_maxTotalDDPct);
               m_permanentHalted = true;
            }
            return false;
         }

         // Dừng nếu live DD > 1.5x backtest DD
         if(totalDD > m_backtestMaxDD * 1.5) {
            if(!m_permanentHalted) {
               PrintFormat("[RISK HALT] Live DD %.2f%% vượt 1.5x Backtest DD %.2f%%. Edge có thể đã biến mất!", totalDD, m_backtestMaxDD);
               m_permanentHalted = true;
            }
            return false;
         }
      }

      return true;
   }

   // A8 FIX: Tính tổng rủi ro của các vị thế đang mở
   double GetTotalOpenRisk() {
      double totalRisk = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC))) continue;

         double sl = PositionGetDouble(POSITION_SL);
         if(sl <= 0) continue;

         string sym    = PositionGetString(POSITION_SYMBOL);
         double open   = PositionGetDouble(POSITION_PRICE_OPEN);
         double vol    = PositionGetDouble(POSITION_VOLUME);
         double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
         double tickSz = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
         double tickVal= SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
         if(point <= 0 || tickSz <= 0 || tickVal <= 0) continue;

         double slDist = MathAbs(open - sl);
         double loss = (slDist / point) * (tickVal * (point / tickSz)) * vol;
         totalRisk += loss;
      }
      return totalRisk;
   }

   // A8 FIX: Kiểm tra xem lệnh mới có làm tổng rủi ro mở vượt quá 2% equity không
   bool CheckOpenRisk(const string symbol, double lot, double entryPrice, double slPrice) {
      if(lot <= 0 || slPrice <= 0) return false;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0) return false;

      double point   = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double tickSz  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickVal = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      if(point <= 0 || tickSz <= 0 || tickVal <= 0) return false;

      double newTradeLoss = (MathAbs(entryPrice - slPrice) / point) * (tickVal * (point / tickSz)) * lot;
      double currentOpenRisk = GetTotalOpenRisk();
      double totalRiskPct = (currentOpenRisk + newTradeLoss) / equity * 100.0;

      if(totalRiskPct > m_maxOpenRiskPct) {
         PrintFormat("[RiskManager] Tổng rủi ro mở %.2f%% ($%.2f hiện tại + $%.2f lệnh mới) vượt giới hạn %.2f%% vốn $%.2f. TỪ CHỐI LỆNH!",
                     totalRiskPct, currentOpenRisk, newTradeLoss, m_maxOpenRiskPct, equity);
         return false;
      }
      return true;
   }

   // Kiểm tra spread theo ATR (an toàn vốn - fail-closed)
   bool IsSpreadOk(const string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1) {
      double atr[];
      int handle = iATR(symbol, tf, 14);
      if(handle == INVALID_HANDLE) {
         PrintFormat("[RiskManager] Không thể lấy handle ATR cho %s. Từ chối vào lệnh vì an toàn.", symbol);
         return false; // Fail-closed an toàn
      }
      if(CopyBuffer(handle, 0, 0, 1, atr) < 1 || atr[0] <= 0) {
         IndicatorRelease(handle);
         return false;
      }
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
      if(slDist <= 0) {
         Print("[RiskManager] Khoảng cách SL = 0. Từ chối lệnh thiếu SL.");
         return 0.0;
      }

      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskAmt = equity * (m_riskPctPerTrade / 100.0);

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
      if(tickSz <= 0 || tickVal <= 0 || point <= 0) return 0.0;

      double slPoints      = slDist / point;
      double valuePerPoint = tickVal * (point / tickSz);
      double lossPerLot    = slPoints * valuePerPoint;
      if(lossPerLot <= 0) return 0.0;

      double rawLot = riskAmt / lossPerLot;
      return NormalizeLot(symbol, rawLot);
   }

   double NormalizeLot(const string symbol, double vol) {
      double minL = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxL = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0 || minL <= 0) return 0.0;

      // P0 FIX: Nếu lot tính toán nhỏ hơn lot tối thiểu của sàn,
      // việc ép thành minL sẽ vi phạm % rủi ro cho phép (nhất là tài khoản nhỏ).
      // Do đó PHẢI trả về 0.0 để bỏ qua lệnh.
      if(vol < minL) {
         PrintFormat("[RiskManager] %s: Lot tính toán (%.4f) < lot tối thiểu sàn (%.2f). Rủi ro thực vượt hạn mức -> BỎ QUA LỆNH!",
                     symbol, vol, minL);
         return 0.0;
      }

      double normalized = MathFloor(vol / step) * step;
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

   void ForceHalt(string reason)  { m_permanentHalted = true; PrintFormat("[RISK HALT] %s", reason); }
   void ResetHalt() {
      m_permanentHalted   = false;
      m_dailyHalted       = false;
      m_weeklyHalted      = false;
      m_consecutiveLosses = 0;
      Print("[RiskManager] Toàn bộ trạng thái Halt đã được reset.");
   }
   bool IsHalted() const          { return m_permanentHalted || m_dailyHalted || m_weeklyHalted; }
   bool IsDailyHalted() const     { return m_dailyHalted; }
   bool IsWeeklyHalted() const    { return m_weeklyHalted; }
   bool IsPermanentHalted() const { return m_permanentHalted; }
   int  GetConsecutiveLosses() const { return m_consecutiveLosses; }
   double GetDailyStartingEquity() const { return m_dailyStartEquity; }
   double GetWeeklyStartingEquity() const { return m_weeklyStartEquity; }
   double GetPeakEquity() const { return m_peakEquity; }

   string GetHaltReason() const {
      if(m_permanentHalted) return "TOTAL_DRAWDOWN_CIRCUIT_BREAKER";
      if(m_weeklyHalted)    return "WEEKLY_LOSS_LIMIT";
      if(m_dailyHalted)     return "DAILY_LOSS_LIMIT";
      return "NONE";
   }
};
