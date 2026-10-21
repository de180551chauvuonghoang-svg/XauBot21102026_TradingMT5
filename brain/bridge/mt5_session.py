"""
MT5 Connection Manager
======================
Đọc credentials từ .env (không bao giờ hardcode trong code).
Kết nối và quản lý phiên làm việc với MetaTrader 5.
"""
import logging
import os
from pathlib import Path

logger = logging.getLogger(__name__)

# Load .env nếu chưa được load
try:
    from dotenv import load_dotenv
    _env_path = Path(__file__).parent.parent.parent / ".env"
    if _env_path.exists():
        load_dotenv(_env_path)
        logger.info(f".env loaded từ: {_env_path}")
    else:
        logger.warning(f".env không tồn tại tại {_env_path}. Dùng biến môi trường hệ thống.")
except ImportError:
    logger.warning("python-dotenv chưa cài. Chạy: pip install python-dotenv")


def get_mt5_credentials() -> dict:
    """
    Đọc thông tin đăng nhập MT5 từ biến môi trường.
    Không bao giờ return giá trị mặc định hardcode.
    """
    login    = os.environ.get("MT5_LOGIN", "")
    password = os.environ.get("MT5_PASSWORD", "")
    server   = os.environ.get("MT5_SERVER", "")

    missing = []
    if not login:    missing.append("MT5_LOGIN")
    if not password: missing.append("MT5_PASSWORD")
    if not server:   missing.append("MT5_SERVER")

    if missing:
        raise EnvironmentError(
            f"Thiếu credentials trong .env: {', '.join(missing)}\n"
            f"Hãy copy .env.example → .env và điền thông tin thật."
        )

    return {
        "login":    int(login),
        "password": password,
        "server":   server,
        "mode":     os.environ.get("TRADING_MODE", "demo"),
    }


def get_telegram_config() -> dict:
    """Đọc cấu hình Telegram từ .env."""
    return {
        "token":   os.environ.get("TELEGRAM_BOT_TOKEN", ""),
        "chat_id": os.environ.get("TELEGRAM_CHAT_ID", ""),
        "enabled": bool(os.environ.get("TELEGRAM_BOT_TOKEN", "")),
    }


class MT5Session:
    """
    Quản lý phiên kết nối MT5.
    Tự động đọc credentials từ .env — không cần truyền tay.
    """

    def __init__(self):
        self._connected = False
        self._creds     = None

    def connect(self) -> bool:
        try:
            import MetaTrader5 as mt5
        except ImportError:
            logger.error("MetaTrader5 package chưa cài. Chạy: pip install MetaTrader5")
            return False

        try:
            self._creds = get_mt5_credentials()
        except EnvironmentError as e:
            logger.error(str(e))
            return False

        mode = self._creds["mode"]
        logger.info(f"Đang kết nối MT5 [{mode.upper()}] → Server: {self._creds['server']} | Login: {self._creds['login']}")

        if not mt5.initialize():
            logger.error(f"mt5.initialize() thất bại: {mt5.last_error()}")
            return False

        authorized = mt5.login(
            login    = self._creds["login"],
            password = self._creds["password"],
            server   = self._creds["server"],
        )

        if not authorized:
            logger.error(f"Đăng nhập thất bại: {mt5.last_error()}")
            mt5.shutdown()
            return False

        account = mt5.account_info()
        logger.info(
            f"✅ Kết nối thành công!\n"
            f"   Account: #{account.login}\n"
            f"   Name:    {account.name}\n"
            f"   Server:  {account.server}\n"
            f"   Balance: {account.balance:.2f} {account.currency}\n"
            f"   Leverage: 1:{account.leverage}\n"
            f"   Mode:    {'DEMO' if account.trade_mode == 0 else 'LIVE'}"
        )

        if mode == "live" and account.trade_mode == 0:
            logger.warning("⚠️  Config là LIVE nhưng account là DEMO. Kiểm tra lại!")

        self._connected = True
        return True

    def disconnect(self):
        if self._connected:
            try:
                import MetaTrader5 as mt5
                mt5.shutdown()
                logger.info("MT5 disconnected.")
            except Exception:
                pass
            self._connected = False

    def is_connected(self) -> bool:
        return self._connected

    def __enter__(self):
        self.connect()
        return self

    def __exit__(self, *args):
        self.disconnect()
