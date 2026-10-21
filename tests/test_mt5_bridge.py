"""
Unit tests for MT5Bridge (Phase 2 - Bridge Protocol & Schema Validation)
"""
import os
import json
import time
from datetime import datetime, timezone
from pathlib import Path
import pytest
from brain.bridge.mt5_bridge import MT5Bridge

@pytest.fixture
def bridge(tmp_path, monkeypatch):
    monkeypatch.setenv("ENABLE_DIRECT_EXEC", "false")
    b = MT5Bridge()
    b.bridge_dir = tmp_path
    b._heartbeat_file = tmp_path / "heartbeat.json"
    b._blackout_file = tmp_path / "news_blackout.json"
    b._kill_file = tmp_path / "kill_switch.json"
    b._state_file = tmp_path / "account_state.json"
    b._local_dir = tmp_path / "local"
    b._local_dir.mkdir(exist_ok=True)
    return b

def test_bridge_direct_exec_disabled_by_default(bridge):
    assert bridge.enable_direct_exec is False

def test_send_heartbeat_utc_schema(bridge):
    bridge.send_heartbeat()
    data = json.loads(bridge._heartbeat_file.read_text(encoding="utf-8"))
    assert data["status"] == "alive"
    assert "timestamp" in data
    assert "unix_ts" in data
    assert isinstance(data["unix_ts"], int)
    # Ensure unix_ts matches current UTC timestamp within 5 seconds
    now_ts = int(datetime.now(timezone.utc).timestamp())
    assert abs(data["unix_ts"] - now_ts) < 5

def test_send_signal_schema_and_no_lot(bridge):
    sig = {
        "symbol": "XAUUSD",
        "action": "BUY",
        "price": 2725.50,
        "stop_loss": 2715.0,
        "take_profit1": 2740.0,
        "confidence": 0.85,
        "strategy": "MeanReversion",
    }
    sig_id = bridge.send_signal(sig)
    sig_file = bridge.bridge_dir / f"{sig_id}.json"
    assert sig_file.exists()

    content = json.loads(sig_file.read_text(encoding="utf-8"))
    assert content["id"] == sig_id
    assert content["symbol"] == "XAUUSD"
    assert content["type"] == "BUY"
    assert content["price"] == 2725.50
    assert content["stop_loss"] == 2715.0
    assert content["take_profit1"] == 2740.0
    assert content["magic"] == 1004
    assert isinstance(content["created_at_utc"], int)
    # A2 & A3 & A7: ABSOLUTELY NO 'lot' field allowed! EA calculates lot size!
    assert "lot" not in content
    assert "lots" not in content

def test_send_news_blackout_formats_time_utc(bridge):
    events = [
        {
            "name": "US Non-Farm Payrolls",
            "time": "2026-10-21T14:30:00+00:00",
            "impact": "HIGH",
        }
    ]
    bridge.send_news_blackout(events)
    content = json.loads(bridge._blackout_file.read_text(encoding="utf-8"))
    assert len(content["events"]) == 1
    evt = content["events"][0]
    assert evt["name"] == "US Non-Farm Payrolls"
    assert isinstance(evt["time_utc"], int)
    assert evt["time_utc"] > 0

def test_send_empty_news_blackout_releases_e_a(bridge):
    bridge.send_news_blackout([])
    content = json.loads(bridge._blackout_file.read_text(encoding="utf-8"))
    assert content["events"] == []

def test_read_account_state_enriched_fields(bridge):
    state_data = {
        "daily_loss_pct": 1.2,
        "weekly_loss_pct": 2.1,
        "total_dd_pct": 3.5,
        "equity": 505.0,
        "balance": 500.0,
        "peak_equity": 510.0,
        "open_risk_pct": 1.0,
        "halted": False,
        "halt_reason": "Normal Operation",
    }
    bridge._state_file.write_text(json.dumps(state_data), encoding="utf-8")
    read_state = bridge.read_account_state()
    assert read_state["peak_equity"] == 510.0
    assert read_state["open_risk_pct"] == 1.0
    assert read_state["halted"] is False
