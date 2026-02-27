from __future__ import annotations

import unittest

from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.contracts import build_codex_ticket
from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.validators import DataContractValidator


class TestTicketSchema(unittest.TestCase):
    def test_ticket_requires_manual_operator_invocation(self) -> None:
        ticket = build_codex_ticket(
            agent_name="agent_test",
            priority="HIGH",
            issue_type="TEST",
            summary="test",
            evidence_paths=["/tmp/evidence.json"],
            suggested_audit_type="TEST_AUDIT",
            suggested_scope={"a": 1},
            questions=["q1"],
            impact={"risk": "LOW"},
        )
        issues = DataContractValidator().validate_ticket(ticket)
        self.assertEqual([], issues)
        self.assertTrue(ticket.requires_operator_approval)
        self.assertEqual("MANUAL_BY_OPERATOR", ticket.codex_invocation_mode)

