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
   ulong          m_partialTickets[];

   double GetAsk(const string sym) { return SymbolInfoDouble(sym, SYMBOL_ASK); }
   double GetBid(const string sym) { return SymbolInfoDouble(sym, SYMBOL_BID); }

   bool IsAlreadyPartiallyClosed(ulong ticket, ENUM_POSITION_TYPE pType, double openPrice, double sl) {
      for(int i = 0; i < ArraySize(m_partialTickets); i++) {
         if(m_partialTickets[i] == ticket) return true;
      }
      if(pType == POSITION_TYPE_BUY && sl >= openPrice) return true;
      if(pType == POSITION_TYPE_SELL && sl > 0 && sl <= openPrice) return true;
      return false;
   }

   void MarkTicketPartiallyClosed(ulong ticket) {
      int sz = ArraySize(m_partialTickets);
      ArrayResize(m_partialTickets, sz + 1);
      m_partialTickets[sz] = ticket;
   }

public:
   CExecutionEngine() : m_magic(202610), m_maxDeviation(20) {}

   void Init(ulong magic, int deviation = 20) {
      m_magic        = magic;
      m_maxDeviation = deviation;
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_maxDeviation);
      ArrayResize(m_partialTickets, 0);
      Print("[ExecutionEngine] Khởi tạo. Magic: ", magic, " | Deviation: ", deviation, " pts");
   }

   // Mở lệnh với SL cứng bắt buộc (theo quy tắc README: không lệnh nào thiếu SL)
   bool OpenOrder(const SignalPacket &sig, double volume) {
      if(sig.stopLoss == 0) {
         Print("[EXEC ERROR] Lệnh bị từ chối: KHÔNG CÓ SL CỨNG! (", sig.symbol, ")");
         return false;
      }

      ulong orderMagic = (sig.magic > 0) ? sig.magic : m_magic;
      m_trade.SetExpertMagicNumber(orderMagic);

      int    digits = (int)SymbolInfoInteger(sig.symbol, SYMBOL_DIGITS);
      double price  = (sig.type == SIGNAL_BUY) ? GetAsk(sig.symbol) : GetBid(sig.symbol);
      double sl     = NormalizeDouble(sig.stopLoss,   digits);
      double tp     = NormalizeDouble(sig.takeProfit1, digits);

      m_trade.SetTypeFillingBySymbol(sig.symbol);

      bool ok = false;
      string comment = StringFormat("%s|m:%I64u", sig.strategyName, orderMagic);

      if(sig.type == SIGNAL_BUY) {
         ok = m_trade.Buy(volume, sig.symbol, price, sl, tp, comment);
      } else if(sig.type == SIGNAL_SELL) {
         ok = m_trade.Sell(volume, sig.symbol, price, sl, tp, comment);
      }

      if(ok) {
         PrintFormat("[EXEC] ✅ %s %s %.2f lot | Entry: %.5f | SL: %.5f | TP1: %.5f | Magic: %I64u",
                     (sig.type==SIGNAL_BUY?"BUY":"SELL"), sig.symbol, volume, price, sl, tp, orderMagic);
      } else {
         PrintFormat("[EXEC ERROR] ❌ %s %s: Code %d - %s",
                     (sig.type==SIGNAL_BUY?"BUY":"SELL"), sig.symbol,
                     m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
      }
      return ok;
   }

   // Đóng 50% tại TP1, dời SL về hòa vốn (partial close strategy - chỉ đóng 1 lần)
   void ManagePartialClose(const string symbol, double tp1Distance = 0) {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(!m_posInfo.SelectByIndex(i)) continue;
         if(m_posInfo.Symbol() != symbol) continue;

         // Chấp nhận magic thuộc về EA này
         if(!IsOurMagic(m_posInfo.Magic())) continue;

         double openPrice    = m_posInfo.PriceOpen();
         double currentPrice = m_posInfo.PriceCurrent();
         double tp           = m_posInfo.TakeProfit();
         double sl           = m_posInfo.StopLoss();
         double volume       = m_posInfo.Volume();
         ulong  ticket       = m_posInfo.Ticket();
         int    digits       = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         ENUM_POSITION_TYPE pType = m_posInfo.PositionType();

         // Kiểm tra nếu lệnh này đã từng partial close hoặc đã dời SL về BE rồi thì bỏ qua
         if(IsAlreadyPartiallyClosed(ticket, pType, openPrice, sl)) continue;

         // Tính khoảng cách TP1: 0.7R–1R
         double targetDist = (tp1Distance > 0) ? tp1Distance : MathAbs(openPrice - sl) * 0.85;
         bool   atTP1      = false;

         if(pType == POSITION_TYPE_BUY && currentPrice >= openPrice + targetDist)  atTP1 = true;
         if(pType == POSITION_TYPE_SELL && currentPrice <= openPrice - targetDist) atTP1 = true;

         // Chỉ đóng 50% một lần duy nhất
         if(atTP1) {
            double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
            if(minLot <= 0) minLot = 0.01;
            if(stepLot <= 0) stepLot = 0.01;

            // A9 FIX: Nếu volume < 2 * lot tối thiểu (ví dụ 0.01 lot trên tài khoản $500),
            // không đóng 100% ở 0.85R mà chỉ dời SL về BE để bảo toàn tỷ lệ R:R thiết kế.
            if(volume < 2.0 * minLot) {
               MarkTicketPartiallyClosed(ticket);
               double newSl = NormalizeDouble(openPrice + 2 * SymbolInfoDouble(symbol, SYMBOL_POINT)
                              * (pType == POSITION_TYPE_BUY ? 1 : -1), digits);
               if((pType == POSITION_TYPE_BUY && newSl > sl) || (pType == POSITION_TYPE_SELL && (sl == 0 || newSl < sl))) {
                  m_trade.PositionModify(ticket, newSl, tp);
                  PrintFormat("[EXEC] %s #%I64u: volume %.2f < 2*minLot (%.2f). Không partial, dời SL về BE %.5f để chạy tiếp tới TP.",
                              symbol, ticket, volume, minLot, newSl);
               }
               continue;
            }

            double halfLot = MathFloor((volume * 0.5) / stepLot) * stepLot;
            halfLot = NormalizeDouble(halfLot, 2);

            if(halfLot >= minLot && (volume - halfLot) >= minLot) {
               if(m_trade.PositionClosePartial(ticket, halfLot)) {
                  MarkTicketPartiallyClosed(ticket);
                  double newSl = NormalizeDouble(openPrice + 2 * SymbolInfoDouble(symbol, SYMBOL_POINT)
                                 * (pType == POSITION_TYPE_BUY ? 1 : -1), digits);
                  m_trade.PositionModify(ticket, newSl, tp);
                  PrintFormat("[EXEC] Partial close 50%% %s #%I64u (%.2f lot). SL dời về %.5f (hòa vốn+2pt)", symbol, ticket, halfLot, newSl);
               }
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
         if(m_posInfo.Symbol() != symbol || !IsOurMagic(m_posInfo.Magic())) continue;

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

   // Đóng tất cả lệnh của một symbol (dùng khi halt / kill switch)
   void CloseAll(const string symbol = "") {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(!m_posInfo.SelectByIndex(i)) continue;
         if(!IsOurMagic(m_posInfo.Magic())) continue;
         if(symbol != "" && m_posInfo.Symbol() != symbol) continue;
         m_trade.PositionClose(m_posInfo.Ticket());
      }
   }

   int CountPositions(const string symbol = "") {
      int cnt = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(!m_posInfo.SelectByIndex(i)) continue;
         if(!IsOurMagic(m_posInfo.Magic())) continue;
         if(symbol != "" && m_posInfo.Symbol() != symbol) continue;
         cnt++;
      }
      return cnt;
   }

   ulong GetMagic() const { return m_magic; }
};
