from __future__ import annotations

import unittest

from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.escalation_policy import (
    evaluate_ticket_permission,
)


class TestEscalationPolicy(unittest.TestCase):
    def test_guardian_is_allowed(self) -> None:
        decision = evaluate_ticket_permission("agent_straznik_spojnosci", "HIGH")
        self.assertTrue(decision.allowed)
        self.assertEqual(decision.reason, "ALLOWED")

    def test_non_guardian_is_denied(self) -> None:
        decision = evaluate_ticket_permission("agent_informacyjny", "HIGH")
        self.assertFalse(decision.allowed)
        self.assertEqual(decision.reason, "GUARDIAN_ONLY_ESCALATION_POLICY")

    def test_invalid_priority_for_guardian_is_denied(self) -> None:
        decision = evaluate_ticket_permission("agent_straznik_spojnosci", "P0")
        self.assertFalse(decision.allowed)
        self.assertEqual(decision.reason, "INVALID_PRIORITY_FOR_GUARDIAN")

