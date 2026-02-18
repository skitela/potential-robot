import sys
import time
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


class _Pos:
    def __init__(self, **kwargs):
        for k, v in kwargs.items():
            setattr(self, k, v)


class TestPositionTimeStopUtils(unittest.TestCase):
    def test_position_open_ts_prefers_valid_candidates(self) -> None:
        now_ts = int(time.time())
        pos = _Pos(time=now_ts - 120, time_msc=(now_ts - 90) * 1000)
        got = safetybot.position_open_ts_utc(pos)
        self.assertEqual(got, now_ts - 120)

    def test_position_open_ts_supports_millis(self) -> None:
        now_ts = int(time.time())
        pos = _Pos(time=0, time_msc=(now_ts - 300) * 1000)
        got = safetybot.position_open_ts_utc(pos)
        self.assertEqual(got, now_ts - 300)

    def test_position_age_sec_non_negative(self) -> None:
        pos = _Pos(time=1_000_000_000)
        got = safetybot.position_age_sec(pos, now_ts=999_999_990)
        self.assertEqual(got, 0)

    def test_position_time_stop_minutes_for_mode(self) -> None:
        old_hot = safetybot.CFG.position_time_stop_hot_min
        old_warm = safetybot.CFG.position_time_stop_warm_min
        old_eco = safetybot.CFG.position_time_stop_eco_min
        try:
            safetybot.CFG.position_time_stop_hot_min = 11
            safetybot.CFG.position_time_stop_warm_min = 22
            safetybot.CFG.position_time_stop_eco_min = 33
            self.assertEqual(safetybot.position_time_stop_minutes_for_mode("HOT"), 11)
            self.assertEqual(safetybot.position_time_stop_minutes_for_mode("WARM"), 22)
            self.assertEqual(safetybot.position_time_stop_minutes_for_mode("ECO"), 33)
            self.assertEqual(safetybot.position_time_stop_minutes_for_mode("unknown"), 33)
        finally:
            safetybot.CFG.position_time_stop_hot_min = old_hot
            safetybot.CFG.position_time_stop_warm_min = old_warm
            safetybot.CFG.position_time_stop_eco_min = old_eco


if __name__ == "__main__":
    raise SystemExit(unittest.main())
