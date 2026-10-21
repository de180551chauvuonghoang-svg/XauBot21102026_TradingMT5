"""
Unit tests for RiskOfficer (Phase 2 - Safety Verification)
"""
import pytest
from pathlib import Path
from brain.risk.risk_officer import RiskOfficer

CONFIG_DIR = Path(__file__).parent.parent / "config"

@pytest.fixture
def risk_officer():
    return RiskOfficer(CONFIG_DIR)

def test_risk_officer_initialization(risk_officer):
    assert risk_officer.risk_pct == 0.5
    assert risk_officer.max_daily_loss == 2.0
    assert risk_officer.max_weekly_loss == 4.0
    assert risk_officer.max_total_dd == 10.0
    assert not risk_officer.is_halted()

def test_veto_missing_stop_loss(risk_officer):
    signal = {"symbol": "XAUUSD", "type": "BUY", "price": 2700.0, "confidence": 0.8}
    state = {"daily_loss_pct": 0.0, "weekly_loss_pct": 0.0, "total_dd_pct": 0.0}
    approved, reason = risk_officer.veto(signal, state)
    assert not approved
    assert "NO HARD SL" in reason

def test_veto_daily_loss_exceeded(risk_officer):
    signal = {"symbol": "XAUUSD", "type": "BUY", "price": 2700.0, "stop_loss": 2690.0, "confidence": 0.8}
    state = {"daily_loss_pct": 2.5, "weekly_loss_pct": 0.0, "total_dd_pct": 0.0}
    approved, reason = risk_officer.veto(signal, state)
    assert not approved
    assert "Daily circuit breaker" in reason
    assert risk_officer.is_halted()

def test_veto_weekly_loss_exceeded(risk_officer):
    signal = {"symbol": "EURUSD", "type": "BUY", "price": 1.0850, "stop_loss": 1.0820, "confidence": 0.8}
    state = {"daily_loss_pct": 0.5, "weekly_loss_pct": 4.5, "total_dd_pct": 2.0}
    approved, reason = risk_officer.veto(signal, state)
    assert not approved
    assert "Weekly circuit breaker" in reason
    assert risk_officer.is_halted()

def test_veto_total_dd_exceeded(risk_officer):
    signal = {"symbol": "EURUSD", "type": "BUY", "price": 1.0850, "stop_loss": 1.0820, "confidence": 0.8}
    state = {"daily_loss_pct": 0.5, "weekly_loss_pct": 1.0, "total_dd_pct": 10.5}
    approved, reason = risk_officer.veto(signal, state)
    assert not approved
    assert "Total DD circuit breaker" in reason
    assert risk_officer.is_halted()

def test_veto_ea_halted_state(risk_officer):
    signal = {"symbol": "XAUUSD", "type": "BUY", "price": 2700.0, "stop_loss": 2690.0, "confidence": 0.8}
    state = {"daily_loss_pct": 0.5, "weekly_loss_pct": 1.0, "total_dd_pct": 2.0, "halted": True, "halt_reason": "Daily loss limit reached"}
    approved, reason = risk_officer.veto(signal, state)
    assert not approved
    assert "EA Halted" in reason
    assert risk_officer.is_halted()

def test_veto_low_confidence(risk_officer):
    signal = {"symbol": "XAUUSD", "type": "BUY", "price": 2700.0, "stop_loss": 2690.0, "confidence": 0.50}
    state = {"daily_loss_pct": 0.0, "weekly_loss_pct": 0.0, "total_dd_pct": 0.0}
    approved, reason = risk_officer.veto(signal, state)
    assert not approved
    assert "threshold" in reason

def test_approved_valid_signal(risk_officer):
    signal = {"symbol": "XAUUSD", "type": "BUY", "price": 2700.0, "stop_loss": 2690.0, "take_profit": 2720.0, "confidence": 0.75}
    state = {"daily_loss_pct": 0.5, "weekly_loss_pct": 1.0, "total_dd_pct": 2.0, "halted": False}
    approved, reason = risk_officer.veto(signal, state)
    assert approved
    assert reason == "APPROVED"
