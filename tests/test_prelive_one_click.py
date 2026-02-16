import unittest

from TOOLS import prelive_one_click


class TestPreliveOneClickVerdict(unittest.TestCase):
    def test_go_offline_pending_online_when_online_is_deferred(self) -> None:
        v = prelive_one_click.evaluate_overall_status(
            learner_rc=0,
            smoke_compile_rc=0,
            gate_rc=0,
            prelive_go=True,
            gate_failed=[],
            prelive_failed_checks=[],
            online_result="DO_WERYFIKACJI_ONLINE",
            symbols_result="DO_WERYFIKACJI_ONLINE",
        )
        self.assertEqual(str(v.get("status")), "GO_OFFLINE_PENDING_ONLINE")
        self.assertTrue(bool(v.get("offline_ready")))
        self.assertFalse(bool(v.get("go_live_ready")))

    def test_no_go_when_offline_gate_or_prelive_fails(self) -> None:
        v = prelive_one_click.evaluate_overall_status(
            learner_rc=0,
            smoke_compile_rc=0,
            gate_rc=1,
            prelive_go=False,
            gate_failed=["diag_latest", "cleanliness"],
            prelive_failed_checks=["LEARNER_FRESH"],
            online_result="PASS",
            symbols_result="PASS",
        )
        self.assertEqual(str(v.get("status")), "NO_GO")
        blockers = set(v.get("blockers") or [])
        self.assertIn("gate:diag_latest", blockers)
        self.assertIn("gate:cleanliness", blockers)
        self.assertIn("prelive:LEARNER_FRESH", blockers)
        self.assertFalse(bool(v.get("offline_ready")))

    def test_no_go_when_symbols_missing_targets(self) -> None:
        v = prelive_one_click.evaluate_overall_status(
            learner_rc=0,
            smoke_compile_rc=0,
            gate_rc=0,
            prelive_go=True,
            gate_failed=[],
            prelive_failed_checks=[],
            online_result="PASS",
            symbols_result="WARN_MISSING_TARGETS",
        )
        self.assertEqual(str(v.get("status")), "NO_GO")
        self.assertIn("online:symbols_missing_targets", set(v.get("blockers") or []))
        self.assertFalse(bool(v.get("go_live_ready")))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
