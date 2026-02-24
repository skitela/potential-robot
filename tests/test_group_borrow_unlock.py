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


class _DbStub:
    def __init__(self, price_used=None, order_used=None, sys_used=None):
        self.price_used = {str(k).upper(): int(v) for k, v in (price_used or {}).items()}
        self.order_used = {str(k).upper(): int(v) for k, v in (order_used or {}).items()}
        self.sys_used = {str(k).upper(): int(v) for k, v in (sys_used or {}).items()}

    def group_price_used_today(self, grp: str) -> int:
        return int(self.price_used.get(str(grp).upper(), 0))

    def get_order_group_actions_day(self, grp: str, now_dt=None, emergency: bool = False) -> int:
        return int(self.order_used.get(str(grp).upper(), 0))

    def group_sys_used_today(self, grp: str) -> int:
        return int(self.sys_used.get(str(grp).upper(), 0))


class TestGroupBorrowUnlock(unittest.TestCase):
    def _pl_to_utc(self, hh: int, mm: int) -> dt.datetime:
        pl_dt = dt.datetime(2026, 2, 23, hh, mm, tzinfo=safetybot.TZ_PL)
        return pl_dt.astimezone(safetybot.UTC)

    def _cfg_snapshot(self):
        return (
            safetybot.CFG.group_price_shares,
            safetybot.CFG.group_borrow_fraction,
            safetybot.CFG.group_borrow_unlock_power,
            safetybot.CFG.trade_windows,
            safetybot.CFG.price_budget_day,
            safetybot.CFG.price_emergency_reserve_fraction,
            safetybot.CFG.price_soft_fraction,
            safetybot.CFG.order_budget_day,
            safetybot.CFG.order_emergency_reserve_fraction,
            safetybot.CFG.sys_budget_day,
            safetybot.CFG.sys_emergency_reserve_fraction,
            safetybot.CFG.sys_emergency_reserve,
            safetybot.CFG.sys_soft_fraction,
        )

    def _cfg_restore(self, prev) -> None:
        (
            safetybot.CFG.group_price_shares,
            safetybot.CFG.group_borrow_fraction,
            safetybot.CFG.group_borrow_unlock_power,
            safetybot.CFG.trade_windows,
            safetybot.CFG.price_budget_day,
            safetybot.CFG.price_emergency_reserve_fraction,
            safetybot.CFG.price_soft_fraction,
            safetybot.CFG.order_budget_day,
            safetybot.CFG.order_emergency_reserve_fraction,
            safetybot.CFG.sys_budget_day,
            safetybot.CFG.sys_emergency_reserve_fraction,
            safetybot.CFG.sys_emergency_reserve,
            safetybot.CFG.sys_soft_fraction,
        ) = prev

    def _configure_simple_budgets(self) -> None:
        safetybot.CFG.group_price_shares = {"FX": 1.0, "INDEX": 1.0, "METAL": 1.0}
        safetybot.CFG.group_borrow_fraction = 1.0
        safetybot.CFG.group_borrow_unlock_power = 1.0
        safetybot.CFG.trade_windows = {
            "FX_AM": {"group": "FX", "anchor_tz": "Europe/Warsaw", "start_hm": (9, 0), "end_hm": (12, 0)},
            "INDEX_MD": {"group": "INDEX", "anchor_tz": "Europe/Warsaw", "start_hm": (12, 0), "end_hm": (15, 0)},
            "METAL_PM": {"group": "METAL", "anchor_tz": "Europe/Warsaw", "start_hm": (15, 0), "end_hm": (18, 0)},
        }
        safetybot.CFG.price_budget_day = 90
        safetybot.CFG.price_emergency_reserve_fraction = 0.0
        safetybot.CFG.price_soft_fraction = 1.0
        safetybot.CFG.order_budget_day = 90
        safetybot.CFG.order_emergency_reserve_fraction = 0.0
        safetybot.CFG.sys_budget_day = 90
        safetybot.CFG.sys_emergency_reserve_fraction = 0.0
        safetybot.CFG.sys_emergency_reserve = 0
        safetybot.CFG.sys_soft_fraction = 1.0

    def test_unlock_ratio_respects_window_progress(self) -> None:
        prev = self._cfg_snapshot()
        try:
            self._configure_simple_budgets()
            gov = safetybot.RequestGovernor(_DbStub())
            pre = gov._group_window_unlock_ratio("METAL", now_dt=self._pl_to_utc(14, 0))
            mid = gov._group_window_unlock_ratio("METAL", now_dt=self._pl_to_utc(16, 30))
            post = gov._group_window_unlock_ratio("METAL", now_dt=self._pl_to_utc(19, 0))
            self.assertAlmostEqual(0.0, pre, places=4)
            self.assertAlmostEqual(0.5, mid, places=2)
            self.assertAlmostEqual(1.0, post, places=4)
        finally:
            self._cfg_restore(prev)

    def test_price_borrow_uses_only_unlocked_other_groups(self) -> None:
        prev = self._cfg_snapshot()
        try:
            self._configure_simple_budgets()
            gov = safetybot.RequestGovernor(
                _DbStub(
                    price_used={"FX": 10, "INDEX": 0, "METAL": 0},
                    order_used={"FX": 0, "INDEX": 0, "METAL": 0},
                    sys_used={"FX": 0, "INDEX": 0, "METAL": 0},
                )
            )
            # 13:00 PL -> FX done (full unlock), METAL not started (no unlock).
            b_index = gov._group_borrow_allowance("INDEX", now_dt=self._pl_to_utc(13, 0))
            self.assertEqual(20, b_index)
        finally:
            self._cfg_restore(prev)

    def test_order_borrow_grows_after_additional_window_closes(self) -> None:
        prev = self._cfg_snapshot()
        try:
            self._configure_simple_budgets()
            gov = safetybot.RequestGovernor(
                _DbStub(
                    price_used={"FX": 0, "INDEX": 0, "METAL": 0},
                    order_used={"FX": 10, "INDEX": 0, "METAL": 0},
                    sys_used={"FX": 0, "INDEX": 0, "METAL": 0},
                )
            )
            # 16:00 PL -> FX and INDEX are fully unlocked, METAL in progress.
            b_metal = gov.order_group_borrow_allowance("METAL", now_dt=self._pl_to_utc(16, 0))
            self.assertEqual(50, b_metal)
        finally:
            self._cfg_restore(prev)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
