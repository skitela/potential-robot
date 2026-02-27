from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any

from .contracts import build_codex_ticket
from .escalation_policy import evaluate_ticket_permission
from .outputs import ObserverOutputWriter
from .readonly_adapter import ReadOnlyDataAdapter
from .validators import DataContractValidator


class ReadOnlyAgentBase(ABC):
    AGENT_NAME = "agent_base"

    def __init__(
        self,
        ro_data: ReadOnlyDataAdapter,
        out: ObserverOutputWriter,
        validator: DataContractValidator,
    ) -> None:
        self.ro_data = ro_data
        self.out = out
        self.validator = validator

    @abstractmethod
    def run_cycle(self) -> dict[str, Any]:
        raise NotImplementedError

    def emit_report(self, report_name: str, content: dict[str, Any]) -> Path:
        payload = {"agent_name": self.AGENT_NAME, **content}
        return self.out.write_report(self.AGENT_NAME, report_name, payload)

    def emit_alert(self, severity: str, alert_payload: dict[str, Any]) -> Path:
        return self.out.write_alert(self.AGENT_NAME, severity, alert_payload)

    def emit_codex_ticket(
        self,
        *,
        priority: str,
        issue_type: str,
        summary: str,
        evidence_paths: list[str],
        suggested_audit_type: str,
        suggested_scope: dict[str, Any],
        questions: list[str],
        impact: dict[str, Any],
    ) -> Path:
        permission = evaluate_ticket_permission(self.AGENT_NAME, priority)
        if not permission.allowed:
            raise PermissionError(
                f"Escalation denied for agent={self.AGENT_NAME}: {permission.reason}"
            )
        ticket = build_codex_ticket(
            agent_name=self.AGENT_NAME,
            priority=priority,
            issue_type=issue_type,
            summary=summary,
            evidence_paths=evidence_paths,
            suggested_audit_type=suggested_audit_type,
            suggested_scope=suggested_scope,
            questions=questions,
            impact=impact,
        )
        issues = self.validator.validate_ticket(ticket)
        if issues:
            raise ValueError(f"Ticket validation failed: {issues}")
        return self.out.write_codex_ticket(ticket)
