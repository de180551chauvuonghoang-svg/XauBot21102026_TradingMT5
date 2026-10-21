"""
Unit tests for QuantAnalyst (Phase 2 - Quant Strategy & Debounce Logic)
"""
import time
from pathlib import Path
import pytest
from brain.agents.quant import QuantAnalyst

CONFIG_DIR = Path(__file__).parent.parent / "config"

@pytest.fixture
def quant_analyst():
    return QuantAnalyst(CONFIG_DIR)

def test_quant_analyst_initialization(quant_analyst):
    assert len(quant_analyst.symbols_config) >= 3
    assert quant_analyst.signal_debounce_sec == 900

def test_quant_analyst_debounce():
    qa = QuantAnalyst(CONFIG_DIR)
    qa._last_signal_time["XAUUSD"] = time.time() - 300  # 5 minutes ago (< 15 mins)
    sig = qa._analyze_symbol("XAUUSD")
    assert sig is None  # Must debounce
