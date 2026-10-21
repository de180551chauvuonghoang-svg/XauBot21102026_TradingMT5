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
    Single Execution Path: MQL5 EA là nơi duy nhất thẩm định và mở lệnh.
    """

    def __init__(self, config_path: Optional[Path] = None):
        self.bridge_dir = get_bridge_directory()
        self._heartbeat_file = self.bridge_dir / "heartbeat.json"
        self._blackout_file  = self.bridge_dir / "news_blackout.json"
        self._kill_file      = self.bridge_dir / "kill_switch.json"
        self._state_file     = self.bridge_dir / "account_state.json"

        # Cờ Single Execution Path: Mặc định tắt đặt lệnh trực tiếp từ Python (A2 FIX)
        self.enable_direct_exec = os.getenv("ENABLE_DIRECT_EXEC", "false").lower() == "true"
        if self.enable_direct_exec:
            logger.warning("⚠️ CẢNH BÁO: ENABLE_DIRECT_EXEC=true! Python sẽ đặt lệnh trực tiếp mà không qua EA.")
        else:
            logger.info("🛡️ SINGLE EXECUTION PATH: Mọi lệnh gửi qua EA (sig_<id>.json) để EA tính lot và thẩm định rủi ro.")

        # Backup thư mục local
        self._local_dir = Path(__file__).parent.parent / "bridge_files"
        self._local_dir.mkdir(exist_ok=True)

    def send_heartbeat(self):
        """Gửi tín hiệu heartbeat định kỳ kèm unix timestamp UTC (A5 FIX)."""
        now_utc = datetime.now(timezone.utc)
        data = {
            "timestamp": now_utc.isoformat(),
            "status": "alive",
            "unix_ts": int(now_utc.timestamp()),
        }
        content = json.dumps(data)
        self._write_file(self._heartbeat_file, content)
        self._write_file(self._local_dir / "heartbeat.json", content)

    def send_signal(self, signal: dict) -> str:
        """
        Gửi tín hiệu giao dịch đã được duyệt sang MT5.
        A2 & A3 FIX:
        - Mỗi tín hiệu ghi thành 1 file riêng: sig_<id>.json
        - KHÔNG chứa trường 'lot' (EA tự tính lot theo RiskManager::CalcLot)
        - Chứa timestamp created_at_utc để EA kiểm tra tuổi tín hiệu (<60s)
        """
        raw_id = signal.get("id")
        sym = signal.get("symbol", "UNKNOWN")
        if not raw_id:
            raw_id = f"{int(time.time() * 1000)}_{sym}"
        sig_id = f"sig_{raw_id}" if not str(raw_id).startswith("sig_") else str(raw_id)

        now_utc = datetime.now(timezone.utc)
        created_at_utc = signal.get("created_at_utc")
        if not created_at_utc:
            created_at_utc = int(now_utc.timestamp())

        # Chuẩn hóa schema tín hiệu - Tuyệt đối KHÔNG có field 'lot' (A2/A3/A7)
        unified_signal = {
            "id": sig_id,
            "symbol": sym,
            "type": signal.get("type", signal.get("action", "BUY")).upper(),
            "price": float(signal.get("price", signal.get("entry_price", 0.0))),
            "stop_loss": float(signal.get("stop_loss", signal.get("sl", 0.0))),
            "take_profit1": float(signal.get("take_profit1", signal.get("tp", 0.0))),
            "take_profit2": float(signal.get("take_profit2", 0.0)),
            "confidence": float(signal.get("confidence", 0.70)),
            "strategy": signal.get("strategy", "BrainAI"),
            "magic": int(signal.get("magic", 1004)),
            "created_at_utc": int(created_at_utc),
        }

        # Nếu cờ ENABLE_DIRECT_EXEC được bật thủ công trong .env, thực thi trực tiếp
        if self.enable_direct_exec:
            self._execute_order_direct(unified_signal)

        # Ghi file tín hiệu riêng biệt sig_<id>.json để EA xử lý
        filename = f"{sig_id}.json"
        content = json.dumps(unified_signal, indent=2)
        self._write_file(self.bridge_dir / filename, content)
        self._write_file(self._local_dir / filename, content)
        logger.info(
            f"Signal queued → {filename} | {unified_signal['symbol']} {unified_signal['type']} | "
            f"SL={unified_signal['stop_loss']} | TP={unified_signal['take_profit1']} | conf={unified_signal['confidence']:.0%}"
        )
        return sig_id

    def _execute_order_direct(self, sig: dict) -> bool:
        """Thực thi lệnh trực tiếp trên MT5 bằng tài khoản đang kết nối (CHỈ DÙNG KHI BẬT ENABLE_DIRECT_EXEC)."""
        try:
            import MetaTrader5 as mt5
            if not mt5.terminal_info():
                return False

            symbol = sig["symbol"]
            open_positions = mt5.positions_get(symbol=symbol)
            if open_positions:
                for p in open_positions:
                    if p.magic == sig.get("magic", 1004):
                        logger.info(f"Bỏ qua mở lệnh {symbol}: Đã có vị thế ticket #{p.ticket} đang mở.")
                        return False

            mt5.symbol_select(symbol, True)
            tick = mt5.symbol_info_tick(symbol)
            sym_info = mt5.symbol_info(symbol)
            if not tick or not sym_info:
                logger.error(f"Không lấy được tick/info cho {symbol}")
                return False

            is_buy = (sig["type"].upper() == "BUY")
            order_type = mt5.ORDER_TYPE_BUY if is_buy else mt5.ORDER_TYPE_SELL
            price = tick.ask if is_buy else tick.bid

            filling = mt5.ORDER_FILLING_FOK
            if sym_info.filling_mode & 2 != 0:
                filling = mt5.ORDER_FILLING_IOC
            elif sym_info.filling_mode & 1 != 0:
                filling = mt5.ORDER_FILLING_FOK
            else:
                filling = mt5.ORDER_FILLING_RETURN

            # Fallback lot khi đặt trực tiếp
            lot = float(sig.get("lot", 0.01))

            request = {
                "action": mt5.TRADE_ACTION_DEAL,
                "symbol": symbol,
                "volume": lot,
                "type": order_type,
                "price": float(price),
                "sl": float(sig["stop_loss"]),
                "tp": float(sig["take_profit1"]),
                "deviation": 20,
                "magic": int(sig.get("magic", 1004)),
                "comment": f"BrainAI:{sig.get('strategy', 'AI')[:10]}",
                "type_time": mt5.ORDER_TIME_GTC,
                "type_filling": filling,
            }

            result = mt5.order_send(request)
            if result and result.retcode == mt5.TRADE_RETCODE_DONE:
                logger.info(
                    f"🎯 MT5 DIRECT ORDER EXECUTED THÀNH CÔNG! Ticket #{result.order} | "
                    f"{symbol} {sig['type']} {lot} lots @ {price:.5f} | SL={sig['stop_loss']} | TP={sig['take_profit1']}"
                )
                return True
            else:
                ret = result.retcode if result else "None"
                comment = result.comment if result else mt5.last_error()
                logger.warning(f"MT5 order_send trả về code={ret}: {comment}")
                return False
        except Exception as e:
            logger.error(f"Lỗi khi thực thi lệnh trực tiếp qua MT5 API: {e}")
            return False

    def send_news_blackout(self, events: list):
        """
        Gửi danh sách sự kiện tin tức vĩ mô cần blackout giao dịch (A4 FIX).
        Đảm bảo mỗi sự kiện có trường time_utc (unix timestamp).
        Ghi lại file mỗi chu kỳ kể cả khi rỗng để EA giải phóng blackout.
        """
        formatted_events = []
        for evt in events:
            time_utc = evt.get("time_utc")
            if time_utc is None:
                t = evt.get("time")
                if isinstance(t, (int, float)):
                    time_utc = int(t)
                elif isinstance(t, datetime):
                    time_utc = int(t.timestamp())
                elif isinstance(t, str):
                    try:
                        time_utc = int(datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp())
                    except Exception:
                        time_utc = 0
            formatted_events.append({
                "name": evt.get("name", "High Impact News"),
                "time_utc": int(time_utc) if time_utc else 0,
                "impact": evt.get("impact", "HIGH"),
                "blackout_before_min": evt.get("blackout_before_min", 30),
                "blackout_after_min": evt.get("blackout_after_min", 30),
            })

        data = {
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "events": formatted_events,
        }
        content = json.dumps(data, indent=2)
        self._write_file(self._blackout_file, content)
        self._write_file(self._local_dir / "news_blackout.json", content)
        logger.info(f"News blackout updated: {len(formatted_events)} events sent to MT5 FILE_COMMON.")

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
        Đọc trạng thái tài khoản thực tế từ MT5 EA (A6 FIX).
        Bao gồm: daily_loss_pct, weekly_loss_pct, total_dd_pct, peak_equity, open_risk_pct, halted, halt_reason
        """
        target = self._state_file if self._state_file.exists() else (self._local_dir / "account_state.json")
        if not target.exists():
            return None
        try:
            return json.loads(target.read_text(encoding="utf-8"))
        except Exception as e:
            logger.debug(f"Chưa đọc được account state: {e}")
            return None

    def read_ack(self, sig_id: str) -> Optional[dict]:
        """Đọc kết quả xử lý của EA cho một tín hiệu từ ack_<id>.json."""
        clean_id = sig_id.replace("sig_", "")
        ack_file = self.bridge_dir / f"ack_{clean_id}.json"
        if not ack_file.exists():
            ack_file = self._local_dir / f"ack_{clean_id}.json"
        if ack_file.exists():
            try:
                return json.loads(ack_file.read_text(encoding="utf-8"))
            except Exception:
                pass
        return None

    def _write_file(self, path: Path, content: str):
        try:
            path.write_text(content, encoding="utf-8")
        except Exception as e:
            logger.warning(f"Lỗi ghi file bridge {path}: {e}")
