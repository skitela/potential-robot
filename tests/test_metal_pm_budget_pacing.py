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


class _GovStub:
    def __init__(self, cap: int, borrow: int = 0):
        self._cap = int(cap)
        self._borrow = int(borrow)

    def order_group_cap(self, grp: str) -> int:
        return int(self._cap)

    def order_group_borrow_allowance(self, grp: str) -> int:
        return int(self._borrow)


class _DbStub:
    def __init__(self, used: int):
        self._used = int(used)

    def get_order_group_actions_day(self, grp: str, now_dt=None, emergency: bool = False) -> int:
        return int(self._used)


class TestMetalPmBudgetPacing(unittest.TestCase):
    def _pl_time_to_utc(self, hh: int, mm: int) -> dt.datetime:
        pl_dt = dt.datetime(2026, 2, 23, hh, mm, tzinfo=safetybot.TZ_PL)
        return pl_dt.astimezone(safetybot.UTC)

    def test_limit_curve(self) -> None:
        self.assertAlmostEqual(safetybot.metal_pacing_limit_ratio(0.10), 0.25, places=4)
        self.assertAlmostEqual(safetybot.metal_pacing_limit_ratio(0.50), 0.70, places=4)
        self.assertAlmostEqual(safetybot.metal_pacing_limit_ratio(0.90), 1.00, places=4)

    def test_allows_when_usage_within_early_limit(self) -> None:
        prev = (safetybot.CFG.metal_budget_pacing_enabled, safetybot.CFG.trade_windows)
        try:
            safetybot.CFG.metal_budget_pacing_enabled = True
            safetybot.CFG.trade_windows = {
                "METAL_PM": {"group": "METAL", "anchor_tz": "Europe/Warsaw", "start_hm": (14, 0), "end_hm": (17, 0)}
            }
            ok, meta = safetybot.metal_budget_pacing_allows_entry(
                _GovStub(cap=100),
                _DbStub(used=20),
                now_dt=self._pl_time_to_utc(14, 30),
            )
            self.assertTrue(ok)
            self.assertLessEqual(float(meta.get("used_ratio", 1.0)), 0.30)
        finally:
            (safetybot.CFG.metal_budget_pacing_enabled, safetybot.CFG.trade_windows) = prev

    def test_blocks_when_usage_too_high_early(self) -> None:
        prev = (safetybot.CFG.metal_budget_pacing_enabled, safetybot.CFG.trade_windows)
        try:
            safetybot.CFG.metal_budget_pacing_enabled = True
            safetybot.CFG.trade_windows = {
                "METAL_PM": {"group": "METAL", "anchor_tz": "Europe/Warsaw", "start_hm": (14, 0), "end_hm": (17, 0)}
            }
            ok, meta = safetybot.metal_budget_pacing_allows_entry(
                _GovStub(cap=100),
                _DbStub(used=40),
                now_dt=self._pl_time_to_utc(14, 30),
            )
            self.assertFalse(ok)
            self.assertGreater(float(meta.get("used_ratio", 0.0)), float(meta.get("limit_ratio", 0.0)))
        finally:
            (safetybot.CFG.metal_budget_pacing_enabled, safetybot.CFG.trade_windows) = prev


if __name__ == "__main__":
    raise SystemExit(unittest.main())
