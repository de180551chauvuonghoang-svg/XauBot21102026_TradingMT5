"""
Macro Analyst - Cross-Asset Context & Sentiment
===============================================
Đánh giá bối cảnh vĩ mô toàn cầu, trạng thái Risk-On / Risk-Off,
sức mạnh USD (DXY), và xác lập thiên hướng (bias) cho từng lớp tài sản:
Kim loại (XAUUSD), Ngoại hối (EUR, GBP, JPY), Chỉ số (US30, NAS100), Năng lượng (USOIL).
"""
import logging
from pathlib import Path
from typing import Dict, Any

logger = logging.getLogger("MacroAnalyst")


class MacroAnalyst:
    """
    Chuyên viên phân tích vĩ mô của quỹ.
    Chuyển đổi dữ liệu tin tức vĩ mô thành bias có cấu trúc cho từng tài sản.
    """

    def __init__(self, config_path: Path):
        self.config_path = config_path
        logger.info("MacroAnalyst sẵn sàng.")

    def analyze(self, research_summary: Dict[str, Any]) -> Dict[str, Any]:
        """
        Phân tích kết quả nghiên cứu và trả về Macro Bias có cấu trúc.
        """
        analysis = research_summary.get("analysis", {})
        macro_sentiment = analysis.get("macro_sentiment", "NEUTRAL")
        dxy_bias        = analysis.get("dxy_bias", "NEUTRAL")
        symbols_bias    = analysis.get("symbols_bias", {})
        warning_flags   = analysis.get("warning_flags", [])

        logger.info(f"MacroAnalyst: Trạng thái thị trường = {macro_sentiment} | DXY Bias = {dxy_bias}")

        return {
            "macro_sentiment": macro_sentiment,
            "dxy_bias": dxy_bias,
            "symbols_bias": symbols_bias,
            "warning_flags": warning_flags,
            "summary": analysis.get("summary", ""),
        }
