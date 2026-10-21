"""
MT5 Bridge - Python Brain ↔ MT5 EA Communication
==================================================
Hai phương thức giao tiếp:
1. File-based (đơn giản, không cần cấu hình): Brain ghi JSON file, EA đọc
2. ZeroMQ (nâng cao, real-time): cần thư viện pyzmq và EA tích hợp socket

Mặc định dùng File-based để dễ triển khai.
"""
import json
import logging
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# Đường dẫn file giao tiếp (đặt trong thư mục chung giữa Python và MT5)
BRIDGE_DIR = Path(__file__).parent.parent / "bridge_files"


class MT5Bridge:
    """
    Giao tiếp Python Brain ↔ MT5 EA qua file JSON.
    MT5 EA đọc các file này trong OnTimer() hoặc OnTick().
    """

    def __init__(self, config_path: Path):
        BRIDGE_DIR.mkdir(exist_ok=True)
        self._heartbeat_file  = BRIDGE_DIR / "heartbeat.json"
        self._signal_file     = BRIDGE_DIR / "signals.json"
        self._blackout_file   = BRIDGE_DIR / "news_blackout.json"
        self._kill_file       = BRIDGE_DIR / "kill_switch.json"
        logger.info(f"MT5Bridge initialized. Bridge dir: {BRIDGE_DIR}")

    def send_heartbeat(self):
        """Gửi tín hiệu heartbeat để EA biết Brain còn sống."""
        data = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "status": "alive",
            "unix_ts": time.time()
        }
        self._heartbeat_file.write_text(json.dumps(data))

    def send_signal(self, signal: dict):
        """
        Gửi tín hiệu giao dịch đã được Risk Officer duyệt sang MT5.
        signal format:
        {
          "symbol": "XAUUSD",
          "type": "BUY",  # BUY / SELL / CLOSE_ALL
          "entry_price": 1950.0,
          "stop_loss": 1940.0,
          "take_profit1": 1970.0,
          "take_profit2": 1980.0,
          "lot": 0.02,
          "confidence": 0.72,
          "strategy": "TrendFollower",
          "comment": "EMA cross H4 filter"
        }
        """
        # Đọc queue hiện tại
        existing = []
        if self._signal_file.exists():
            try:
                existing = json.loads(self._signal_file.read_text()) or []
            except Exception:
                existing = []

        signal["created_at"] = datetime.now(timezone.utc).isoformat()
        signal["consumed"]   = False
        existing.append(signal)

        self._signal_file.write_text(json.dumps(existing, indent=2))
        logger.info(f"Signal queued → {signal['symbol']} {signal['type']} | conf={signal.get('confidence', 0):.0%}")

    def send_news_blackout(self, events: list):
        """Gửi danh sách sự kiện tin tức cần chặn giao dịch."""
        data = {
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "events": events
        }
        self._blackout_file.write_text(json.dumps(data, indent=2, default=str))
        logger.info(f"News blackout updated: {len(events)} events")

    def send_kill_switch(self, activate: bool, reason: str = ""):
        """Kích hoạt / tắt kill switch từ xa (qua Telegram bot hoặc thủ công)."""
        data = {
            "active": activate,
            "reason": reason,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        self._kill_file.write_text(json.dumps(data))
        logger.critical(f"Kill switch {'ACTIVATED' if activate else 'DEACTIVATED'}: {reason}")

    def read_account_state(self) -> Optional[dict]:
        """
        Đọc trạng thái tài khoản từ MT5 (EA ghi định kỳ).
        """
        state_file = BRIDGE_DIR / "account_state.json"
        if not state_file.exists():
            return None
        try:
            return json.loads(state_file.read_text())
        except Exception as e:
            logger.warning(f"Không đọc được account state: {e}")
            return None
