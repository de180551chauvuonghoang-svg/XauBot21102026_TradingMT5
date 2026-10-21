//+------------------------------------------------------------------+
//|                                              ExecutionEngine.mqh |
//|                              MultiAssetEA v2 - Quant Trading     |
//|  Thực thi lệnh: SL cứng bắt buộc, partial close, trailing       |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Team"
#property version   "2.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include "Definitions.mqh"

class CExecutionEngine {
private:
   CTrade         m_trade;
   CPositionInfo  m_posInfo;
   ulong          m_magic;
   int            m_maxDeviation;

   double GetAsk(const string sym) { return SymbolInfoDouble(sym, SYMBOL_ASK); }
   double GetBid(const string sym) { return SymbolInfoDouble(sym, SYMBOL_BID); }

public:
   CExecutionEngine() : m_magic(202610), m_maxDeviation(20) {}

   void Init(ulong magic, int deviation = 20) {
      m_magic        = magic;
      m_maxDeviation = deviation;
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_maxDeviation);
      Print("[ExecutionEngine] Khởi tạo. Magic: ", magic, " | Deviation: ", deviation, " pts");
   }

   // Mở lệnh với SL cứng bắt buộc (theo quy tắc README: không lệnh nào thiếu SL)
   bool OpenOrder(const SignalPacket &sig, double volume) {
      if(sig.stopLoss == 0) {
         Print("[EXEC ERROR] Lệnh bị từ chối: KHÔNG CÓ SL CỨNG! (", sig.symbol, ")");
         return false;
      }

      int    digits = (int)SymbolInfoInteger(sig.symbol, SYMBOL_DIGITS);
      double price  = (sig.type == SIGNAL_BUY) ? GetAsk(sig.symbol) : GetBid(sig.symbol);
      double sl     = NormalizeDouble(sig.stopLoss,   digits);
      double tp     = NormalizeDouble(sig.takeProfit1, digits);

      m_trade.SetTypeFillingBySymbol(sig.symbol);

      bool ok = false;
      string comment = StringFormat("EA|%s|%.2f", sig.strategyName, sig.confidence);

      if(sig.type == SIGNAL_BUY) {
         ok = m_trade.Buy(volume, sig.symbol, price, sl, tp, comment);
      } else if(sig.type == SIGNAL_SELL) {
         ok = m_trade.Sell(volume, sig.symbol, price, sl, tp, comment);
      }

      if(ok) {
         PrintFormat("[EXEC] ✅ %s %s %.2f lot | Entry: %.5f | SL: %.5f | TP1: %.5f | Confidence: %.0f%%",
                     (sig.type==SIGNAL_BUY?"BUY":"SELL"), sig.symbol, volume, price, sl, tp, sig.confidence*100);
      } else {
         PrintFormat("[EXEC ERROR] ❌ %s %s: Code %d - %s",
                     (sig.type==SIGNAL_BUY?"BUY":"SELL"), sig.symbol,
                     m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
      }
      return ok;
   }

   // Đóng 50% tại TP1, dời SL về hòa vốn (partial close strategy)
   void ManagePartialClose(const string symbol, double tp1Distance = 0) {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(!m_posInfo.SelectByIndex(i)) continue;
         if(m_posInfo.Symbol() != symbol || m_posInfo.Magic() != m_magic) continue;

         double openPrice    = m_posInfo.PriceOpen();
         double currentPrice = m_posInfo.PriceCurrent();
         double tp           = m_posInfo.TakeProfit();
         double sl           = m_posInfo.StopLoss();
         double volume       = m_posInfo.Volume();
         ulong  ticket       = m_posInfo.Ticket();
         int    digits       = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

         // Tính khoảng cách TP1: 0.7R–1R
         double targetDist = (tp1Distance > 0) ? tp1Distance : MathAbs(openPrice - sl) * 0.85;
         bool   atTP1      = false;

         if(m_posInfo.PositionType() == POSITION_TYPE_BUY && currentPrice >= openPrice + targetDist) atTP1 = true;
         if(m_posInfo.PositionType() == POSITION_TYPE_SELL && currentPrice <= openPrice - targetDist) atTP1 = true;

         // Chỉ đóng 50% một lần - dùng comment để đánh dấu
         if(atTP1 && StringFind(m_posInfo.Comment(), "PARTIAL") < 0) {
            double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            double halfLot = NormalizeDouble(volume * 0.5, 2);
            if(halfLot < minLot) halfLot = volume;

            if(m_trade.PositionClosePartial(ticket, halfLot)) {
               // Dời SL về hòa vốn + 2 pts
               double newSl = NormalizeDouble(openPrice + 2 * SymbolInfoDouble(symbol, SYMBOL_POINT)
                              * (m_posInfo.PositionType()==POSITION_TYPE_BUY ? 1 : -1), digits);
               m_trade.PositionModify(ticket, newSl, tp);
               PrintFormat("[EXEC] Partial close 50%% %s #%I64u. SL dời về %.5f (hòa vốn+2pt)", symbol, ticket, newSl);
            }
         }
      }
   }

   // Trailing stop theo ATR (phần còn lại sau partial close)
   void ApplyAtrTrailing(const string symbol, ENUM_TIMEFRAMES tf = PERIOD_H1, double atrMult = 1.5) {
      double atrBuf[];
      int handle = iATR(symbol, tf, 14);
      if(handle == INVALID_HANDLE) return;
      if(CopyBuffer(handle, 0, 0, 1, atrBuf) < 1) { IndicatorRelease(handle); return; }
      IndicatorRelease(handle);

      double atr    = atrBuf[0];
      double trail  = atr * atrMult;
      int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(!m_posInfo.SelectByIndex(i)) continue;
         if(m_posInfo.Symbol() != symbol || m_posInfo.Magic() != m_magic) continue;

         double current = m_posInfo.PriceCurrent();
         double curSl   = m_posInfo.StopLoss();
         ulong  ticket  = m_posInfo.Ticket();

         if(m_posInfo.PositionType() == POSITION_TYPE_BUY) {
            double newSl = NormalizeDouble(current - trail, digits);
            if(newSl > curSl && newSl > m_posInfo.PriceOpen()) {
               m_trade.PositionModify(ticket, newSl, m_posInfo.TakeProfit());
            }
         } else if(m_posInfo.PositionType() == POSITION_TYPE_SELL) {
            double newSl = NormalizeDouble(current + trail, digits);
            if(curSl == 0 || (newSl < curSl && newSl < m_posInfo.PriceOpen())) {
               m_trade.PositionModify(ticket, newSl, m_posInfo.TakeProfit());
            }
         }
      }
   }

   // Đóng tất cả lệnh của một symbol (dùng khi halt)
   void CloseAll(const string symbol = "") {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(!m_posInfo.SelectByIndex(i)) continue;
         if(m_posInfo.Magic() != m_magic) continue;
         if(symbol != "" && m_posInfo.Symbol() != symbol) continue;
         m_trade.PositionClose(m_posInfo.Ticket());
      }
   }

   int CountPositions(const string symbol = "") {
      int cnt = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(!m_posInfo.SelectByIndex(i)) continue;
         if(m_posInfo.Magic() != m_magic) continue;
         if(symbol != "" && m_posInfo.Symbol() != symbol) continue;
         cnt++;
      }
      return cnt;
   }

   ulong GetMagic() const { return m_magic; }
};
