"""
Research Agent - Multi-Source Financial News & Calendar Intelligence
=====================================================================
Thu thập dữ liệu từ 4 nguồn tin tức tài chính và Lịch kinh tế.
Sử dụng Groq LLM để đọc, lọc nhiễu, phân loại tác động và cung cấp báo cáo
nghiên cứu thị trường cập nhật cho Macro Analyst và Head Trader.
"""
import logging
from pathlib import Path
from typing import Dict, Any, List
import yaml

from data.news_collector import NewsCollector
from agents.llm_client import LLMClient

logger = logging.getLogger("ResearchAgent")


class ResearchAgent:
    """
    Agent nghiên cứu vĩ mô & tin tức tài chính.
    """

    def __init__(self, config_path: Path):
        self.config_path = config_path
        self.collector = NewsCollector(cache_ttl_seconds=600)
        self.llm = LLMClient()
        
        # Đọc danh sách symbols cần theo dõi từ symbols.yaml
        self.symbols = self._load_symbols()
        logger.info(f"ResearchAgent sẵn sàng: Theo dõi {len(self.symbols)} tài sản với 4 nguồn tin.")

    def _load_symbols(self) -> List[str]:
        symbols_file = self.config_path / "symbols.yaml"
        if symbols_file.exists():
            try:
                with open(symbols_file, "r", encoding="utf-8") as f:
                    cfg = yaml.safe_load(f)
                    return [s["name"] for s in cfg.get("symbols", [])]
            except Exception as e:
                logger.warning(f"Lỗi đọc symbols.yaml: {e}")
        return ["XAUUSD", "EURUSD", "GBPUSD", "USDJPY", "US30", "NAS100", "USOIL"]

    def fetch_and_summarize(self) -> Dict[str, Any]:
        """
        Thu thập toàn bộ tin tức mới nhất từ 4 nguồn và dùng LLM tóm tắt phân tích.
        """
        logger.info("ResearchAgent: Thu thập dữ liệu từ 4 nguồn tin...")
        news_items = self.collector.fetch_all()

        logger.info("ResearchAgent: Gửi tin tức tới Groq LLM để phân tích vĩ mô...")
        analysis = self.llm.analyze_news_sentiment(news_items, self.symbols)

        result = {
            "timestamp": news_items[0]["published"] if news_items else "",
            "total_articles": len(news_items),
            "sources": ["ForexFactory", "FXStreet", "MarketWatch", "GoogleFinance"],
            "analysis": analysis,
            "raw_headlines_count": len(news_items),
        }
        return result
