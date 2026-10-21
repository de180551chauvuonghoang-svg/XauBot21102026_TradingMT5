"""
Head Trader - Consensus Arbiter & Trade Authorizer
==================================================
Tổng hợp thông tin từ:
1. Research Agent (Tin tức 4 nguồn qua Groq LLM)
2. Macro Analyst (Thiên hướng vĩ mô đa tài sản)
3. Quant Analyst (Tín hiệu kỹ thuật & Regime)
4. Risk Officer (Quyền phủ quyết tuyệt đối - VETO)

Nguyên tắc: Chỉ duyệt lệnh khi Kỹ Thuật + Vĩ Mô + Quản Trị Rủi Ro đồng thuận!
"""
import logging
from pathlib import Path
from typing import List, Dict, Any, Optional

from risk.risk_officer import RiskOfficer
from agents.bull_bear import BullAgent, BearAgent

logger = logging.getLogger("HeadTrader")


class HeadTrader:
    """
    Trưởng nhóm giao dịch (Head Trader / Judge).
    Quyết định phê duyệt tín hiệu cuối cùng trước khi chuyển sang MT5 Execution.
    """

    def __init__(self, config_path: Path, risk_officer: RiskOfficer):
        self.config_path = config_path
        self.risk_officer = risk_officer
        self.bull_agent = BullAgent()
        self.bear_agent = BearAgent()
        logger.info("HeadTrader sẵn sàng: Quản lý phê duyệt tín hiệu giao dịch với Bull vs Bear.")

    def decide(
        self,
        macro_bias: Dict[str, Any],
        quant_signals: List[Dict[str, Any]],
        research_summary: Dict[str, Any],
        account_state: Optional[Dict[str, Any]] = None,
    ) -> List[Dict[str, Any]]:
        """
        Đối chiếu tín hiệu kỹ thuật với thiên hướng vĩ mô LLM và kiểm tra quy tắc rủi ro thật.
        """
        approved_signals = []
        symbols_bias = macro_bias.get("symbols_bias", {})

        current_account_state = account_state or {
            "daily_loss_pct": 0.0,
            "weekly_loss_pct": 0.0,
            "total_dd_pct": 0.0,
            "equity": 10000.0,
        }

        for signal in quant_signals:
            symbol = signal["symbol"]
            action = signal["action"]  # BUY hoặc SELL

            # 1. Kiểm tra đối chiếu Vĩ Mô (Macro Consensus)
            sym_macro = symbols_bias.get(symbol, {})
            bias = sym_macro.get("bias", "NEUTRAL")

            # Nếu kỹ thuật mua (BUY) mà vĩ mô cảnh báo xu hướng giảm mạnh (BEARISH) -> Bỏ qua
            if action == "BUY" and bias == "BEARISH":
                logger.info(f"HeadTrader từ chối {symbol} BUY: Mâu thuẫn với Vĩ mô (Macro Bearish: {sym_macro.get('reason')})")
                continue

            # Nếu kỹ thuật bán (SELL) mà vĩ mô cảnh báo xu hướng tăng mạnh (BULLISH) -> Bỏ qua
            if action == "SELL" and bias == "BULLISH":
                logger.info(f"HeadTrader từ chối {symbol} SELL: Mâu thuẫn với Vĩ mô (Macro Bullish: {sym_macro.get('reason')})")
                continue

            # 2. Tranh luận Bull vs Bear (Phản biện rủi ro trước khi duyệt)
            bear_eval = self.bear_agent.evaluate(symbol, action, macro_bias, signal)
            bull_eval = self.bull_agent.evaluate(symbol, action, macro_bias, signal)

            if bear_eval["veto"]:
                logger.warning(f"Bear Agent VETO setup {symbol} {action}: {', '.join(bear_eval['risks'])}")
                continue

            # 3. Chuẩn hóa format tín hiệu cho RiskOfficer
            formatted_signal = {
                "symbol": symbol,
                "type": action,
                "price": signal["price"],
                "stop_loss": signal["sl"],
                "take_profit": signal["tp"],
                "confidence": signal.get("confidence", 70) / 100.0 if signal.get("confidence", 70) > 1 else signal.get("confidence", 0.7),
                "strategy": signal.get("strategy", "MeanReversion"),
                "magic": 1004,
            }

            # 3. P0 FIX: Kiểm tra quyền phủ quyết của Risk Officer với dữ liệu tài khoản thật
            approved, reason = self.risk_officer.veto(formatted_signal, current_account_state)
            if not approved:
                logger.warning(f"Risk Officer VETO lệnh {symbol} {action}: {reason}")
                continue

            # 4. Tính toán lot size dựa trên equity thật và khoảng cách SL
            equity = current_account_state.get("equity", 10000.0)
            sl_dist = abs(signal["price"] - signal["sl"])
            risk_cash = equity * 0.005  # 0.5% rủi ro
            
            # Ước lượng lot size tương đối an toàn
            calculated_lot = round(max(0.01, min(1.0, risk_cash / max(10.0, sl_dist * 100))), 2)
            size_factor = self.risk_officer.get_size_factor()
            final_lot = round(calculated_lot * size_factor, 2)
            if final_lot < 0.01:
                final_lot = 0.01

            signal["lots"] = final_lot
            signal["magic"] = 1004
            signal["approved_by"] = "HeadTrader"
            signal["macro_alignment"] = bias
            approved_signals.append(signal)

            logger.info(
                f"✅ HeadTrader ĐÃ DUYỆT: {symbol} {action} {signal['lots']} lots | "
                f"Macro: {bias} | Strategy: {signal.get('strategy')} | Magic: 1004"
            )

        return approved_signals
