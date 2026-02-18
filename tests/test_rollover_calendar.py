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


class _Dummy:
    pass


class _Config:
    def __init__(self, rollover: dict):
        self.rollover = rollover
        self.scheduler = {}


class TestRolloverCalendar(unittest.TestCase):
    def _strategy(self, rollover_cfg: dict) -> safetybot.StandardStrategy:
        return safetybot.StandardStrategy(
            engine=_Dummy(),
            gov=_Dummy(),
            throttle=_Dummy(),
            db=_Dummy(),
            config=_Config(rollover_cfg),
            risk_manager=_Dummy(),
        )

    def test_quarterly_dates_for_2026(self) -> None:
        self.assertEqual(safetybot.third_friday_date(2026, 3), dt.date(2026, 3, 20))
        got = safetybot.quarterly_rollover_dates(2026)
        self.assertEqual(got[3], dt.date(2026, 3, 18))
        self.assertEqual(got[6], dt.date(2026, 6, 17))
        self.assertEqual(got[9], dt.date(2026, 9, 16))
        self.assertEqual(got[12], dt.date(2026, 12, 16))

    def test_rollover_safe_blocks_quarter_window_for_index(self) -> None:
        stg = self._strategy(
            {
                "enabled": True,
                "auto_index_quarterly": True,
                "quarter_block_minutes_before": 45,
                "quarter_block_minutes_after": 30,
                "quarter_force_close_before_min": 10,
            }
        )
        orig_now_ny = safetybot.now_ny
        try:
            safetybot.now_ny = lambda: dt.datetime(2026, 3, 18, 16, 20, 0, tzinfo=safetybot.TZ_NY)
            self.assertFalse(stg.rollover_safe(symbol="US500"))
            self.assertTrue(stg.rollover_safe(symbol="EURUSD"))
        finally:
            safetybot.now_ny = orig_now_ny

    def test_force_close_quarter_window_for_index(self) -> None:
        stg = self._strategy(
            {
                "enabled": True,
                "auto_index_quarterly": True,
                "quarter_force_close_before_min": 10,
            }
        )
        orig_now_ny = safetybot.now_ny
        try:
            # Quarterly anchor 17:00 NY. This is inside quarter force-close (16:50-17:00)
            # but still outside legacy daily force-close (16:55-17:00).
            safetybot.now_ny = lambda: dt.datetime(2026, 3, 18, 16, 52, 0, tzinfo=safetybot.TZ_NY)
            self.assertTrue(stg.force_close_window(symbol="US500"))
            self.assertFalse(stg.force_close_window(symbol="EURUSD"))
        finally:
            safetybot.now_ny = orig_now_ny

    def test_manual_event_blocks_symbol(self) -> None:
        stg = self._strategy(
            {
                "enabled": True,
                "events": [
                    {
                        "date": "2026-03-19",
                        "time": "12:00",
                        "tz": "America/New_York",
                        "symbols": ["US500"],
                        "block_before_min": 10,
                        "block_after_min": 10,
                    }
                ],
            }
        )
        orig_now_ny = safetybot.now_ny
        try:
            safetybot.now_ny = lambda: dt.datetime(2026, 3, 19, 12, 5, 0, tzinfo=safetybot.TZ_NY)
            self.assertFalse(stg.rollover_safe(symbol="US500"))
            self.assertTrue(stg.rollover_safe(symbol="EURUSD"))
        finally:
            safetybot.now_ny = orig_now_ny


if __name__ == "__main__":
    raise SystemExit(unittest.main())
