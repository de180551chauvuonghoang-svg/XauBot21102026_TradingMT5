"""
Unit tests for HeadTrader (Phase 2 - Intent-Only Signal Generation & Risk Officer Veto)
"""
import pytest
from pathlib import Path
from brain.agents.head_trader import HeadTrader
from brain.risk.risk_officer import RiskOfficer

CONFIG_DIR = Path(__file__).parent.parent / "config"

@pytest.fixture
def head_trader():
    risk = RiskOfficer(CONFIG_DIR)
    return HeadTrader(CONFIG_DIR, risk)

def test_head_trader_approves_aligned_intent_without_lots(head_trader):
    macro_bias = {
        "symbols_bias": {
            "XAUUSD": {"bias": "BULLISH", "reason": "Weak USD and falling real yields"}
        }
    }
    signals = [
        {
            "symbol": "XAUUSD",
            "action": "BUY",
            "price": 2720.0,
            "sl": 2710.0,
            "tp": 2740.0,
            "confidence": 75,
            "strategy": "MeanReversion",
        }
    ]
    account_state = {"equity": 500.0, "daily_loss_pct": 0.0, "weekly_loss_pct": 0.0, "total_dd_pct": 0.0}

    approved = head_trader.decide(macro_bias, signals, research_summary={}, account_state=account_state)
    assert len(approved) == 1
    sig = approved[0]
    assert sig["symbol"] == "XAUUSD"
    assert sig["type"] == "BUY"
    assert sig["stop_loss"] == 2710.0
    assert sig["take_profit1"] == 2740.0
    assert sig["magic"] == 1004
    # Single Execution Path assertion (A2 & A7): Brain never sets or outputs lot sizing!
    assert "lots" not in sig
    assert "lot" not in sig

def test_head_trader_filters_contrary_signals(head_trader):
    macro_bias = {
        "symbols_bias": {
            "XAUUSD": {"bias": "BEARISH", "reason": "Rising yields and hawkish Fed"}
        }
    }
    signals = [
        {
            "symbol": "XAUUSD",
            "action": "BUY",  # Contrary to BEARISH bias
            "price": 2720.0,
            "sl": 2710.0,
            "tp": 2740.0,
            "confidence": 75,
            "strategy": "MeanReversion",
        }
    ]
    account_state = {"equity": 500.0, "daily_loss_pct": 0.0, "weekly_loss_pct": 0.0, "total_dd_pct": 0.0}

    approved = head_trader.decide(macro_bias, signals, research_summary={}, account_state=account_state)
    assert len(approved) == 0

def test_head_trader_respects_circuit_breaker(head_trader):
    macro_bias = {
        "symbols_bias": {
            "EURUSD": {"bias": "NEUTRAL", "reason": "Range bound"}
        }
    }
    signals = [
        {
            "symbol": "EURUSD",
            "action": "BUY",
            "price": 1.0850,
            "sl": 1.0820,
            "tp": 1.0900,
            "confidence": 80,
            "strategy": "MeanReversion",
        }
    ]
    account_state = {"equity": 500.0, "daily_loss_pct": 2.5, "weekly_loss_pct": 0.0, "total_dd_pct": 0.0}

    approved = head_trader.decide(macro_bias, signals, research_summary={}, account_state=account_state)
    assert len(approved) == 0
