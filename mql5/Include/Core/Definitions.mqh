//+------------------------------------------------------------------+
//|                                                  Definitions.mqh |
//|                              MultiAssetEA v2 - Quant Trading     |
//|                           Copyright 2026, Quant Trading Team     |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Team"
#property version   "2.00"

//--- Signal types
enum ENUM_SIGNAL_TYPE {
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1,
   SIGNAL_CLOSE_BUY  = 2,
   SIGNAL_CLOSE_SELL = -2,
   SIGNAL_CLOSE_ALL  = 3,
   SIGNAL_HALT       = 99
};

//--- Market regime
enum ENUM_MARKET_REGIME {
   REGIME_UNKNOWN  = 0,
   REGIME_TREND    = 1,
   REGIME_RANGE    = 2,
   REGIME_BREAKOUT = 3,
   REGIME_VOLATILE = 4
};

//--- Lot calculation mode
enum ENUM_LOT_MODE {
   LOT_FIXED         = 0,
   LOT_RISK_PERCENT  = 1,
   LOT_ATR_VOLATILITY= 2
};

//--- Magic numbers riêng biệt cho từng chiến lược
#define MAGIC_TREND_FOLLOWER    1001
#define MAGIC_SESSION_BREAKOUT  1002
#define MAGIC_MEAN_REVERSION    1003
#define MAGIC_BRAIN_AI          1004

//--- Trade signal packet from Brain or strategy
struct SignalPacket {
   string            symbol;
   ENUM_TIMEFRAMES   timeframe;
   ENUM_SIGNAL_TYPE  type;
   ENUM_MARKET_REGIME regime;
   double            entryPrice;
   double            stopLoss;
   double            takeProfit1;      // Chốt 50% vị thế
   double            takeProfit2;      // Chốt phần còn lại (trailing)
   double            confidence;       // 0.0–1.0
   string            strategyName;
   string            comment;
   datetime          signalTime;
   ulong             magic;            // Magic number định danh chiến lược
};

//--- Account risk snapshot
struct AccountRiskSnapshot {
   double balance;
   double equity;
   double freeMargin;
   double dailyStartEquity;
   double dailyDrawdownPct;
   double weeklyStartEquity;
   double weeklyDrawdownPct;
   bool   isHalted;
};

//--- Error codes
#define ERR_SPREAD_TOO_HIGH   10001
#define ERR_SLIPPAGE_TOO_HIGH 10002
#define ERR_DD_EXCEEDED       10003
#define ERR_NEWS_BLACKOUT     10004
#define ERR_NO_HARD_SL        10005
#define ERR_HEARTBEAT_LOST    10006
