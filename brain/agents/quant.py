"""
Quant Analyst - Quantitative Signal & Regime Identification
===========================================================
Xác định trạng thái thị trường (Market Regime):
- TRENDING (Mạnh): Chạy chiến lược TrendFollower (EMA + ADX)
- RANGING (Sideway): Chạy chiến lược MeanReversion (RSI + Bollinger Bands)
- BREAKOUT: Chạy chiến lược SessionBreakout (Phiên London / New York)
- VOLATILE BẤT THƯỜNG: Đứng ngoài (Stand Aside)
"""
import logging
import time
from pathlib import Path
from typing import List, Dict, Any
import yaml

try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False

logger = logging.getLogger("QuantAnalyst")


class QuantAnalyst:
    """
    Chuyên viên định lượng: Nhận diện regime và tính toán tín hiệu kỹ thuật.
    """

    def __init__(self, config_path: Path):
        self.config_path = config_path
        self.symbols_config = self._load_symbols_config()
        self._last_signal_time: Dict[str, float] = {}
        self.signal_debounce_sec = 900  # 15 phút chống lặp tín hiệu
        logger.info(f"QuantAnalyst sẵn sàng: Theo dõi kỹ thuật {len(self.symbols_config)} symbols.")

    def _load_symbols_config(self) -> List[Dict[str, Any]]:
        symbols_file = self.config_path / "symbols.yaml"
        if symbols_file.exists():
            try:
                with open(symbols_file, "r", encoding="utf-8") as f:
                    cfg = yaml.safe_load(f)
                    return cfg.get("symbols", [])
            except Exception as e:
                logger.warning(f"Lỗi đọc symbols.yaml: {e}")
        return [{"name": "XAUUSD"}, {"name": "EURUSD"}, {"name": "GBPUSD"}]

    def generate_signals(self) -> List[Dict[str, Any]]:
        """
        Quét các symbol và tạo danh sách tín hiệu kỹ thuật thô.
        """
        signals = []
        for sym_info in self.symbols_config:
            symbol = sym_info["name"]
            sig = self._analyze_symbol(symbol)
            if sig:
                signals.append(sig)
        return signals

    def _analyze_symbol(self, symbol: str) -> Dict[str, Any] | None:
        """
        Phân tích kỹ thuật và phát hiện regime cho symbol.
        Nếu MT5 đang kết nối, lấy nến M15/H1 thật để tính toán.
        """
        now = time.time()
        # Chống lặp tín hiệu: Mỗi symbol chỉ phát tín hiệu 1 lần trong 15 phút
        if now - self._last_signal_time.get(symbol, 0) < self.signal_debounce_sec:
            return None

        if MT5_AVAILABLE and mt5.terminal_info() is not None:
            # Lấy giá tick hiện tại
            tick = mt5.symbol_info_tick(symbol)
            if not tick:
                return None

            ask = tick.ask
            bid = tick.bid
            if ask <= 0 or bid <= 0:
                return None

            # Lấy 50 nến M15 để tính regime cơ bản
            rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M15, 0, 50)
            if rates is not None and len(rates) >= 30:
                closes = [r[4] for r in rates]
                sma20 = sum(closes[-20:]) / 20.0
                current_price = closes[-1]

                # Đo độ lệch chuẩn cho Mean Reversion
                variance = sum((c - sma20) ** 2 for c in closes[-20:]) / 20.0
                std = variance ** 0.5
                if std <= 0:
                    return None

                upper_bb = sma20 + 2.0 * std
                lower_bb = sma20 - 2.0 * std

                # P1 FIX: Đặt SL = 1.5 * std và TP = sma20 (~2 * std) để đạt R:R >= 1.33
                if current_price <= lower_bb and bid > 0:
                    sl = bid - 1.5 * std
                    tp = sma20
                    self._last_signal_time[symbol] = now
                    return {
                        "symbol": symbol,
                        "action": "BUY",
                        "strategy": "MeanReversion",
                        "price": bid,
                        "sl": round(sl, 4),
                        "tp": round(tp, 4),
                        "regime": "RANGING",
                        "confidence": 70,
                    }
                elif current_price >= upper_bb and ask > 0:
                    sl = ask + 1.5 * std
                    tp = sma20
                    self._last_signal_time[symbol] = now
                    return {
                        "symbol": symbol,
                        "action": "SELL",
                        "strategy": "MeanReversion",
                        "price": ask,
                        "sl": round(sl, 4),
                        "tp": round(tp, 4),
                        "regime": "RANGING",
                        "confidence": 70,
                    }

        return None
