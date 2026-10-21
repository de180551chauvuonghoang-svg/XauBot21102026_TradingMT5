"""
MultiAssetEA v2 - Python Brain Entry Point
==========================================
Khởi động hệ thống não bộ Python: data feeds, agents, bridge sang MT5.

Credentials đọc từ .env (KHÔNG hardcode trong code).
Chạy: python main.py --config ../config --mode demo

Setup lần đầu:
  1. Copy .env.example → .env
  2. Điền MT5_LOGIN, MT5_PASSWORD, MT5_SERVER
  3. pip install -r requirements.txt
  4. python main.py --mode demo
"""
import argparse
import logging
import sys
import time
from pathlib import Path

# Load .env ngay khi khởi động (trước mọi thứ khác)
try:
    from dotenv import load_dotenv
    _env = Path(__file__).parent.parent / ".env"
    if _env.exists():
        load_dotenv(_env)
    else:
        print(f"[WARN] .env không tồn tại! Hãy copy .env.example → .env và điền thông tin.")
except ImportError:
    print("[WARN] python-dotenv chưa cài. Chạy: pip install python-dotenv")

# Đảm bảo console Windows hỗ trợ UTF-8 cho Tiếng Việt
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

# Setup logging trước khi import các module khác
_journal_dir = Path(__file__).parent / "journal"
_journal_dir.mkdir(exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(_journal_dir / "brain.log", mode="a", encoding="utf-8"),
    ],
)
logger = logging.getLogger("Brain")


def parse_args():
    parser = argparse.ArgumentParser(description="MultiAssetEA v2 - Python Brain")
    parser.add_argument("--config", default="../config", help="Thư mục config (YAML files)")
    parser.add_argument(
        "--mode",
        choices=["demo", "live"],
        default="demo",
        help="Chế độ giao dịch (mặc định: demo)"
    )
    parser.add_argument("--symbols", default=None, help="Override danh sách symbol (csv)")
    parser.add_argument("--once", action="store_true", help="Chỉ chạy 1 chu kỳ rồi dừng (dùng cho test/cron)")
    parser.add_argument("--debug", action="store_true", help="Bật debug logging")
    return parser.parse_args()


def main():
    args = parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    logger.info("=" * 60)
    logger.info("   MultiAssetEA v2 - Python Brain STARTING")
    logger.info(f"   Mode: {args.mode.upper()} | Config: {args.config}")
    logger.info("=" * 60)

    if args.mode == "live":
        logger.warning("⚠️  LIVE MODE - Giao dịch bằng tiền thật!")
        logger.warning("Nhấn Ctrl+C trong 5 giây để hủy...")
        try:
            time.sleep(5)
        except KeyboardInterrupt:
            logger.info("Hủy khởi động.")
            return

    try:
        # Import các module
        from agents.research  import ResearchAgent
        from agents.macro     import MacroAnalyst
        from agents.quant     import QuantAnalyst
        from agents.head_trader import HeadTrader
        from risk.risk_officer  import RiskOfficer
        from bridge.mt5_bridge  import MT5Bridge
        from bridge.mt5_session import MT5Session
        from data.calendar      import EconomicCalendar

        config_path = Path(args.config)
        logger.info(f"Đọc config từ: {config_path.resolve()}")

        # P0 FIX: Khởi tạo kết nối MT5 API cho Brain
        session = MT5Session()
        session_connected = session.connect()
        if not session_connected:
            logger.warning("Chưa kết nối trực tiếp MT5 Python API. Brain sẽ hoạt động qua FILE_COMMON bridge với MT5 EA.")

        # --- Khởi tạo các thành phần
        bridge    = MT5Bridge(config_path)
        calendar  = EconomicCalendar(config_path)
        research  = ResearchAgent(config_path)
        macro     = MacroAnalyst(config_path)
        quant     = QuantAnalyst(config_path)
        risk      = RiskOfficer(config_path)
        head      = HeadTrader(config_path, risk)

        logger.info("Tất cả agents đã khởi động. Bắt đầu vòng lặp chính...")

        # Cache phân tích tin tức để tiết kiệm quota LLM (15 phút cập nhật 1 lần)
        cached_news_summary = None
        cached_macro_bias   = None
        last_llm_analysis   = 0
        LLM_REFRESH_INTERVAL = 900  # 15 phút (900 giây)

        # --- Vòng lặp chính
        cycle = 0
        while True:
            cycle += 1
            now_ts = time.time()
            logger.debug(f"--- Chu kỳ #{cycle} ---")

            try:
                # 1. Cập nhật heartbeat cho MT5 EA
                bridge.send_heartbeat()

                # 2. Đọc trạng thái tài khoản thực tế từ MT5 EA (P0 FIX)
                account_state = bridge.read_account_state() or {
                    "daily_loss_pct": 0.0,
                    "weekly_loss_pct": 0.0,
                    "total_dd_pct": 0.0,
                    "equity": 10000.0,
                    "balance": 10000.0,
                }

                # 3. Kiểm tra tin tức sắp ra (A4 FIX: Luôn gửi danh sách blackout kể cả rỗng để EA giải phóng blackout khi hết tin)
                upcoming_news = calendar.get_upcoming_high_impact(minutes_ahead=60)
                bridge.send_news_blackout(upcoming_news or [])
                if upcoming_news:
                    logger.info(f"News blackout: {[n['name'] for n in upcoming_news]}")

                # 4. Nghiên cứu thị trường & LLM (chạy mỗi 15 phút để tiết kiệm quota Groq)
                if cached_news_summary is None or (now_ts - last_llm_analysis >= LLM_REFRESH_INTERVAL):
                    logger.info("Cập nhật phân tích tin tức mới từ 4 nguồn qua Groq LLM...")
                    cached_news_summary = research.fetch_and_summarize()
                    cached_macro_bias   = macro.analyze(cached_news_summary)
                    last_llm_analysis   = now_ts

                # 5. Phân tích định lượng và sinh tín hiệu kỹ thuật
                quant_signals = quant.generate_signals()

                # 6. Tổng hợp và ra quyết định (đối chiếu vĩ mô + rủi ro thật)
                approved = head.decide(cached_macro_bias, quant_signals, cached_news_summary, account_state)

                # 7. Gửi lệnh đã duyệt sang MT5 qua FILE_COMMON
                for signal in approved:
                    bridge.send_signal(signal)
                    logger.info(f"Gửi tín hiệu duyệt sang MT5: {signal}")

            except KeyboardInterrupt:
                raise
            except Exception as e:
                logger.error(f"Lỗi chu kỳ #{cycle}: {e}", exc_info=True)

            if args.once:
                logger.info("Hoàn tất chu kỳ --once, dừng Brain.")
                break

            # Nghỉ 60 giây giữa các chu kỳ
            time.sleep(60)

    except ImportError as e:
        logger.critical(f"❌ [LỖI NGHIÊM TRỌNG] Thiếu thư viện hoặc module: {e}")
        logger.critical("Vui lòng chạy: pip install -r requirements.txt để cài đặt đầy đủ các gói cần thiết.")
        sys.exit(1)

    except KeyboardInterrupt:
        logger.info("Nhận Ctrl+C - dừng Brain gracefully.")
    finally:
        logger.info("Brain đã dừng.")


def _run_heartbeat_only_mode():
    """
    Chế độ đơn giản: chỉ giữ heartbeat cho MT5 EA,
    EA tự hoạt động hoàn toàn bằng MQL5 strategies.
    Dùng trong giai đoạn 1-2 trước khi Brain đầy đủ.
    """
    logger.info("Chạy Heartbeat-Only mode. Nhấn Ctrl+C để dừng.")
    try:
        import MetaTrader5 as mt5
        if not mt5.initialize():
            logger.error("Không thể kết nối MT5! Đảm bảo MT5 đang chạy trên cùng máy.")
            return

        account = mt5.account_info()
        if account:
            logger.info(f"MT5 connected: Account #{account.login} | Balance: {account.balance:.2f} {account.currency}")

        while True:
            # Ghi heartbeat file để EA đọc (nếu dùng file-based bridge)
            Path("journal/heartbeat.txt").write_text(str(time.time()))
            logger.debug("Heartbeat sent")
            time.sleep(10)
    except ImportError:
        logger.warning("MetaTrader5 package chưa cài. Chạy: pip install MetaTrader5")
        logger.info("Sleeping...")
        while True:
            time.sleep(30)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    # Đảm bảo thư mục journal tồn tại
    Path("journal").mkdir(exist_ok=True)
    main()
