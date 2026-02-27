from __future__ import annotations

from pathlib import Path
import unittest

from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.base_agent import ReadOnlyAgentBase


class _DummyRO:
    pass


class _DummyOut:
    def write_report(self, *_args, **_kwargs) -> Path:
        return Path("dummy_report.json")

    def write_alert(self, *_args, **_kwargs) -> Path:
        return Path("dummy_alert.json")

    def write_codex_ticket(self, *_args, **_kwargs) -> Path:
        return Path("dummy_ticket.json")


class _DummyValidator:
    def validate_ticket(self, _ticket) -> list[str]:
        return []


class _DummyAgent(ReadOnlyAgentBase):
    AGENT_NAME = "agent_informacyjny"

    def run_cycle(self) -> dict:
        return {}


class _GuardianDummyAgent(ReadOnlyAgentBase):
    AGENT_NAME = "agent_straznik_spojnosci"

    def run_cycle(self) -> dict:
        return {}


class TestGuardianTicketGate(unittest.TestCase):
    def test_non_guardian_cannot_emit_ticket(self) -> None:
        agent = _DummyAgent(_DummyRO(), _DummyOut(), _DummyValidator())
        with self.assertRaises(PermissionError):
            agent.emit_codex_ticket(
                priority="HIGH",
                issue_type="TEST",
                summary="x",
                evidence_paths=[],
                suggested_audit_type="TEST",
                suggested_scope={},
                questions=[],
                impact={},
            )

    def test_guardian_can_emit_ticket(self) -> None:
        agent = _GuardianDummyAgent(_DummyRO(), _DummyOut(), _DummyValidator())
        out = agent.emit_codex_ticket(
            priority="HIGH",
            issue_type="TEST",
            summary="x",
            evidence_paths=[],
            suggested_audit_type="TEST",
            suggested_scope={},
            questions=[],
            impact={},
        )
        self.assertEqual(out, Path("dummy_ticket.json"))

