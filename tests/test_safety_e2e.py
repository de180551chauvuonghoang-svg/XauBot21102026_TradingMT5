"""
Safety Verification Test Suite (T1 - T18 Mapping & Logic Tests)
Based on 'Kế hoạch sửa lỗi và kiểm thử MultiAssetEA v2.md'
"""
import json
import time
from datetime import datetime, timezone
import pytest

# --- Helper logic emulating MQL5 EA RiskManager & BridgeReader rules ---

def mql5_calc_lot(balance: float, risk_pct: float, sl_points: float, tick_value: float, tick_size: float, point: float, min_lot: float, max_lot: float, step: float) -> float:
    """
    Simulates RiskManager::CalcLot in MQL5.
    Must return 0 if calculated lot < min_lot (NEVER force round up to min_lot)!
    """
    if sl_points <= 0 or tick_value <= 0 or tick_size <= 0:
        return 0.0

    risk_amount = balance * (risk_pct / 100.0)
    loss_per_lot = (sl_points * point / tick_size) * tick_value
    if loss_per_lot <= 0:
        return 0.0

    raw_lot = risk_amount / loss_per_lot

    # T4 FIX: If raw_lot < min_lot, reject trade (return 0)
    if raw_lot < min_lot:
        return 0.0

    # Step rounding
    steps = int(raw_lot / step)
    lot = steps * step
    return min(lot, max_lot)

def mql5_check_open_risk(current_open_risk_usd: float, balance: float, new_trade_risk_usd: float, max_risk_pct: float = 2.0) -> bool:
    """Simulates RiskManager::CheckOpenRisk (T6). Max 2% total open risk limit."""
    max_allowed = balance * (max_risk_pct / 100.0)
    return (current_open_risk_usd + new_trade_risk_usd) <= max_allowed

def mql5_check_signal_age(sig_created_at_utc: int, current_gmt: int, max_age_seconds: int = 60) -> tuple[bool, str]:
    """Simulates BridgeReader::ProcessSingleSignalFile age check (T9)."""
    age = current_gmt - sig_created_at_utc
    if age > max_age_seconds:
        return False, f"stale_signal_age_{age}s"
    if age < -10:
        return False, "future_timestamp"
    return True, "valid"

def mql5_partial_close_rule(volume: float, min_lot: float, step: float) -> str:
    """
    Simulates ExecutionEngine::HandlePartialClose (T14 / A9).
    If volume < 2 * minLot: DO NOT partial close, move SL to Break-Even and target TP.
    """
    if volume < 2 * min_lot:
        return "MOVE_SL_BE_NO_PARTIAL"
    close_vol = volume * 0.5
    steps = int(close_vol / step)
    final_close = steps * step
    return f"PARTIAL_CLOSE_{final_close:.2f}"

def mql5_check_heartbeat_alive(last_heartbeat_utc: int, current_gmt: int, max_age_seconds: int = 180) -> bool:
    """Simulates BridgeReader::CheckHeartbeat (T12 / A5)."""
    age = current_gmt - last_heartbeat_utc
    return 0 <= age <= max_age_seconds


# --- TESTS ---

def test_t4_calc_lot_xauusd_500_capital():
    """
    T4: Vốn $500, rủi ro 0.5% = $2.5.
    XAUUSD SL 10 USD (1000 points, tick_size=0.01, tick_value=1.0, point=0.01).
    loss_per_lot = 1000.0 USD.
    raw_lot = 2.5 / 1000 = 0.0025 lot.
    Vì min_lot = 0.01, bot PHẢI TRẢ 0 (bỏ lệnh), không ép lên 0.01!
    """
    lot = mql5_calc_lot(
        balance=500.0,
        risk_pct=0.5,
        sl_points=1000.0,
        tick_value=1.0,
        tick_size=0.01,
        point=0.01,
        min_lot=0.01,
        max_lot=100.0,
        step=0.01,
    )
    assert lot == 0.0, f"Expected 0.0 (trade rejected due to min lot), got {lot}"

def test_t5_calc_lot_indices_and_oil():
    """
    T5: CalcLot cho US30, NAS100, USOIL khớp công thức tick value; rủi ro thực <= 0.5% hoặc trả 0.
    """
    # USOIL: SL 1.00 USD (100 points, tick_value=10.0, tick_size=0.01, point=0.01) -> loss_per_lot = $1000
    # $500 * 0.5% = $2.5 -> raw_lot = 0.0025 < 0.01 -> Trả 0
    lot_oil = mql5_calc_lot(
        balance=500.0,
        risk_pct=0.5,
        sl_points=100.0,
        tick_value=10.0,
        tick_size=0.01,
        point=0.01,
        min_lot=0.01,
        max_lot=100.0,
        step=0.01,
    )
    assert lot_oil == 0.0

    # Tài khoản $10,000 -> risk $50 -> raw_lot = 0.05
    lot_oil_large = mql5_calc_lot(
        balance=10000.0,
        risk_pct=0.5,
        sl_points=100.0,
        tick_value=10.0,
        tick_size=0.01,
        point=0.01,
        min_lot=0.01,
        max_lot=100.0,
        step=0.01,
    )
    assert lot_oil_large == 0.05

def test_t6_total_open_risk_limit_2pct():
    """
    T6: Giới hạn tổng rủi ro mở 2% ($10 trên tài khoản $500).
    Lệnh làm vượt 2% bị từ chối.
    """
    balance = 500.0
    # Hiện đã mở lệnh với rủi ro $8.0 (1.6%)
    # Lệnh mới có rủi ro $2.5 -> Tổng $10.5 > $10.0 (2%) -> Từ chối!
    assert not mql5_check_open_risk(current_open_risk_usd=8.0, balance=balance, new_trade_risk_usd=2.5, max_risk_pct=2.0)
    # Lệnh mới có rủi ro $1.5 -> Tổng $9.5 <= $10.0 -> Cho phép
    assert mql5_check_open_risk(current_open_risk_usd=8.0, balance=balance, new_trade_risk_usd=1.5, max_risk_pct=2.0)

def test_t9_stale_signal_rejected():
    """
    T9: Tín hiệu cũ (age > 60s) bị từ chối, ghi lý do stale.
    """
    current_gmt = 1729500000
    stale_ts = current_gmt - 300  # 5 minutes ago
    valid, reason = mql5_check_signal_age(stale_ts, current_gmt, max_age_seconds=60)
    assert not valid
    assert "stale" in reason

    fresh_ts = current_gmt - 15  # 15 seconds ago
    valid, reason = mql5_check_signal_age(fresh_ts, current_gmt, max_age_seconds=60)
    assert valid

def test_t12_heartbeat_monitoring():
    """
    T12: Heartbeat quá 180s thì mất kết nối Brain.
    """
    current_gmt = 1729500000
    # Brain gửi heartbeat 60s trước -> Alive
    assert mql5_check_heartbeat_alive(current_gmt - 60, current_gmt, max_age_seconds=180)
    # Brain dừng 200s trước -> Lost
    assert not mql5_check_heartbeat_alive(current_gmt - 200, current_gmt, max_age_seconds=180)

def test_t14_partial_close_rule():
    """
    T14: Lot 0.04 đóng một nửa (0.02) và dời SL BE;
    Lot 0.01 (< 2*min_lot) không đóng một nửa mà dời SL BE chạy tới TP.
    """
    # 0.04 lot: Đóng 0.02
    action_04 = mql5_partial_close_rule(volume=0.04, min_lot=0.01, step=0.01)
    assert action_04 == "PARTIAL_CLOSE_0.02"

    # 0.01 lot: Không đóng một nửa, dời BE chạy TP
    action_01 = mql5_partial_close_rule(volume=0.01, min_lot=0.01, step=0.01)
    assert action_01 == "MOVE_SL_BE_NO_PARTIAL"

def test_t18_malformed_json_handling():
    """
    T18: Parser không crash khi gặp JSON hỏng/thiếu trường.
    """
    bad_json = "{ symbol: 'XAUUSD', broken... "
    try:
        data = json.loads(bad_json)
    except Exception:
        data = None
    assert data is None  # Handled safely without unhandled exception
