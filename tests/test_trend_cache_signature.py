import sys
import types
from pathlib import Path
from unittest.mock import MagicMock

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

if "MetaTrader5" not in sys.modules:
    mt5_stub = types.ModuleType("MetaTrader5")
    mt5_stub.TIMEFRAME_H4 = 16388
    mt5_stub.TIMEFRAME_D1 = 16408
    sys.modules["MetaTrader5"] = mt5_stub

from BIN import safetybot


def _mk_rates(count: int, start: float = 100.0) -> pd.DataFrame:
    closes = [float(start + i) for i in range(count)]
    base_ts = pd.Timestamp("2026-03-10 00:00:00", tz="UTC")
    times = [(base_ts + pd.Timedelta(hours=i)).tz_convert(safetybot.TZ_PL) for i in range(count)]
    return pd.DataFrame(
        {
            "time": times,
            "open": closes,
            "high": closes,
            "low": closes,
            "close": closes,
        }
    )


class _BarsStoreStub:
    def __init__(self, df_h4: pd.DataFrame, df_d1: pd.DataFrame):
        self.df_h4 = df_h4
        self.df_d1 = df_d1

    def read_resampled_df(self, base_symbol: str, timeframe_min: int, limit: int):  # noqa: ARG002
        if int(timeframe_min) == 240:
            return self.df_h4.tail(limit).reset_index(drop=True)
        if int(timeframe_min) == 1440:
            return self.df_d1.tail(limit).reset_index(drop=True)
        return None


def test_get_trend_reuses_full_cache_when_h4_d1_signature_is_unchanged(monkeypatch):
    original_ttl = int(getattr(safetybot.CFG, "trend_cache_ttl_sec", 3600))
    original_use_store = bool(getattr(safetybot.CFG, "hybrid_use_zmq_m5_bars", True))
    original_resample = bool(getattr(safetybot.CFG, "hybrid_use_mtf_resample_from_m5_store", True))
    try:
        safetybot.CFG.trend_cache_ttl_sec = 1
        safetybot.CFG.hybrid_use_zmq_m5_bars = True
        safetybot.CFG.hybrid_use_mtf_resample_from_m5_store = True

        engine = MagicMock()
        df_h4 = _mk_rates(90, start=100.0)
        df_d1 = _mk_rates(90, start=200.0)
        engine.bars_store = _BarsStoreStub(df_h4, df_d1)
        engine.copy_rates.side_effect = AssertionError("copy_rates should not be called when trend signature is unchanged")

        stg = safetybot.StandardStrategy(
            engine=engine,
            gov=MagicMock(),
            throttle=MagicMock(),
            db=MagicMock(),
            config=MagicMock(),
            risk_manager=MagicMock(),
        )
        symbol = "EURUSD.pro"
        stg.cache.trend_cache[symbol] = (0.0, "BUY", "BUY", "BUY")
        stg.cache.trend_cache_quality[symbol] = "FULL"
        stg.cache.trend_cache_signature[symbol] = stg._trend_signature_from_frames(df_h4, df_d1)

        result = stg.get_trend(symbol, "FX")

        assert result == ("BUY", "BUY", "BUY")
        assert engine.copy_rates.call_count == 0
    finally:
        safetybot.CFG.trend_cache_ttl_sec = original_ttl
        safetybot.CFG.hybrid_use_zmq_m5_bars = original_use_store
        safetybot.CFG.hybrid_use_mtf_resample_from_m5_store = original_resample
