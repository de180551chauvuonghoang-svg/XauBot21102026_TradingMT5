"""
Bull Agent & Bear Agent - Debate & Thesis Counter-Argument
===========================================================
Mỗi setup trước khi được duyệt phải qua tranh luận giữa Bull và Bear:
- Bull Agent: Nêu luận điểm ủng hộ setup, động lực giá và mục tiêu.
- Bear Agent: Tìm rủi ro, điểm cản trở, tin tức sắp ra và điều kiện làm setup thất bại.

Nếu Bear chỉ ra rủi ro vĩ mô lớn hoặc mâu thuẫn cản mạnh, HeadTrader sẽ giảm size 50% hoặc bỏ lệnh.
"""
import logging
from typing import Dict, Any

logger = logging.getLogger("BullBearDebate")


class BullAgent:
    """Đại diện cho phe bò: Tìm kiếm các yếu tố củng cố xu hướng tăng / mua."""
    def evaluate(self, symbol: str, action: str, macro_bias: Dict[str, Any], quant_signal: Dict[str, Any]) -> Dict[str, Any]:
        bias_info = macro_bias.get("symbols_bias", {}).get(symbol, {})
        bias = bias_info.get("bias", "NEUTRAL")
        
        thesis = []
        confidence_boost = 0.0

        if action == "BUY":
            if bias == "BULLISH":
                thesis.append(f"Vĩ mô đồng thuận Bullish: {bias_info.get('reason')}")
                confidence_boost += 0.15
            if quant_signal.get("regime") == "TREND":
                thesis.append("Động lượng xu hướng EMA đang hỗ trợ mạnh")
                confidence_boost += 0.10
        elif action == "SELL":
            if bias == "BEARISH":
                thesis.append(f"Vĩ mô ủng hộ Bearish: {bias_info.get('reason')}")
                confidence_boost += 0.15

        return {
            "supported": len(thesis) > 0,
            "thesis": thesis,
            "boost": confidence_boost,
        }


class BearAgent:
    """Đại diện cho phe gấu / phản biện rủi ro: Tìm kiếm điểm sai của luận điểm."""
    def evaluate(self, symbol: str, action: str, macro_bias: Dict[str, Any], quant_signal: Dict[str, Any]) -> Dict[str, Any]:
        bias_info = macro_bias.get("symbols_bias", {}).get(symbol, {})
        bias = bias_info.get("bias", "NEUTRAL")
        warning_flags = macro_bias.get("warning_flags", [])

        risks = []
        veto_flag = False
        penalty = 0.0

        # Kiểm tra mâu thuẫn vĩ mô
        if action == "BUY" and bias == "BEARISH":
            risks.append(f"Nguy hiểm: Mua ngược chiều dòng tiền vĩ mô ({bias_info.get('reason')})")
            veto_flag = True

        if action == "SELL" and bias == "BULLISH":
            risks.append(f"Nguy hiểm: Bán ngược chiều dòng tiền vĩ mô ({bias_info.get('reason')})")
            veto_flag = True

        # Cảnh báo rủi ro biến động
        if warning_flags:
            risks.append(f"Cảnh báo vĩ mô tồn tại: {', '.join(warning_flags)}")
            penalty += 0.10

        return {
            "risks_found": len(risks) > 0,
            "risks": risks,
            "penalty": penalty,
            "veto": veto_flag,
        }
