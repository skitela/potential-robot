import datetime as dt
import sys
import tempfile
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


class TestSafetyBotTimezoneContract(unittest.TestCase):
    def test_day_keys_across_ny_utc_pl(self) -> None:
        ts = dt.datetime(2026, 2, 14, 23, 30, 0, tzinfo=safetybot.UTC)
        ny_day, ny_hour = safetybot.ny_day_hour_key(ts)
        self.assertEqual(ny_day, "2026-02-14")
        self.assertEqual(ny_hour, 18)
        self.assertEqual(safetybot.utc_day_key(ts), "2026-02-14")
        self.assertEqual(safetybot.pl_day_key(ts), "2026-02-15")

    def test_pl_day_start_utc_ts(self) -> None:
        ts = dt.datetime(2026, 2, 14, 23, 30, 0, tzinfo=safetybot.UTC)
        got = safetybot.pl_day_start_utc_ts(ts)
        expected = int(dt.datetime(2026, 2, 14, 23, 0, 0, tzinfo=safetybot.UTC).timestamp())
        self.assertEqual(got, expected)

    def test_seconds_until_next_midnights(self) -> None:
        ts = dt.datetime(2026, 2, 14, 22, 59, 0, tzinfo=safetybot.UTC)
        self.assertEqual(safetybot._seconds_until_next_pl_midnight(ts), 60)
        self.assertEqual(safetybot._seconds_until_next_utc_midnight(ts), 3660)
        self.assertEqual(safetybot._seconds_until_next_ny_midnight(ts), 21660)

    def test_order_actions_strict_guard_uses_max_across_day_keys(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            db = safetybot.Persistence(Path(tmp) / "safetybot_time.db")
            try:
                now_dt = dt.datetime(2026, 2, 14, 23, 30, 0, tzinfo=safetybot.UTC)
                day_ny, _ = safetybot.ny_day_hour_key(now_dt)
                day_utc = safetybot.utc_day_key(now_dt)
                day_pl = safetybot.pl_day_key(now_dt)

                db.state_set(f"order_actions_ny:{day_ny}", "2")
                db.state_set(f"order_actions_utc:{day_utc}", "7")
                db.state_set(f"order_actions_pl:{day_pl}", "5")

                state = db.get_order_actions_state(now_dt=now_dt)
                self.assertEqual(state["ny"], 2)
                self.assertEqual(state["utc"], 7)
                self.assertEqual(state["pl"], 5)
                self.assertEqual(state["used"], 7)
                self.assertEqual(db.get_order_actions_day(now_dt=now_dt), 7)
            finally:
                db.conn.close()


if __name__ == "__main__":
    raise SystemExit(unittest.main())
