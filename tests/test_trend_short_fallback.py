import sys
import types
import unittest
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


def _mk_rates(closes):
    closes_f = [float(x) for x in closes]
    n = len(closes_f)
    return pd.DataFrame(
        {
            "time": list(range(n)),
            "open": closes_f,
            "high": closes_f,
            "low": closes_f,
            "close": closes_f,
            "tick_volume": [1] * n,
        }
    )


class TestTrendShortFallback(unittest.TestCase):
    def setUp(self):
        self._orig_enabled = bool(getattr(safetybot.CFG, "trend_short_fallback_enabled", True))
        self._orig_min_h4 = int(getattr(safetybot.CFG, "trend_short_fallback_min_h4_rows", 3))
        self._orig_min_d1 = int(getattr(safetybot.CFG, "trend_short_fallback_min_d1_rows", 1))

    def tearDown(self):
        safetybot.CFG.trend_short_fallback_enabled = self._orig_enabled
        safetybot.CFG.trend_short_fallback_min_h4_rows = self._orig_min_h4
        safetybot.CFG.trend_short_fallback_min_d1_rows = self._orig_min_d1

    def _strategy_with_short_history(self):
        engine = MagicMock()
        df_h4 = _mk_rates([100.0, 101.0, 102.0, 103.0])
        df_d1 = _mk_rates([200.0])

        def _copy_rates(symbol, grp, timeframe, count):
            if int(timeframe) == int(getattr(safetybot.CFG, "timeframe_trend_h4", 16388)):
                return df_h4.copy()
            if int(timeframe) == int(getattr(safetybot.CFG, "timeframe_trend_d1", 16408)):
                return df_d1.copy()
            return None

        engine.copy_rates.side_effect = _copy_rates
        return safetybot.StandardStrategy(
            engine=engine,
            gov=MagicMock(),
            throttle=MagicMock(),
            db=MagicMock(),
            config=MagicMock(),
            risk_manager=MagicMock(),
        )

    def test_short_history_uses_fallback_when_enabled(self):
        safetybot.CFG.trend_short_fallback_enabled = True
        safetybot.CFG.trend_short_fallback_min_h4_rows = 3
        safetybot.CFG.trend_short_fallback_min_d1_rows = 1

        stg = self._strategy_with_short_history()
        trend_h4, trend_d1, structure_h4 = stg.get_trend("US500.pro", "INDEX")

        self.assertEqual("BUY", trend_h4)
        self.assertEqual("BUY", trend_d1)
        self.assertIn(structure_h4, {"BUY", "SELL"})
        self.assertNotEqual("NEUTRAL", structure_h4)

    def test_short_history_returns_neutral_when_fallback_disabled(self):
        safetybot.CFG.trend_short_fallback_enabled = False

        stg = self._strategy_with_short_history()
        trend_h4, trend_d1, structure_h4 = stg.get_trend("US500.pro", "INDEX")

        self.assertEqual(("NEUTRAL", "NEUTRAL", "NEUTRAL"), (trend_h4, trend_d1, structure_h4))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
