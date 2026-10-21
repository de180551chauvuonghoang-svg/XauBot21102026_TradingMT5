//+------------------------------------------------------------------+
//|                                           PortfolioManager.mqh  |
//|                              MultiAssetEA v2 - Quant Trading     |
//|  Kiểm soát exposure tương quan và giới hạn vị thế đa tài sản   |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Team"
#property version   "2.00"

#include "Definitions.mqh"
#include <Trade\PositionInfo.mqh>

class CPortfolioManager {
private:
   string        m_symbols[];
   int           m_symCount;
   int           m_maxTotalTrades;
   int           m_maxPerSymbol;
   ulong         m_magic;
   CPositionInfo m_posInfo;

   // Nhóm tương quan: không được mở quá N vị thế cùng chiều trong 1 nhóm
   struct CorrelGroup {
      string syms[8];
      int    count;
      int    maxSameDir;
      string name;
   };
   CorrelGroup m_groups[5];
   int         m_groupCount;

public:
   CPortfolioManager() : m_symCount(0), m_maxTotalTrades(5), m_maxPerSymbol(1), m_magic(202610), m_groupCount(0) {}

   void Init(string symbolsCsv, int maxTotal, int maxPerSym, ulong magic) {
      m_maxTotalTrades = maxTotal;
      m_maxPerSymbol   = maxPerSym;
      m_magic          = magic;
      m_symCount       = 0;
      ArrayResize(m_symbols, 0);

      string parts[];
      int n = StringSplit(symbolsCsv, ',', parts);
      for(int i = 0; i < n; i++) {
         string s = parts[i];
         StringTrimLeft(s); StringTrimRight(s);
         if(StringLen(s) > 0 && SymbolSelect(s, true)) {
            ArrayResize(m_symbols, m_symCount + 1);
            m_symbols[m_symCount++] = s;
            PrintFormat("[Portfolio] Thêm tài sản: %s", s);
         } else if(StringLen(s) > 0) {
            PrintFormat("[Portfolio] CẢNH BÁO: Symbol '%s' không tìm thấy trên broker!", s);
         }
      }

      // Thiết lập nhóm tương quan mặc định theo README
      AddCorrelGroup("USD_Group", "EURUSD,GBPUSD,XAUUSD", 1);
      AddCorrelGroup("US_Equities", "US30,NAS100", 1);
   }

   void AddCorrelGroup(string name, string symbolsCsv, int maxSameDir = 1) {
      if(m_groupCount >= 5) return;
      string parts[];
      int n = StringSplit(symbolsCsv, ',', parts);
      m_groups[m_groupCount].count      = 0;
      m_groups[m_groupCount].maxSameDir = maxSameDir;
      m_groups[m_groupCount].name       = name;
      for(int i = 0; i < n && i < 8; i++) {
         string s = parts[i]; StringTrimLeft(s); StringTrimRight(s);
         m_groups[m_groupCount].syms[m_groups[m_groupCount].count++] = s;
      }
      m_groupCount++;
      PrintFormat("[Portfolio] Nhóm tương quan '%s': %d cặp, max %d cùng chiều", name, n, maxSameDir);
   }

   int GetSymCount() const { return m_symCount; }
   string GetSymbol(int i) const { return (i >= 0 && i < m_symCount) ? m_symbols[i] : ""; }

   int TotalOpenPositions() {
      int cnt = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(m_posInfo.SelectByIndex(i) && m_posInfo.Magic() == m_magic) cnt++;
      }
      return cnt;
   }

   int SymbolOpenPositions(const string sym) {
      int cnt = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(m_posInfo.SelectByIndex(i) && m_posInfo.Magic() == m_magic && m_posInfo.Symbol() == sym) cnt++;
      }
      return cnt;
   }

   // Kiểm tra exposure nhóm tương quan
   bool IsCorrelationOk(const string symbol, ENUM_SIGNAL_TYPE signalType) {
      for(int g = 0; g < m_groupCount; g++) {
         bool inGroup = false;
         for(int s = 0; s < m_groups[g].count; s++) {
            if(m_groups[g].syms[s] == symbol) { inGroup = true; break; }
         }
         if(!inGroup) continue;

         // Đếm số vị thế cùng chiều trong nhóm
         int sameDirCount = 0;
         ENUM_POSITION_TYPE posType = (signalType == SIGNAL_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(!m_posInfo.SelectByIndex(i) || m_posInfo.Magic() != m_magic) continue;
            for(int s = 0; s < m_groups[g].count; s++) {
               if(m_posInfo.Symbol() == m_groups[g].syms[s] && m_posInfo.PositionType() == posType) {
                  sameDirCount++;
               }
            }
         }

         if(sameDirCount >= m_groups[g].maxSameDir) {
            PrintFormat("[Portfolio] Từ chối %s: Nhóm '%s' đã có %d vị thế cùng chiều (max: %d)",
                        symbol, m_groups[g].name, sameDirCount, m_groups[g].maxSameDir);
            return false;
         }
      }
      return true;
   }

   bool CanOpenNew(const string symbol, ENUM_SIGNAL_TYPE signalType) {
      if(TotalOpenPositions() >= m_maxTotalTrades) {
         PrintFormat("[Portfolio] Đã đạt tổng giới hạn %d lệnh!", m_maxTotalTrades);
         return false;
      }
      if(SymbolOpenPositions(symbol) >= m_maxPerSymbol) return false;
      if(!IsCorrelationOk(symbol, signalType)) return false;
      return true;
   }
};
