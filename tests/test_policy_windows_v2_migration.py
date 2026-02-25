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


class TestPolicyWindowsV2Migration(unittest.TestCase):
    def _cfg_snapshot(self):
        return (
            safetybot.CFG.policy_risk_windows_enabled,
            safetybot.CFG.friday_risk_enabled,
            safetybot.CFG.friday_risk_ny_start_hm,
            safetybot.CFG.friday_risk_ny_end_hm,
            safetybot.CFG.friday_risk_groups,
            safetybot.CFG.friday_risk_close_only_groups,
            safetybot.CFG.friday_risk_borrow_block,
            safetybot.CFG.friday_risk_priority_factor,
            safetybot.CFG.reopen_guard_enabled,
            safetybot.CFG.reopen_guard_ny_start_hm,
            safetybot.CFG.reopen_guard_minutes,
            safetybot.CFG.reopen_guard_groups,
            safetybot.CFG.reopen_guard_close_only_groups,
            safetybot.CFG.reopen_guard_borrow_block,
            safetybot.CFG.reopen_guard_priority_factor,
            safetybot.CFG.policy_group_arbitration_enabled,
            safetybot.CFG.policy_shadow_mode_enabled,
            safetybot.CFG.group_price_shares,
            safetybot.CFG.group_borrow_fraction,
            safetybot.CFG.group_borrow_fraction_by_group,
            safetybot.CFG.group_priority_boost,
            safetybot.CFG.group_overlap_priority_factor,
            safetybot.CFG.group_priority_min_factor,
            safetybot.CFG.group_priority_max_factor,
            safetybot.CFG.policy_overlap_arbitration_enabled,
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
            safetybot.CFG.policy_risk_windows_enabled,
            safetybot.CFG.friday_risk_enabled,
            safetybot.CFG.friday_risk_ny_start_hm,
            safetybot.CFG.friday_risk_ny_end_hm,
            safetybot.CFG.friday_risk_groups,
            safetybot.CFG.friday_risk_close_only_groups,
            safetybot.CFG.friday_risk_borrow_block,
            safetybot.CFG.friday_risk_priority_factor,
            safetybot.CFG.reopen_guard_enabled,
            safetybot.CFG.reopen_guard_ny_start_hm,
            safetybot.CFG.reopen_guard_minutes,
            safetybot.CFG.reopen_guard_groups,
            safetybot.CFG.reopen_guard_close_only_groups,
            safetybot.CFG.reopen_guard_borrow_block,
            safetybot.CFG.reopen_guard_priority_factor,
            safetybot.CFG.policy_group_arbitration_enabled,
            safetybot.CFG.policy_shadow_mode_enabled,
            safetybot.CFG.group_price_shares,
            safetybot.CFG.group_borrow_fraction,
            safetybot.CFG.group_borrow_fraction_by_group,
            safetybot.CFG.group_priority_boost,
            safetybot.CFG.group_overlap_priority_factor,
            safetybot.CFG.group_priority_min_factor,
            safetybot.CFG.group_priority_max_factor,
            safetybot.CFG.policy_overlap_arbitration_enabled,
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

    def _ny_to_utc(self, year: int, month: int, day: int, hh: int, mm: int) -> dt.datetime:
        ny_dt = dt.datetime(year, month, day, hh, mm, tzinfo=safetybot.TZ_NY)
        return ny_dt.astimezone(safetybot.UTC)

    def test_in_window_supports_overnight(self) -> None:
        local_dt = dt.datetime(2026, 2, 23, 23, 30, tzinfo=safetybot.TZ_PL)
        self.assertTrue(safetybot.in_window(local_dt, (21, 0), (7, 0)))
        self.assertFalse(safetybot.in_window(local_dt.replace(hour=8, minute=15), (21, 0), (7, 0)))

    def test_friday_risk_blocks_new_fx_entries(self) -> None:
        prev = self._cfg_snapshot()
        try:
            safetybot.CFG.policy_risk_windows_enabled = True
            safetybot.CFG.friday_risk_enabled = True
            safetybot.CFG.friday_risk_groups = ("FX",)
            safetybot.CFG.friday_risk_close_only_groups = ("FX",)
            safetybot.CFG.friday_risk_borrow_block = True
            safetybot.CFG.friday_risk_priority_factor = 0.60
            now_u = self._ny_to_utc(2026, 2, 27, 16, 30)
            st = safetybot.group_market_risk_state("FX", now_dt=now_u)
            self.assertTrue(bool(st.get("friday_risk")))
            self.assertFalse(bool(st.get("entry_allowed")))
            self.assertTrue(bool(st.get("borrow_blocked")))
            self.assertIn("FRIDAY", str(st.get("reason")))
        finally:
            self._cfg_restore(prev)

    def test_reopen_guard_blocks_new_fx_entries(self) -> None:
        prev = self._cfg_snapshot()
        try:
            safetybot.CFG.policy_risk_windows_enabled = True
            safetybot.CFG.reopen_guard_enabled = True
            safetybot.CFG.reopen_guard_groups = ("FX",)
            safetybot.CFG.reopen_guard_close_only_groups = ("FX",)
            safetybot.CFG.reopen_guard_borrow_block = True
            safetybot.CFG.reopen_guard_minutes = 45
            now_u = self._ny_to_utc(2026, 3, 1, 17, 20)
            st = safetybot.group_market_risk_state("FX", now_dt=now_u)
            self.assertTrue(bool(st.get("reopen_guard")))
            self.assertFalse(bool(st.get("entry_allowed")))
            self.assertTrue(bool(st.get("borrow_blocked")))
            self.assertIn("REOPEN", str(st.get("reason")))
        finally:
            self._cfg_restore(prev)

    def test_borrow_is_blocked_in_active_risk_window(self) -> None:
        prev = self._cfg_snapshot()
        try:
            safetybot.CFG.policy_group_arbitration_enabled = True
            safetybot.CFG.policy_shadow_mode_enabled = False
            safetybot.CFG.policy_risk_windows_enabled = True
            safetybot.CFG.friday_risk_enabled = True
            safetybot.CFG.friday_risk_groups = ("FX",)
            safetybot.CFG.friday_risk_close_only_groups = ("FX",)
            safetybot.CFG.friday_risk_borrow_block = True

            safetybot.CFG.group_price_shares = {"FX": 0.5, "METAL": 0.5}
            safetybot.CFG.group_borrow_fraction = 1.0
            safetybot.CFG.group_borrow_fraction_by_group = {"FX": 1.0, "METAL": 1.0}
            safetybot.CFG.trade_windows = {
                "FX_ALL": {"group": "FX", "anchor_tz": "Europe/Warsaw", "start_hm": (0, 0), "end_hm": (23, 59)},
                "METAL_ALL": {"group": "METAL", "anchor_tz": "Europe/Warsaw", "start_hm": (0, 0), "end_hm": (23, 59)},
            }
            safetybot.CFG.price_budget_day = 100
            safetybot.CFG.price_emergency_reserve_fraction = 0.0
            safetybot.CFG.price_soft_fraction = 1.0
            safetybot.CFG.order_budget_day = 100
            safetybot.CFG.order_emergency_reserve_fraction = 0.0
            safetybot.CFG.sys_budget_day = 100
            safetybot.CFG.sys_emergency_reserve_fraction = 0.0
            safetybot.CFG.sys_emergency_reserve = 0
            safetybot.CFG.sys_soft_fraction = 1.0

            gov = safetybot.RequestGovernor(_DbStub(price_used={"METAL": 0}))
            now_u = self._ny_to_utc(2026, 2, 27, 16, 20)
            self.assertEqual(0, int(gov._group_borrow_allowance("FX", now_dt=now_u)))
        finally:
            self._cfg_restore(prev)

    def test_effective_priority_factor_is_clamped(self) -> None:
        prev = self._cfg_snapshot()
        try:
            safetybot.CFG.group_priority_boost = {"FX": 8.0}
            safetybot.CFG.group_overlap_priority_factor = {"FX": 2.0}
            safetybot.CFG.group_priority_min_factor = 0.40
            safetybot.CFG.group_priority_max_factor = 1.80
            safetybot.CFG.policy_overlap_arbitration_enabled = True
            val = safetybot.effective_group_priority_factor(
                "FX",
                now_dt=dt.datetime(2026, 2, 23, 15, 0, tzinfo=safetybot.UTC),
            )
            self.assertGreaterEqual(val, 0.40)
            self.assertLessEqual(val, 1.80)
            self.assertAlmostEqual(1.80, val, places=4)
        finally:
            self._cfg_restore(prev)

    def test_candidate_skip_on_entry_block(self) -> None:
        risk_state = {"entry_allowed": False, "reason": "FRIDAY_SPREAD_RISK"}
        skip_hard, tag_hard = safetybot.risk_window_skip_decision(
            symbol="EURUSD",
            group="FX",
            risk_state=risk_state,
            is_open_symbol=False,
            use_risk_windows_hard=True,
            policy_risk_windows_enabled=True,
        )
        self.assertTrue(skip_hard)
        self.assertEqual("ENTRY_SKIP_RISK_WINDOW", tag_hard)

        skip_shadow, tag_shadow = safetybot.risk_window_skip_decision(
            symbol="EURUSD",
            group="FX",
            risk_state=risk_state,
            is_open_symbol=False,
            use_risk_windows_hard=False,
            policy_risk_windows_enabled=True,
        )
        self.assertFalse(skip_shadow)
        self.assertEqual("ENTRY_SKIP_RISK_WINDOW_SHADOW", tag_shadow)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
