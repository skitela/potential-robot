import unittest

from BIN.canary_rollout_guard import CanaryPolicy, CanaryRolloutGuard


class TestCanaryRolloutGuard(unittest.TestCase):
    def test_canary_promotes_after_stable_window(self) -> None:
        now = 1_700_000_000
        guard = CanaryRolloutGuard(
            CanaryPolicy(
                lookback_sec=3600,
                promote_min_deals=4,
                promote_min_net_pnl=0.0,
                canary_max_symbols=1,
            )
        )
        deals = [
            (now - 10, "EURUSD", 1.0),
            (now - 20, "EURUSD", -0.1),
            (now - 30, "GBPUSD", 0.6),
            (now - 40, "EURUSD", 0.2),
        ]
        sig = guard.evaluate(
            deals_desc=deals,
            now_ts=now,
            promoted_state=False,
            incident_error_count=0,
        )
        self.assertTrue(sig.promoted_now)
        self.assertTrue(sig.promoted)
        self.assertFalse(sig.canary_active)

    def test_canary_pause_on_loss_streak(self) -> None:
        now = 1_700_000_000
        guard = CanaryRolloutGuard(CanaryPolicy(lookback_sec=3600, pause_loss_streak=3, canary_max_symbols=1))
        deals = [
            (now - 10, "EURUSD", -1.0),
            (now - 20, "EURUSD", -0.5),
            (now - 30, "GBPUSD", -0.2),
            (now - 40, "EURUSD", 0.1),
        ]
        sig = guard.evaluate(
            deals_desc=deals,
            now_ts=now,
            promoted_state=False,
            incident_error_count=0,
        )
        self.assertTrue(sig.pause)
        self.assertEqual(sig.allowed_symbols, 0)
        self.assertIn("LOSS_STREAK", sig.reasons)

    def test_canary_pause_on_incident_errors(self) -> None:
        now = 1_700_000_000
        guard = CanaryRolloutGuard(CanaryPolicy(max_error_incidents=2))
        sig = guard.evaluate(
            deals_desc=[],
            now_ts=now,
            promoted_state=False,
            incident_error_count=2,
        )
        self.assertTrue(sig.pause)
        self.assertIn("INCIDENTS", sig.reasons)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
