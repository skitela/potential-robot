import datetime as dt
import sys
import types
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

if "MetaTrader5" not in sys.modules:
    mt5_stub = types.ModuleType("MetaTrader5")
    mt5_stub.TIMEFRAME_M5 = 5
    mt5_stub.TIMEFRAME_H4 = 16388
    mt5_stub.TIMEFRAME_D1 = 16408
    sys.modules["MetaTrader5"] = mt5_stub

import safetybot


class TestTimeAnchorRegressionGuard(unittest.TestCase):
    def test_time_anchor_skips_large_backward_update(self) -> None:
        a = safetybot.TimeAnchor()
        old = safetybot.CFG.time_anchor_max_backward_sec
        try:
            safetybot.CFG.time_anchor_max_backward_sec = 120
            t0 = dt.datetime(2026, 2, 18, 10, 30, 0, tzinfo=safetybot.UTC)
            a.update(t0)
            self.assertTrue(a._have)
            self.assertEqual(a._server_utc, t0)

            stale = dt.datetime(2026, 2, 17, 10, 30, 0, tzinfo=safetybot.UTC)
            a.update(stale)
            self.assertEqual(a._server_utc, t0)

            t1 = dt.datetime(2026, 2, 18, 10, 30, 30, tzinfo=safetybot.UTC)
            a.update(t1)
            self.assertEqual(a._server_utc, t1)
        finally:
            safetybot.CFG.time_anchor_max_backward_sec = old


if __name__ == "__main__":
    raise SystemExit(unittest.main())
