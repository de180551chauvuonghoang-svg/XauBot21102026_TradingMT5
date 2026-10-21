"""
Multi-Source News Collector - 4 Real-Time Financial News Feeds
==============================================================
Tích hợp 4 nguồn tin tài chính hàng đầu (100% Miễn phí & Real-time):
1. ForexFactory  : Lịch kinh tế tác động cao (CPI, NFP, FOMC, Lãi suất)
2. FXStreet      : Tin tức & phân tích chuyên sâu Forex, Vàng (XAUUSD)
3. MarketWatch   : Nhịp đập thị trường tài chính Mỹ & toàn cầu theo thời gian thực
4. Google Finance: Tin tức vĩ mô tổng hợp (DXY, Fed, Trái phiếu, US30, NAS100, Dầu USOIL)
"""
import logging
import time
import re
from datetime import datetime, timezone
from typing import List, Dict, Any
import requests
import feedparser

logger = logging.getLogger("NewsCollector")

# Danh sách từ khóa phân loại tài sản
ASSET_KEYWORDS = {
    "XAUUSD": ["gold", "xauusd", "bullion", "precious metal", "vàng", "silver"],
    "EURUSD": ["eur", "euro", "ecb", "lagarde", "eurozone"],
    "GBPUSD": ["gbp", "pound", "boe", "bailey", "uk economy", "sterling"],
    "USDJPY": ["jpy", "yen", "boj", "ueda", "japan"],
    "US30":   ["dow", "dow jones", "djia", "wall street", "us30"],
    "NAS100": ["nasdaq", "tech stocks", "nas100", "big tech", "semiconductor"],
    "USOIL":  ["oil", "crude", "wti", "brent", "opec", "energy", "petroleum"],
    "USD":    ["fed", "powell", "fomc", "cpi", "nfp", "treasury", "yield", "dxy", "dollar", "inflation", "interest rate"]
}


class NewsCollector:
    """
    Thu thập, lọc và chuẩn hóa tin tức từ 4 nguồn tài chính.
    Tự động gắn nhãn symbol và lưu cache tránh spam API.
    """

    def __init__(self, cache_ttl_seconds: int = 600):
        self.cache_ttl = cache_ttl_seconds
        self._last_fetch_time = 0
        self._cached_news: List[Dict[str, Any]] = []

        self.headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }

    def fetch_all(self, force_refresh: bool = False) -> List[Dict[str, Any]]:
        """Lấy tin tức tổng hợp từ cả 4 nguồn."""
        now = time.time()
        if not force_refresh and (now - self._last_fetch_time < self.cache_ttl) and self._cached_news:
            logger.debug(f"Trả về {len(self._cached_news)} tin tức từ cache.")
            return self._cached_news

        all_news = []
        logger.info("Bắt đầu cập nhật tin tức từ 4 nguồn tài chính...")

        # 1. Nguồn 1: ForexFactory (Lịch kinh tế vĩ mô)
        try:
            ff_news = self._fetch_forexfactory()
            all_news.extend(ff_news)
            logger.info(f" [1/4] ForexFactory: lấy thành công {len(ff_news)} sự kiện vĩ mô.")
        except Exception as e:
            logger.warning(f" [1/4] ForexFactory lỗi: {e}")

        # 2. Nguồn 2: FXStreet (Forex & Gold chuyên sâu)
        try:
            fx_news = self._fetch_fxstreet()
            all_news.extend(fx_news)
            logger.info(f" [2/4] FXStreet: lấy thành công {len(fx_news)} tin.")
        except Exception as e:
            logger.warning(f" [2/4] FXStreet lỗi: {e}")

        # 3. Nguồn 3: MarketWatch (Real-time Market Pulse)
        try:
            mw_news = self._fetch_marketwatch()
            all_news.extend(mw_news)
            logger.info(f" [3/4] MarketWatch: lấy thành công {len(mw_news)} tin.")
        except Exception as e:
            logger.warning(f" [3/4] MarketWatch lỗi: {e}")

        # 4. Nguồn 4: Google Finance Macro RSS
        try:
            gf_news = self._fetch_google_finance()
            all_news.extend(gf_news)
            logger.info(f" [4/4] Google Finance: lấy thành công {len(gf_news)} tin vĩ mô.")
        except Exception as e:
            logger.warning(f" [4/4] Google Finance lỗi: {e}")

        # Loại bỏ tin trùng lặp dựa trên title
        unique_news = self._deduplicate(all_news)
        self._cached_news = unique_news
        self._last_fetch_time = now

        logger.info(f"==> Tổng hợp thành công {len(unique_news)} tin tức độc nhất từ 4 nguồn.")
        return unique_news

    def _fetch_forexfactory(self) -> List[Dict[str, Any]]:
        """Lấy sự kiện lịch kinh tế từ ForexFactory."""
        url = "https://nfs.faireconomy.media/ff_calendar_thisweek.json"
        resp = requests.get(url, headers=self.headers, timeout=10)
        if resp.status_code != 200:
            return []

        events = resp.json()
        result = []
        for evt in events:
            impact = evt.get("impact", "").upper()
            if impact in ["HIGH", "MEDIUM"]:
                title = f"[{evt.get('country', 'US')}] {evt.get('title')}: Forecast {evt.get('forecast') or 'N/A'}, Previous {evt.get('previous') or 'N/A'}"
                result.append({
                    "source": "ForexFactory",
                    "title": title,
                    "summary": f"Impact: {impact}. Event time: {evt.get('date')}",
                    "published": evt.get("date", ""),
                    "symbols": self._detect_symbols(title),
                    "impact": impact
                })
        return result

    def _fetch_fxstreet(self) -> List[Dict[str, Any]]:
        """Lấy RSS tin tức & phân tích từ FXStreet."""
        url = "https://www.fxstreet.com/rss/news"
        resp = requests.get(url, headers=self.headers, timeout=10)
        feed = feedparser.parse(resp.content)
        result = []
        for entry in feed.entries[:25]:
            title = entry.get("title", "")
            summary = entry.get("summary", "")
            # Làm sạch HTML tag trong summary nếu có
            clean_summary = re.sub(r"<[^>]+>", "", summary).strip()
            symbols = self._detect_symbols(title + " " + clean_summary)
            result.append({
                "source": "FXStreet",
                "title": title,
                "summary": clean_summary[:300],
                "published": entry.get("published", ""),
                "symbols": symbols,
                "impact": "HIGH" if any(k in title.lower() for k in ["fed", "war", "surge", "crash", "breakout"]) else "MEDIUM"
            })
        return result

    def _fetch_marketwatch(self) -> List[Dict[str, Any]]:
        """Lấy RSS từ MarketWatch Realtime Headlines."""
        url = "https://feeds.content.dowjones.io/public/rss/mw_realtimeheadlines"
        resp = requests.get(url, headers=self.headers, timeout=10)
        feed = feedparser.parse(resp.content)
        result = []
        for entry in feed.entries[:20]:
            title = entry.get("title", "")
            summary = re.sub(r"<[^>]+>", "", entry.get("summary", "")).strip()
            symbols = self._detect_symbols(title + " " + summary)
            result.append({
                "source": "MarketWatch",
                "title": title,
                "summary": summary[:300],
                "published": entry.get("published", ""),
                "symbols": symbols,
                "impact": "MEDIUM"
            })
        return result

    def _fetch_google_finance(self) -> List[Dict[str, Any]]:
        """Lấy tin tức vĩ mô tổng hợp từ Google Finance News RSS."""
        queries = "XAUUSD+OR+Gold+price+OR+Federal+Reserve+OR+Crude+Oil+OR+Forex+Dollar"
        url = f"https://news.google.com/rss/search?q={queries}&hl=en-US&gl=US&ceid=US:en"
        resp = requests.get(url, headers=self.headers, timeout=10)
        feed = feedparser.parse(resp.content)
        result = []
        for entry in feed.entries[:25]:
            title = entry.get("title", "")
            symbols = self._detect_symbols(title)
            result.append({
                "source": "GoogleFinance",
                "title": title,
                "summary": title,
                "published": entry.get("published", ""),
                "symbols": symbols,
                "impact": "MEDIUM"
            })
        return result

    def _detect_symbols(self, text: str) -> List[str]:
        """Tự động phân loại xem tin tức liên quan tới symbol nào."""
        text_lower = text.lower()
        matched = set()
        for symbol, kws in ASSET_KEYWORDS.items():
            for kw in kws:
                if kw in text_lower:
                    matched.add(symbol)
                    break
        # Nếu có USD thì có thể ảnh hưởng cả XAUUSD và các cặp FX
        if "USD" in matched:
            matched.add("XAUUSD")
        return list(matched) if matched else ["GENERAL_MACRO"]

    def _deduplicate(self, news_items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Khử trùng lặp tiêu đề."""
        seen = set()
        unique = []
        for item in news_items:
            key = item["title"].strip().lower()[:80]
            if key not in seen:
                seen.add(key)
                unique.append(item)
        return unique

    def get_news_for_symbol(self, symbol: str, limit: int = 10) -> List[Dict[str, Any]]:
        """Lấy các tin tức mới nhất tác động tới symbol cụ thể."""
        all_news = self.fetch_all()
        filtered = [n for n in all_news if symbol in n["symbols"] or "GENERAL_MACRO" in n["symbols"]]
        return filtered[:limit]
