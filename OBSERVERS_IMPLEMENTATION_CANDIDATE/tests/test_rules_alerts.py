from __future__ import annotations

import unittest

from OBSERVERS_IMPLEMENTATION_CANDIDATE.agent_informacyjny.rules_alerts import evaluate_alerts


class TestRulesAlerts(unittest.TestCase):
    def test_unknown_retcode_value_does_not_crash(self) -> None:
        report = {
            "drift_checks": {"status": "OK"},
            "anomalies": {"retcode_10017": "UNKNOWN"},
        }
        alerts = evaluate_alerts(report)
        self.assertEqual([], alerts)

    def test_retcode_10017_produces_med_alert(self) -> None:
        report = {
            "drift_checks": {"status": "OK"},
            "anomalies": {"retcode_10017": 3},
        }
        alerts = evaluate_alerts(report)
        self.assertTrue(any(a.get("type") == "TRADE_DISABLED_RETURNCODE_SEEN" for a in alerts))


if __name__ == "__main__":
    unittest.main()
