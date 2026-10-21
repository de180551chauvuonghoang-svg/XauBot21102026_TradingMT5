r"""
MT5 Bridge - Python Brain ↔ MT5 EA Communication
==================================================
Giao tiếp 2 chiều giữa Python Brain và MT5 EA qua thư mục FILE_COMMON của MT5.
- Brain ghi: signals.json, heartbeat.json, news_blackout.json, kill_switch.json
- Brain đọc: account_state.json (do EA ghi định kỳ)

Đường dẫn FILE_COMMON: %APPDATA%\MetaQuotes\Terminal\Common\Files
"""
import os
import json
import logging
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, List, Dict, Any

logger = logging.getLogger("MT5Bridge")


def get_bridge_directory() -> Path:
    """
    Tìm thư mục FILE_COMMON của MT5 để trao đổi dữ liệu với EA.
    Nếu không tìm thấy, fallback về thư mục cục bộ bridge_files.
    """
    appdata = os.environ.get("APPDATA")
    if appdata:
        common_files = Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files"
        if common_files.exists():
            logger.info(f"MT5Bridge: Đã kết nối thư mục FILE_COMMON: {common_files}")
            return common_files

    # Fallback thư mục local
    local_dir = Path(__file__).parent.parent / "bridge_files"
    local_dir.mkdir(exist_ok=True)
    logger.info(f"MT5Bridge: Dùng thư mục local fallback: {local_dir}")
    return local_dir


class MT5Bridge:
    """
    Cầu nối truyền tin cậy 2 chiều giữa Python Brain và MT5 EA.
    """

    def __init__(self, config_path: Path):
        self.bridge_dir = get_bridge_directory()
        self._heartbeat_file = self.bridge_dir / "heartbeat.json"
        self._signal_file    = self.bridge_dir / "signals.json"
        self._blackout_file  = self.bridge_dir / "news_blackout.json"
        self._kill_file      = self.bridge_dir / "kill_switch.json"
        self._state_file     = self.bridge_dir / "account_state.json"

        # Backup thư mục local
        self._local_dir = Path(__file__).parent.parent / "bridge_files"
        self._local_dir.mkdir(exist_ok=True)

    def send_heartbeat(self):
        """Gửi tín hiệu heartbeat định kỳ kèm unix timestamp."""
        data = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "status": "alive",
            "unix_ts": time.time(),
        }
        content = json.dumps(data)
        self._write_file(self._heartbeat_file, content)
        self._write_file(self._local_dir / "heartbeat.json", content)

    def send_signal(self, signal: dict):
        """
        Gửi tín hiệu giao dịch đã được Risk Officer duyệt sang MT5.
        Chuẩn hóa schema chung cho cả Brain và EA.
        """
        existing = []
        if self._signal_file.exists():
            try:
                existing = json.loads(self._signal_file.read_text(encoding="utf-8")) or []
            except Exception:
                existing = []

        # Chuẩn hóa schema tín hiệu
        unified_signal = {
            "symbol": signal.get("symbol", ""),
            "type": signal.get("type", signal.get("action", "BUY")),
            "price": float(signal.get("price", signal.get("entry_price", 0.0))),
            "stop_loss": float(signal.get("stop_loss", signal.get("sl", 0.0))),
            "take_profit1": float(signal.get("take_profit1", signal.get("tp", 0.0))),
            "take_profit2": float(signal.get("take_profit2", 0.0)),
            "lot": float(signal.get("lot", signal.get("lots", 0.01))),
            "confidence": float(signal.get("confidence", 0.70)),
            "strategy": signal.get("strategy", "BrainAI"),
            "magic": int(signal.get("magic", 1004)),
            "created_at": datetime.now(timezone.utc).isoformat(),
            "consumed": False,
        }

        existing.append(unified_signal)
        content = json.dumps(existing, indent=2)
        self._write_file(self._signal_file, content)
        self._write_file(self._local_dir / "signals.json", content)
        logger.info(f"Signal queued → {unified_signal['symbol']} {unified_signal['type']} | lots={unified_signal['lot']} | conf={unified_signal['confidence']:.0%}")

    def send_news_blackout(self, events: list):
        """Gửi danh sách sự kiện tin tức vĩ mô cần blackout giao dịch."""
        data = {
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "events": events,
        }
        content = json.dumps(data, indent=2, default=str)
        self._write_file(self._blackout_file, content)
        self._write_file(self._local_dir / "news_blackout.json", content)
        logger.info(f"News blackout updated: {len(events)} events sent to MT5 FILE_COMMON.")

    def send_kill_switch(self, activate: bool, reason: str = ""):
        """Kích hoạt / Tắt Kill Switch khẩn cấp."""
        data = {
            "active": activate,
            "reason": reason,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        content = json.dumps(data, indent=2)
        self._write_file(self._kill_file, content)
        self._write_file(self._local_dir / "kill_switch.json", content)
        logger.critical(f"Kill switch {'ACTIVATED' if activate else 'DEACTIVATED'}: {reason}")

    def read_account_state(self) -> Optional[dict]:
        """
        Đọc trạng thái tài khoản thực tế từ MT5 EA (P0 FIX).
        """
        target = self._state_file if self._state_file.exists() else (self._local_dir / "account_state.json")
        if not target.exists():
            return None
        try:
            return json.loads(target.read_text(encoding="utf-8"))
        except Exception as e:
            logger.debug(f"Chưa đọc được account state: {e}")
            return None

    def _write_file(self, path: Path, content: str):
        try:
            path.write_text(content, encoding="utf-8")
        except Exception as e:
            logger.warning(f"Lỗi ghi file bridge {path}: {e}")
