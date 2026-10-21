"""
Economic Calendar - News Blackout Data
=======================================
Lấy lịch kinh tế tác động cao từ ForexFactory hoặc Investing.com
để gửi danh sách blackout sang MT5 EA.
"""
import logging
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Optional
import requests

logger = logging.getLogger(__name__)

# Các sự kiện tác động cao cần chặn
HIGH_IMPACT_KEYWORDS = [
    "Non-Farm Payroll", "NFP",
    "CPI", "Core CPI", "Inflation",
    "FOMC", "Federal Funds Rate", "Interest Rate",
    "GDP", "Gross Domestic Product",
    "PPI", "Retail Sales",
    "Unemployment Rate",
    "ECB", "BOE", "BOJ",  # Ngân hàng trung ương chính
]


class EconomicCalendar:
    """
    Lịch kinh tế - lấy sự kiện tác động cao sắp xảy ra.
    
    Nguồn dữ liệu ưu tiên:
    1. ForexFactory RSS (miễn phí, không cần API key)
    2. Investing.com (cần scraping thận trọng)
    3. Cài thủ công qua file YAML nếu không có kết nối
    """

    def __init__(self, config_path: Path, blackout_before_min: int = 30, blackout_after_min: int = 30):
        self._blackout_before = blackout_before_min
        self._blackout_after  = blackout_after_min
        self._cache           = []
        self._last_fetch      = 0
        self._cache_ttl_sec   = 3600  # Cache 1 giờ

        # Sự kiện thủ công (fallback)
        self._manual_events = []

        logger.info(f"EconomicCalendar: blackout ±{blackout_before_min}min quanh tin tác động cao")

    def get_upcoming_high_impact(self, minutes_ahead: int = 60) -> list:
        """
        Trả về danh sách sự kiện tác động cao trong N phút tới.
        """
        self._refresh_if_needed()
        now = datetime.now(timezone.utc)
        cutoff = now + timedelta(minutes=minutes_ahead)

        upcoming = []
        for event in self._cache + self._manual_events:
            evt_time = event.get("time")
            if evt_time and now <= evt_time <= cutoff:
                upcoming.append({
                    "name": event["name"],
                    "time": evt_time.isoformat(),
                    "impact": event.get("impact", "HIGH"),
                    "blackout_before_min": self._blackout_before,
                    "blackout_after_min":  self._blackout_after,
                })
        return upcoming

    def _refresh_if_needed(self):
        if time.time() - self._last_fetch < self._cache_ttl_sec:
            return
        try:
            self._fetch_forexfactory()
        except Exception as e:
            logger.warning(f"Không fetch được lịch kinh tế: {e}. Dùng cache cũ hoặc manual events.")
        self._last_fetch = time.time()

    def _fetch_forexfactory(self):
        """Lấy RSS ForexFactory - chỉ các sự kiện HIGH impact."""
        try:
            import feedparser
        except ImportError:
            logger.warning("feedparser chưa cài. Chạy: pip install feedparser")
            return

        url = "https://nfs.faireconomy.media/ff_calendar_thisweek.json"
        resp = requests.get(url, timeout=10)
        if resp.status_code != 200:
            return

        events = resp.json()
        parsed = []
        for evt in events:
            if evt.get("impact", "").upper() != "HIGH":
                continue
            try:
                evt_time = datetime.fromisoformat(evt["date"].replace("Z", "+00:00"))
                parsed.append({"name": evt["title"], "time": evt_time, "impact": "HIGH"})
            except Exception:
                continue

        self._cache = parsed
        logger.info(f"Cập nhật lịch kinh tế: {len(parsed)} sự kiện HIGH impact tuần này")

    def add_manual_event(self, name: str, utc_datetime: datetime):
        """Thêm sự kiện thủ công (khi không có API)."""
        self._manual_events.append({"name": name, "time": utc_datetime, "impact": "HIGH"})
        logger.info(f"Manual event: {name} @ {utc_datetime.isoformat()}")
