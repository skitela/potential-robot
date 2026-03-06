import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

from capital_protection_black_swan_guard_v2 import (  # noqa: E402
    CapitalProtectionBlackSwanGuardV2,
    GuardConfig,
    GuardState,
    MarketSnapshot,
)


class TestCapitalProtectionBlackSwanGuardV2(unittest.TestCase):
    def test_crash_hard_caps_trigger_halt(self):
        guard = CapitalProtectionBlackSwanGuardV2(
            GuardConfig(
                warmup_ticks=1,
                hard_max_spread_points=20.0,
                hard_max_bridge_wait_ms=200.0,
                hard_max_heartbeat_age_ms=1500.0,
            )
        )
        # warm baseline
        warm = MarketSnapshot(
            ts_monotonic=1.0,
            symbol="EURUSD",
            volatility_score=1.0,
            spread_points=5.0,
            slippage_points=1.0,
            liquidity_score=0.9,
            tick_rate_per_sec=10.0,
            tick_gap_ms=100.0,
            price_jump_points=2.0,
            bridge_wait_ms=30.0,
            heartbeat_age_ms=200.0,
            reject_count_recent=0,
        )
        guard.evaluate(warm)
        panic = MarketSnapshot(
            ts_monotonic=2.0,
            symbol="EURUSD",
            volatility_score=2.0,
            spread_points=25.0,
            slippage_points=5.0,
            liquidity_score=0.1,
            tick_rate_per_sec=1.0,
            tick_gap_ms=3000.0,
            price_jump_points=20.0,
            bridge_wait_ms=500.0,
            heartbeat_age_ms=5000.0,
            reject_count_recent=5,
            stale_tick_flag=True,
            burst_flag=True,
            ask_lt_bid_flag=False,
        )
        decision = guard.evaluate(panic)
        self.assertEqual(decision.state, GuardState.HALT)
        self.assertIn("hard_cap:spread", decision.reasons)

    def test_recovery_requires_cooldown_and_stable_ticks(self):
        guard = CapitalProtectionBlackSwanGuardV2(
            GuardConfig(
                warmup_ticks=1,
                required_stable_ticks_for_recovery=2,
                halt_cooldown_sec=2,
                close_only_cooldown_sec=2,
                defensive_cooldown_sec=1,
                caution_cooldown_sec=1,
                hard_max_spread_points=20.0,
            )
        )
        base = MarketSnapshot(
            ts_monotonic=1.0,
            symbol="EURUSD",
            volatility_score=1.0,
            spread_points=5.0,
            slippage_points=1.0,
            liquidity_score=0.9,
            tick_rate_per_sec=10.0,
            tick_gap_ms=100.0,
            price_jump_points=2.0,
            bridge_wait_ms=30.0,
            heartbeat_age_ms=200.0,
            reject_count_recent=0,
        )
        guard.evaluate(base)
        crash = MarketSnapshot(
            ts_monotonic=2.0,
            symbol="EURUSD",
            volatility_score=1.0,
            spread_points=30.0,
            slippage_points=1.0,
            liquidity_score=0.9,
            tick_rate_per_sec=10.0,
            tick_gap_ms=100.0,
            price_jump_points=2.0,
            bridge_wait_ms=30.0,
            heartbeat_age_ms=200.0,
            reject_count_recent=0,
        )
        d1 = guard.evaluate(crash)
        self.assertEqual(d1.state, GuardState.HALT)

        # before cooldown expiry should still be HALT
        calm_early = MarketSnapshot(**{**base.__dict__, "ts_monotonic": 3.0})
        d2 = guard.evaluate(calm_early)
        self.assertEqual(d2.state, GuardState.HALT)

        # after cooldown + stable ticks should step down gradually
        calm_late_1 = MarketSnapshot(**{**base.__dict__, "ts_monotonic": 5.5})
        calm_late_2 = MarketSnapshot(**{**base.__dict__, "ts_monotonic": 6.5})
        d3 = guard.evaluate(calm_late_1)
        d4 = guard.evaluate(calm_late_2)
        self.assertIn(d3.state, {GuardState.HALT, GuardState.CLOSE_ONLY})
        self.assertIn(d4.state, {GuardState.CLOSE_ONLY, GuardState.DEFENSIVE})

    def test_warmup_state_is_guarded_not_normal(self):
        guard = CapitalProtectionBlackSwanGuardV2(GuardConfig(warmup_ticks=10))
        snap = MarketSnapshot(
            ts_monotonic=1.0,
            symbol="EURUSD",
            volatility_score=1.0,
            spread_points=4.0,
            slippage_points=0.5,
            liquidity_score=0.9,
            tick_rate_per_sec=10.0,
            tick_gap_ms=120.0,
            price_jump_points=2.0,
            bridge_wait_ms=20.0,
            heartbeat_age_ms=100.0,
            reject_count_recent=0,
        )
        decision = guard.evaluate(snap)
        self.assertIn(decision.state, {GuardState.CAUTION, GuardState.CLOSE_ONLY})

    def test_liquidity_floor_requires_streak(self):
        guard = CapitalProtectionBlackSwanGuardV2(
            GuardConfig(
                warmup_ticks=1,
                liquidity_floor_score=0.20,
                liquidity_floor_streak_required=3,
            )
        )
        warm = MarketSnapshot(
            ts_monotonic=1.0,
            symbol="EURUSD",
            volatility_score=1.0,
            spread_points=4.0,
            slippage_points=0.5,
            liquidity_score=0.9,
            tick_rate_per_sec=10.0,
            tick_gap_ms=120.0,
            price_jump_points=2.0,
            bridge_wait_ms=20.0,
            heartbeat_age_ms=100.0,
            reject_count_recent=0,
        )
        guard.evaluate(warm)

        low_liq = MarketSnapshot(**{**warm.__dict__, "ts_monotonic": 2.0, "liquidity_score": 0.19})
        d1 = guard.evaluate(low_liq)
        d2 = guard.evaluate(MarketSnapshot(**{**low_liq.__dict__, "ts_monotonic": 3.0}))
        d3 = guard.evaluate(MarketSnapshot(**{**low_liq.__dict__, "ts_monotonic": 4.0}))

        self.assertNotIn("crash:liquidity_floor", d1.reasons)
        self.assertNotIn("crash:liquidity_floor", d2.reasons)
        self.assertIn("crash:liquidity_floor", d3.reasons)

    def test_bridge_freeze_requires_streak(self):
        guard = CapitalProtectionBlackSwanGuardV2(
            GuardConfig(
                warmup_ticks=1,
                crash_bridge_mult=2.0,
                crash_bridge_streak_required=3,
                hard_max_bridge_wait_ms=10_000.0,
            )
        )
        warm = MarketSnapshot(
            ts_monotonic=1.0,
            symbol="EURUSD",
            volatility_score=1.0,
            spread_points=4.0,
            slippage_points=0.5,
            liquidity_score=0.9,
            tick_rate_per_sec=10.0,
            tick_gap_ms=120.0,
            price_jump_points=2.0,
            bridge_wait_ms=20.0,
            heartbeat_age_ms=100.0,
            reject_count_recent=0,
        )
        guard.evaluate(warm)

        b1 = guard.evaluate(MarketSnapshot(**{**warm.__dict__, "ts_monotonic": 2.0, "bridge_wait_ms": 60.0}))
        b2 = guard.evaluate(MarketSnapshot(**{**warm.__dict__, "ts_monotonic": 3.0, "bridge_wait_ms": 65.0}))
        b3 = guard.evaluate(MarketSnapshot(**{**warm.__dict__, "ts_monotonic": 4.0, "bridge_wait_ms": 70.0}))

        self.assertNotIn("crash:bridge_freeze", b1.reasons)
        self.assertNotIn("crash:bridge_freeze", b2.reasons)
        self.assertIn("crash:bridge_freeze", b3.reasons)

    def test_soft_crash_rules_are_suppressed_during_warmup(self):
        guard = CapitalProtectionBlackSwanGuardV2(
            GuardConfig(
                warmup_ticks=10,
                crash_move_mult=2.0,
                hard_max_spread_points=1000.0,
                hard_max_tick_gap_ms=100000.0,
            )
        )
        base = MarketSnapshot(
            ts_monotonic=1.0,
            symbol="EURUSD",
            volatility_score=1.0,
            spread_points=4.0,
            slippage_points=0.5,
            liquidity_score=0.9,
            tick_rate_per_sec=10.0,
            tick_gap_ms=120.0,
            price_jump_points=2.0,
            bridge_wait_ms=20.0,
            heartbeat_age_ms=100.0,
            reject_count_recent=0,
        )
        guard.evaluate(base)
        spike = guard.evaluate(MarketSnapshot(**{**base.__dict__, "ts_monotonic": 2.0, "price_jump_points": 10.0}))
        self.assertFalse(spike.warm)
        self.assertNotIn("crash:flash_move", spike.reasons)
        self.assertNotEqual(spike.state, GuardState.HALT)

    def test_warmup_continues_while_halt_is_active(self):
        guard = CapitalProtectionBlackSwanGuardV2(
            GuardConfig(
                warmup_ticks=4,
                hard_max_spread_points=10.0,
                hard_max_tick_gap_ms=100000.0,
                hard_max_bridge_wait_ms=100000.0,
                hard_max_heartbeat_age_ms=100000.0,
            )
        )
        base = MarketSnapshot(
            ts_monotonic=1.0,
            symbol="EURUSD",
            volatility_score=1.0,
            spread_points=4.0,
            slippage_points=0.5,
            liquidity_score=0.9,
            tick_rate_per_sec=10.0,
            tick_gap_ms=120.0,
            price_jump_points=2.0,
            bridge_wait_ms=20.0,
            heartbeat_age_ms=100.0,
            reject_count_recent=0,
        )
        guard.evaluate(base)
        # hard cap spread -> HALT and frozen baseline
        guard.evaluate(MarketSnapshot(**{**base.__dict__, "ts_monotonic": 2.0, "spread_points": 20.0}))
        d3 = guard.evaluate(MarketSnapshot(**{**base.__dict__, "ts_monotonic": 3.0}))
        d4 = guard.evaluate(MarketSnapshot(**{**base.__dict__, "ts_monotonic": 4.0}))
        d5 = guard.evaluate(MarketSnapshot(**{**base.__dict__, "ts_monotonic": 5.0}))
        self.assertFalse(d3.warm)
        self.assertTrue(d4.warm or d5.warm)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
