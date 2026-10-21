"""
Risk Officer - Python Brain
============================
Quyền phủ quyết tuyệt đối. Không phụ thuộc AI/LLM.
Tất cả giới hạn viết bằng code cứng (deterministic).
"""
import logging
from datetime import datetime, timezone
from pathlib import Path
import yaml

logger = logging.getLogger(__name__)


class RiskOfficer:
    """
    Risk Officer: kiểm tra và veto tín hiệu dựa trên config cứng.
    LLM/AI không có quyền override class này.
    """

    def __init__(self, config_path: Path):
        risk_cfg = config_path / "risk.yaml"
        with open(risk_cfg, encoding="utf-8") as f:
            cfg = yaml.safe_load(f)

        self.risk_pct          = cfg["risk_per_trade_pct"]
        self.max_daily_loss    = cfg["max_daily_loss_pct"]
        self.max_weekly_loss   = cfg["max_weekly_loss_pct"]
        self.max_total_dd      = cfg["max_total_drawdown_pct"]
        self.kelly_cap         = cfg["kelly_fraction_cap"]
        self.news_blackout_min = cfg["news_blackout_minutes"]
        self.max_slippage_pts  = cfg["max_slippage_points"]
        self.require_hard_sl   = cfg["require_hard_sl"]
        self.allow_martingale  = cfg["allow_martingale"]
        self.allow_grid        = cfg["allow_grid"]

        # State
        self._halted           = False
        self._halt_reason      = ""
        self._daily_loss_pct   = 0.0
        self._weekly_loss_pct  = 0.0
        self._consecutive_losses = 0

        logger.info(f"RiskOfficer initialized: risk/trade={self.risk_pct}% | daily_limit={self.max_daily_loss}%")

    def veto(self, signal: dict, account_state: dict) -> tuple[bool, str]:
        """
        Kiểm tra và phủ quyết tín hiệu.
        Returns: (approved: bool, reason: str)
        """
        if self._halted:
            return False, f"System halted: {self._halt_reason}"

        # 1. SL bắt buộc
        if self.require_hard_sl and not signal.get("stop_loss"):
            return False, "NO HARD SL - Từ chối lệnh thiếu SL cứng"

        # 2. Kiểm tra daily loss
        dd = account_state.get("daily_loss_pct", 0)
        if dd >= self.max_daily_loss:
            self.halt(f"Daily loss {dd:.2f}% >= limit {self.max_daily_loss}%")
            return False, f"Daily circuit breaker: {dd:.2f}%"

        # 3. Kiểm tra weekly loss
        wdd = account_state.get("weekly_loss_pct", 0)
        if wdd >= self.max_weekly_loss:
            self.halt(f"Weekly loss {wdd:.2f}% >= limit {self.max_weekly_loss}%")
            return False, f"Weekly circuit breaker: {wdd:.2f}%"

        # 4. Kiểm tra total DD
        total_dd = account_state.get("total_dd_pct", 0)
        if total_dd >= self.max_total_dd:
            self.halt(f"Total DD {total_dd:.2f}% >= limit {self.max_total_dd}%")
            return False, f"Total DD circuit breaker: {total_dd:.2f}%"

        # 5. Confidence threshold
        confidence = signal.get("confidence", 0)
        if confidence < 0.60:
            return False, f"Confidence {confidence:.0%} < 60% threshold"

        logger.info(f"✅ RiskOfficer APPROVED: {signal.get('symbol')} {signal.get('type')} | conf={confidence:.0%}")
        return True, "APPROVED"

    def halt(self, reason: str):
        self._halted = True
        self._halt_reason = reason
        logger.critical(f"🚨 RISK HALT: {reason}")

    def reset_halt(self):
        self._halted = False
        self._halt_reason = ""
        logger.warning("RiskOfficer halt đã được reset thủ công.")

    def is_halted(self) -> bool:
        return self._halted

    def on_trade_closed(self, profit: float):
        if profit < 0:
            self._consecutive_losses += 1
            logger.warning(f"Lệnh thua #{self._consecutive_losses}: {profit:.2f}")
        else:
            self._consecutive_losses = 0

    def get_size_factor(self) -> float:
        """Hệ số giảm size sau chuỗi thua"""
        cap = 3
        if self._consecutive_losses <= cap:
            return 1.0
        reduction = 1.0 - 0.1 * (self._consecutive_losses - cap)
        return max(0.3, reduction)
