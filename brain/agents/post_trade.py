"""
Post-Trade Analyst - Trade Performance Journal & Edge Monitoring
================================================================
Theo dõi hiệu suất lệnh sau khi đóng, tính toán Winrate, Profit Factor,
ghi nhật ký journal và cảnh báo khi chiến lược suy giảm hiệu quả (decay).
"""
import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Any, List

logger = logging.getLogger("PostTradeAnalyst")


class PostTradeAnalyst:
    """
    Chuyên viên đánh giá & nhật ký sau giao dịch.
    """

    def __init__(self, journal_dir: Path):
        self.journal_dir = journal_dir
        self.journal_dir.mkdir(exist_ok=True)
        self.journal_file = self.journal_dir / "trade_journal.jsonl"
        logger.info(f"PostTradeAnalyst sẵn sàng. Journal: {self.journal_file}")

    def log_trade_closed(self, trade_info: Dict[str, Any]):
        """Ghi nhận lệnh đã đóng vào journal."""
        trade_record = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "symbol": trade_info.get("symbol", ""),
            "action": trade_info.get("action", ""),
            "profit": float(trade_info.get("profit", 0.0)),
            "strategy": trade_info.get("strategy", ""),
            "magic": trade_info.get("magic", 0),
            "comment": trade_info.get("comment", ""),
        }

        with open(self.journal_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(trade_record) + "\n")

        logger.info(f"PostTrade: Đã lưu journal lệnh {trade_record['symbol']} (PnL: {trade_record['profit']:.2f})")

    def generate_summary(self) -> Dict[str, Any]:
        """Tổng kết hiệu suất từ các lệnh trong nhật ký."""
        if not self.journal_file.exists():
            return {"total_trades": 0, "win_rate": 0.0, "total_profit": 0.0}

        trades = []
        with open(self.journal_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        trades.append(json.loads(line))
                    except Exception:
                        pass

        if not trades:
            return {"total_trades": 0, "win_rate": 0.0, "total_profit": 0.0}

        wins = sum(1 for t in trades if t["profit"] > 0)
        total_pnl = sum(t["profit"] for t in trades)
        win_rate = (wins / len(trades)) * 100.0

        return {
            "total_trades": len(trades),
            "wins": wins,
            "losses": len(trades) - wins,
            "win_rate": round(win_rate, 2),
            "total_profit": round(total_pnl, 2),
        }
