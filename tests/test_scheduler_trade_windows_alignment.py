import datetime as dt
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

import scheduler
from scheduler import ActivityController


class _DB:
    def price_req_for_hour(self, grp: str, symbol: str, ny_hour: int, lookback_days: int = 14) -> int:
        return 0

    def pnl_net_for_hour(self, grp: str, symbol: str, ny_hour: int, lookback_days: int = 14) -> float:
        return 0.0

    def get_p80_spread(self, symbol: str) -> float:
        return 0.0


def _utc_from_local(year: int, month: int, day: int, hour: int, minute: int, tz_name: str) -> dt.datetime:
    local = dt.datetime(year, month, day, hour, minute, tzinfo=ZoneInfo(tz_name))
    return local.astimezone(dt.timezone.utc)


class TestSchedulerTradeWindowsAlignment(unittest.TestCase):
    def _with_now_utc(self, fake_now_utc: dt.datetime):
        original = scheduler.now_utc
        scheduler.now_utc = lambda: fake_now_utc
        return original

    def test_time_weight_uses_dynamic_trade_windows_from_strategy(self) -> None:
        cfg = SimpleNamespace(
            strategy={
                "trade_windows": {
                    "FX_EVE": {
                        "group": "FX",
                        "anchor_tz": "Europe/Warsaw",
                        "start_hm": [20, 0],
                        "end_hm": [22, 0],
                    }
                }
            },
            index_profile_map={},
            scheduler={},
        )
        ctrl = ActivityController(_DB(), cfg)
        original = self._with_now_utc(_utc_from_local(2026, 2, 23, 21, 0, "Europe/Warsaw"))
        try:
            self.assertEqual(1.0, ctrl.time_weight("FX", "EURUSD"))
        finally:
            scheduler.now_utc = original

        original = self._with_now_utc(_utc_from_local(2026, 2, 23, 23, 0, "Europe/Warsaw"))
        try:
            self.assertEqual(0.25, ctrl.time_weight("FX", "EURUSD"))
        finally:
            scheduler.now_utc = original

    def test_time_weight_fallback_is_aligned_with_default_cfg_windows(self) -> None:
        cfg = SimpleNamespace(strategy={}, index_profile_map={}, scheduler={})
        ctrl = ActivityController(_DB(), cfg)

        original = self._with_now_utc(_utc_from_local(2026, 2, 23, 10, 0, "Europe/Warsaw"))
        try:
            self.assertEqual(1.0, ctrl.time_weight("FX", "EURUSD"))
            self.assertEqual(0.25, ctrl.time_weight("METAL", "XAUUSD"))
        finally:
            scheduler.now_utc = original

        original = self._with_now_utc(_utc_from_local(2026, 2, 23, 15, 0, "Europe/Warsaw"))
        try:
            self.assertEqual(0.25, ctrl.time_weight("FX", "EURUSD"))
            self.assertEqual(1.0, ctrl.time_weight("METAL", "XAUUSD"))
        finally:
            scheduler.now_utc = original


if __name__ == "__main__":
    raise SystemExit(unittest.main())

