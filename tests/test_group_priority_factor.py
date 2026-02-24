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
    def __init__(self, *, price=None, order=None, sys_used=None):
        self.price = {str(k).upper(): int(v) for k, v in (price or {}).items()}
        self.order = {str(k).upper(): int(v) for k, v in (order or {}).items()}
        self.sys_used = {str(k).upper(): int(v) for k, v in (sys_used or {}).items()}

    def group_price_used_today(self, grp: str) -> int:
        return int(self.price.get(str(grp).upper(), 0))

    def get_order_group_actions_day(self, grp: str, now_dt=None, emergency: bool = False) -> int:
        return int(self.order.get(str(grp).upper(), 0))

    def group_sys_used_today(self, grp: str) -> int:
        return int(self.sys_used.get(str(grp).upper(), 0))


class TestGroupPriorityFactor(unittest.TestCase):
    def _pl_to_utc(self, hh: int, mm: int) -> dt.datetime:
        pl_dt = dt.datetime(2026, 2, 23, hh, mm, tzinfo=safetybot.TZ_PL)
        return pl_dt.astimezone(safetybot.UTC)

    def _cfg_snapshot(self):
        return (
            safetybot.CFG.group_price_shares,
            safetybot.CFG.group_borrow_fraction,
            safetybot.CFG.group_borrow_unlock_power,
            safetybot.CFG.group_priority_min_factor,
            safetybot.CFG.group_priority_max_factor,
            safetybot.CFG.group_priority_pressure_weight,
            safetybot.CFG.trade_windows,
            safetybot.CFG.per_group,
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
            safetybot.CFG.group_priority_min_factor,
            safetybot.CFG.group_priority_max_factor,
            safetybot.CFG.group_priority_pressure_weight,
            safetybot.CFG.trade_windows,
            safetybot.CFG.per_group,
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

    def _configure(self) -> None:
        safetybot.CFG.group_price_shares = {"FX": 1.0, "METAL": 1.0}
        safetybot.CFG.group_borrow_fraction = 0.0
        safetybot.CFG.group_borrow_unlock_power = 1.0
        safetybot.CFG.group_priority_min_factor = 0.7
        safetybot.CFG.group_priority_max_factor = 1.3
        safetybot.CFG.group_priority_pressure_weight = 0.5
        safetybot.CFG.trade_windows = {
            "FX_ALL": {"group": "FX", "anchor_tz": "Europe/Warsaw", "start_hm": (0, 0), "end_hm": (23, 59)},
            "METAL_ALL": {"group": "METAL", "anchor_tz": "Europe/Warsaw", "start_hm": (0, 0), "end_hm": (23, 59)},
        }
        safetybot.CFG.per_group = {"FX": {"priority_boost": 1.0}, "METAL": {"priority_boost": 1.0}}
        safetybot.CFG.price_budget_day = 200
        safetybot.CFG.price_emergency_reserve_fraction = 0.0
        safetybot.CFG.price_soft_fraction = 1.0
        safetybot.CFG.order_budget_day = 200
        safetybot.CFG.order_emergency_reserve_fraction = 0.0
        safetybot.CFG.sys_budget_day = 200
        safetybot.CFG.sys_emergency_reserve_fraction = 0.0
        safetybot.CFG.sys_emergency_reserve = 0
        safetybot.CFG.sys_soft_fraction = 1.0

    def test_priority_factor_drops_with_pressure(self) -> None:
        prev = self._cfg_snapshot()
        try:
            self._configure()
            now_u = self._pl_to_utc(12, 0)
            low = safetybot.RequestGovernor(
                _DbStub(price={"FX": 5}, order={"FX": 5}, sys_used={"FX": 5})
            ).group_priority_factor("FX", now_dt=now_u)
            high = safetybot.RequestGovernor(
                _DbStub(price={"FX": 90}, order={"FX": 90}, sys_used={"FX": 90})
            ).group_priority_factor("FX", now_dt=now_u)
            self.assertGreater(low, high)
        finally:
            self._cfg_restore(prev)

    def test_priority_boost_applies_for_group(self) -> None:
        prev = self._cfg_snapshot()
        try:
            self._configure()
            safetybot.CFG.per_group = {"FX": {"priority_boost": 1.2}, "METAL": {"priority_boost": 0.9}}
            gov = safetybot.RequestGovernor(_DbStub())
            now_u = self._pl_to_utc(12, 0)
            fx = gov.group_priority_factor("FX", now_dt=now_u)
            metal = gov.group_priority_factor("METAL", now_dt=now_u)
            self.assertGreater(fx, metal)
        finally:
            self._cfg_restore(prev)

    def test_priority_factor_is_clamped(self) -> None:
        prev = self._cfg_snapshot()
        try:
            self._configure()
            safetybot.CFG.group_priority_min_factor = 0.8
            safetybot.CFG.group_priority_max_factor = 1.1
            safetybot.CFG.per_group = {"FX": {"priority_boost": 3.0}}
            gov = safetybot.RequestGovernor(_DbStub(price={"FX": 150}, order={"FX": 150}, sys_used={"FX": 150}))
            now_u = self._pl_to_utc(12, 0)
            f = gov.group_priority_factor("FX", now_dt=now_u)
            self.assertGreaterEqual(f, 0.8)
            self.assertLessEqual(f, 1.1)
        finally:
            self._cfg_restore(prev)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
