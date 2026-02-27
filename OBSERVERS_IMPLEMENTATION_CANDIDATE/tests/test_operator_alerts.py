from __future__ import annotations

from pathlib import Path
import unittest

from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.operator_alerts import (
    alert_identity,
    extract_alert_summary,
    should_popup_alert,
)


class TestOperatorAlerts(unittest.TestCase):
    def test_popup_only_for_high(self) -> None:
        self.assertTrue(should_popup_alert({"severity": "HIGH"}))
        self.assertFalse(should_popup_alert({"severity": "MED"}))
        self.assertFalse(should_popup_alert({}))

    def test_summary_contains_key_fields(self) -> None:
        payload = {"type": "NO_LIVE_DRIFT_NOT_OK", "summary": "drift fail", "severity": "HIGH"}
        msg = extract_alert_summary(payload)
        self.assertIn("type=NO_LIVE_DRIFT_NOT_OK", msg)
        self.assertIn("summary=drift fail", msg)
        self.assertIn("severity=HIGH", msg)

    def test_identity_is_deterministic(self) -> None:
        payload = {"type": "X", "summary": "Y", "severity": "HIGH", "generated_at_utc": "t"}
        p = Path(r"C:\tmp\alert.json")
        a = alert_identity(p, payload)
        b = alert_identity(p, payload)
        self.assertEqual(a, b)


if __name__ == "__main__":
    unittest.main()
