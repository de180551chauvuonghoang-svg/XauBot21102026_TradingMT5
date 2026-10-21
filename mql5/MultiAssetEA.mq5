//+------------------------------------------------------------------+
//|                                                MultiAssetEA.mq5 |
//|                              MultiAssetEA v2 - Quant Trading     |
//|  Expert Advisor chính: Điều phối đa tài sản, Regime-aware,       |
//|  Risk Officer veto, Safety Guard, Telegram, Partial Close        |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Team"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property description "MultiAssetEA v2 - Hệ thống giao dịch đa tài sản với quản trị rủi ro chuyên nghiệp"

//--- Includes
#include "Include\Core\Definitions.mqh"
#include "Include\Core\RiskManager.mqh"
#include "Include\Core\ExecutionEngine.mqh"
#include "Include\Core\SafetyGuard.mqh"
#include "Include\Core\PortfolioManager.mqh"
#include "Include\Core\TelegramNotifier.mqh"
#include "Include\Core\BridgeReader.mqh"
#include "Include\Strategies\TrendFollowerStrategy.mqh"
#include "Include\Strategies\SessionBreakoutStrategy.mqh"
#include "Include\Strategies\MeanReversionStrategy.mqh"

//=== INPUT PARAMETERS =================================================

input group "=== DANH MỤC TÀI SẢN ==="
input string InpSymbols      = "XAUUSD,EURUSD,USDCAD"; // Tập trung danh mục chủ lực (tối ưu lợi nhuận/DD)
input ENUM_TIMEFRAMES InpTF  = PERIOD_H1;   // Khung thời gian chính

input group "=== QUẢN TRỊ RỦI RO (Risk Officer) ==="
input double InpRiskPct      = 1.0;    // % Equity rủi ro mỗi lệnh (1.0% tối ưu cho vốn $500 đánh Vàng)
input double InpMaxDailyLoss = 2.0;    // % Lỗ ngày tối đa (Circuit Breaker 2.0%)
input double InpMaxWeeklyLoss= 4.0;    // % Lỗ tuần tối đa
input double InpMaxTotalDD   = 8.0;    // % Max Drawdown tổng (giới hạn cứng bảo vệ vốn < 10%)
input double InpBacktestDD   = 5.0;    // % DD từ backtest (dừng nếu live > 1.5x)
input int    InpMaxTrades    = 2;      // Tối đa 2 lệnh mở đồng thời (kiểm soát rủi ro tương quan)
input int    InpMaxPerSymbol = 1;      // Lệnh tối đa mỗi cặp tiền
input int    InpNewsBlackout = 30;     // Phút chặn trước/sau tin lớn

input group "=== CHIẾN LƯỢC ==="
input bool InpUseTrend       = true;   // Bật chiến lược Trend Following
input bool InpUseBreakout    = true;   // Bật chiến lược Session Breakout
input bool InpUseMeanRev     = true;   // Bật chiến lược Mean Reversion

// Trend Following
input int    InpEmaFast      = 21;     // EMA nhanh
input int    InpEmaSlow      = 50;     // EMA chậm
input double InpAtrSlMult    = 1.5;    // SL = ATR * multiplier
input double InpRR_Trend     = 2.0;    // R:R Trend Following

// Breakout
input double InpMinRangePips = 15.0;   // Range phiên Á tối thiểu (pips)
input double InpRR_Break     = 2.2;    // R:R Breakout tối ưu (chốt lời nổ biên độ)

// Mean Reversion
input int    InpRsiPeriod    = 14;     // RSI Period
input double InpRsiOS        = 25.0;   // RSI Oversold (chọn lọc vùng quá bán cực đại)
input double InpRsiOB        = 75.0;   // RSI Overbought (chọn lọc vùng quá mua cực đại)
input double InpRR_MeanRev   = 1.5;    // R:R Mean Reversion

input group "=== THỰC THI LỆNH ==="
input ulong  InpMagic        = 202610; // Magic Number
input int    InpMaxDeviation = 20;     // Max Slippage (points)
input double InpTrailAtrMult = 1.5;    // Trailing Stop = ATR * multiplier

input group "=== TELEGRAM ==="
input string InpTelegramToken = "";    // Bot Token (lấy từ @BotFather)
input string InpTelegramChatId= "";    // Chat ID
input bool   InpTelegramEnabled= true; // Bật thông báo Telegram

input group "=== AN TOÀN & PYTHON BRAIN BRIDGE ==="
input bool   InpHeartbeatEnabled = true;  // Bật kiểm tra heartbeat Python Brain
input int    InpHeartbeatTimeout = 180;   // Timeout heartbeat (giây)

//=== GLOBAL OBJECTS ===================================================

CRiskManager         g_risk;
CExecutionEngine     g_exec;
CSafetyGuard         g_safety;
CPortfolioManager    g_portfolio;
CTelegramNotifier    g_telegram;
CBridgeReader        g_bridge;

// Mảng chiến lược: 3 chiến lược × N symbols
CTrendFollowerStrategy    *g_trends[];
CSessionBreakoutStrategy  *g_breakouts[];
CMeanReversionStrategy    *g_meanrevs[];

// Thống kê ngày
double   g_startEquity;
double   g_dailyPnL;
int      g_totalTrades;
int      g_winTrades;
datetime g_lastDailyReport;
datetime g_lastHeartbeatNotify;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit() {
   PrintFormat("=== MultiAssetEA v2 khởi động | Magic: %I64u ===", InpMagic);
   PrintFormat("Danh mục: %s | TF: %s", InpSymbols, EnumToString(InpTF));

   // --- Khởi tạo các hệ thống
   g_risk.Init(InpRiskPct, InpMaxDailyLoss, InpMaxWeeklyLoss,
               InpMaxTotalDD, InpBacktestDD, InpNewsBlackout, InpMaxDeviation);

   g_exec.Init(InpMagic, InpMaxDeviation);

   g_safety.Init(InpHeartbeatTimeout, InpHeartbeatEnabled);

   g_portfolio.Init(InpSymbols, InpMaxTrades, InpMaxPerSymbol, InpMagic);

   g_telegram.Init(InpTelegramToken, InpTelegramChatId, InpTelegramEnabled);

   // --- Khởi tạo chiến lược cho từng symbol
   int n = g_portfolio.GetSymCount();
   ArrayResize(g_trends,    n);
   ArrayResize(g_breakouts, n);
   ArrayResize(g_meanrevs,  n);

   for(int i = 0; i < n; i++) {
      string sym = g_portfolio.GetSymbol(i);

      g_trends[i]    = new CTrendFollowerStrategy();
      g_trends[i].Init(sym, InpTF);
      g_trends[i].Configure(InpEmaFast, InpEmaSlow, 200, InpAtrSlMult, InpRR_Trend);

      g_breakouts[i] = new CSessionBreakoutStrategy();
      g_breakouts[i].Init(sym, PERIOD_M15);
      g_breakouts[i].Configure(0.5, InpRR_Break, InpMinRangePips, 200.0);

      g_meanrevs[i]  = new CMeanReversionStrategy();
      g_meanrevs[i].Init(sym, InpTF);
      g_meanrevs[i].Configure(InpRsiPeriod, InpRsiOS, InpRsiOB, 20, 2.0, 20.0, InpRR_MeanRev, 1.0); // A13 FIX
   }

   // --- State
   g_startEquity       = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dailyPnL          = 0;
   g_totalTrades       = 0;
   g_winTrades         = 0;
   g_lastDailyReport   = 0;
   g_lastHeartbeatNotify = 0;

   g_telegram.NotifyRiskAlert("EA Started",
      StringFormat("MultiAssetEA v2 online\nSymbols: %s\nBalance: %.2f",
                   InpSymbols, AccountInfoDouble(ACCOUNT_BALANCE)));

   Print("[INIT] Hoàn tất. Sẵn sàng giao dịch.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   int n = g_portfolio.GetSymCount();
   for(int i = 0; i < n; i++) {
      if(g_trends[i])    { delete g_trends[i];    g_trends[i]    = NULL; }
      if(g_breakouts[i]) { delete g_breakouts[i]; g_breakouts[i] = NULL; }
      if(g_meanrevs[i])  { delete g_meanrevs[i];  g_meanrevs[i]  = NULL; }
   }
   g_telegram.NotifyRiskAlert("EA Stopped", StringFormat("Lý do deinit: %d", reason));
   Print("[DEINIT] MultiAssetEA v2 đã dừng.");
}

//+------------------------------------------------------------------+
//| OnTick - Hàm chính, gọi mỗi tick                                |
//+------------------------------------------------------------------+
void OnTick() {
   // 1. A6 FIX: Cập nhật Account State định kỳ sang FILE_COMMON trước CheckAllLimits
   g_bridge.WriteAccountState(g_risk);

   // 2. Kiểm tra Kill Switch từ xa
   if(g_bridge.CheckKillSwitch(g_risk, g_exec)) {
      return; // Hệ thống đã dừng khẩn cấp
   }

   // 3. A5 FIX: Kiểm tra Heartbeat từ Python Brain qua TimeGMT
   bool brainAlive = true;
   if(InpHeartbeatEnabled) {
      brainAlive = g_bridge.CheckHeartbeat(InpHeartbeatTimeout);
   }

   // 4. Kiểm tra Risk Officer (Daily/Weekly/Total DD)
   if(!g_risk.CheckAllLimits()) {
      if(!g_risk.IsHalted()) return;
      static datetime lastHaltMsg = 0;
      if(TimeCurrent() - lastHaltMsg > 300) {
         g_telegram.NotifyHalt(StringFormat("Circuit Breaker kích hoạt: %s", g_risk.GetHaltReason()));
         lastHaltMsg = TimeCurrent();
      }
      return;
   }

   // 5. Báo cáo hàng ngày (một lần vào đầu giờ)
   SendDailyReportIfNeeded();

   // 6. Heartbeat notify mỗi 4 giờ
   if(TimeCurrent() - g_lastHeartbeatNotify > 14400) {
      g_telegram.NotifyHeartbeat("OK");
      g_lastHeartbeatNotify = TimeCurrent();
   }

   // 7. Quản lý trailing và partial close cho các vị thế hiện có
   int n = g_portfolio.GetSymCount();
   for(int i = 0; i < n; i++) {
      string sym = g_portfolio.GetSymbol(i);
      g_exec.ManagePartialClose(sym);
      g_exec.ApplyAtrTrailing(sym, InpTF, InpTrailAtrMult);
   }

   // 8. A3 FIX: Xử lý tín hiệu đến từ Python Brain nếu Brain đang alive
   if(brainAlive) {
      g_bridge.ProcessBrainSignals(g_risk, g_exec, g_safety, g_portfolio, InpSymbols);
   }

   // 9. Quét tín hiệu và mở lệnh nội tại (MQL5 Strategies)
   for(int i = 0; i < n; i++) {
      string sym = g_portfolio.GetSymbol(i);

      // Kiểm tra phiên giao dịch
      if(!g_safety.IsTradingSessionActive(sym)) continue;

      // P0 FIX: Kiểm tra News Blackout từ Python Brain thực tế
      if(g_bridge.CheckNewsBlackout()) {
         static datetime lastNewsWarn = 0;
         if(TimeCurrent() - lastNewsWarn > 300) {
            PrintFormat("[SAFETY] %s: Đang trong thời gian News Blackout quanh tin tức lớn. Tạm dừng mở lệnh.", sym);
            lastNewsWarn = TimeCurrent();
         }
         continue;
      }

      // Kiểm tra spread
      if(!g_risk.IsSpreadOk(sym, InpTF)) continue;

      // Nhận diện regime hiện tại
      ENUM_MARKET_REGIME regime = DetectRegime(sym, PERIOD_H4);
      if(regime == REGIME_VOLATILE) {
         static datetime lastVolWarn[]; // tránh spam
         continue; // Đứng ngoài khi biến động bất thường
      }

      // Kiểm tra có thể mở lệnh mới không
      // (sẽ kiểm tra sau khi có tín hiệu để log chính xác hơn)

      SignalPacket sig;

      // --- Chọn chiến lược theo regime
      bool gotSignal = false;

      if(InpUseTrend && regime == REGIME_TREND && g_trends[i] != NULL) {
         gotSignal = g_trends[i].GenerateSignal(sig);
      }
      else if(InpUseBreakout && regime == REGIME_BREAKOUT && g_breakouts[i] != NULL) {
         gotSignal = g_breakouts[i].GenerateSignal(sig);
      }
      else if(InpUseMeanRev && regime == REGIME_RANGE && g_meanrevs[i] != NULL) {
         gotSignal = g_meanrevs[i].GenerateSignal(sig);
      }

      if(!gotSignal || sig.type == SIGNAL_NONE) continue;

      // --- Portfolio Manager kiểm tra giới hạn và tương quan
      if(!g_portfolio.CanOpenNew(sym, sig.type)) continue;

      // --- Tính lot (Risk Officer)
      double lot = g_risk.CalcLot(sym, sig.entryPrice, sig.stopLoss);
      if(lot <= 0) continue;

      // --- Thực thi lệnh
      if(g_exec.OpenOrder(sig, lot)) {
         g_totalTrades++;
         g_telegram.NotifyOrderOpen(sym,
            (sig.type==SIGNAL_BUY?"BUY":"SELL"),
            lot, sig.entryPrice, sig.stopLoss, sig.takeProfit1, sig.strategyName);
      }
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction - Theo dõi kết quả giao dịch                 |
//+------------------------------------------------------------------+
//| OnTradeTransaction - Theo dõi kết quả giao dịch (P0 FIX)         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req,
                        const MqlTradeResult &result) {
   // Chỉ xử lý sự kiện deal được thêm vào history
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal == 0) return;

   // P0 FIX: Kiểm tra DEAL_ENTRY_OUT hoặc DEAL_ENTRY_INOUT (chính xác các deal đóng lệnh)
   if(HistoryDealSelect(trans.deal)) {
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) return;

      ulong magic = (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
      // Kiểm tra deal thuộc EA này hoặc các chiến lược con của EA
      if(magic != InpMagic && (magic < 1001 || magic > 1004)) return;

      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      bool isWin = (profit > 0);
      g_dailyPnL += profit;

      // Kích hoạt giảm size sau chuỗi thua
      g_risk.OnTradeResult(isWin);
      if(isWin) g_winTrades++;

      double winRate = (g_totalTrades > 0) ? (double)g_winTrades / g_totalTrades * 100.0 : 0.0;

      g_telegram.NotifyOrderClose(
         HistoryDealGetString(trans.deal, DEAL_SYMBOL),
         profit, (isWin ? "TP chạm" : "SL chạm"), g_totalTrades, winRate);
   }
}

//+------------------------------------------------------------------+
//| Báo cáo ngày (một lần vào đầu mỗi ngày)                         |
//+------------------------------------------------------------------+
void SendDailyReportIfNeeded() {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   // Gửi lúc 00:05 UTC mỗi ngày
   if(dt.hour == 0 && dt.min >= 5 && dt.min <= 10) {
      datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:05", dt.year, dt.mon, dt.day));
      if(today > g_lastDailyReport) {
         g_lastDailyReport = today;

         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
         double startEq = g_risk.GetDailyStartingEquity();
         double ddPct   = (startEq > 0) ? (startEq - equity) / startEq * 100.0 : 0;
         double winRate = (g_totalTrades > 0) ? (double)g_winTrades / g_totalTrades * 100.0 : 0;

         g_telegram.NotifyDailyReport(balance, equity, g_dailyPnL, ddPct, g_totalTrades, winRate);

         // Reset PnL ngày
         g_dailyPnL   = 0;
         g_startEquity = equity;
      }
   }
}
