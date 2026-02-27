from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4


TIMESTAMP_SEMANTICS = {"UTC", "MT5_SERVER_DERIVED", "WARSAW_DERIVED"}


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


@dataclass(slots=True)
class EventRecord:
    event_type: str
    timestamp_utc: str
    timestamp_semantics: str
    source: str
    symbol_raw: str | None = None
    symbol_canonical: str | None = None
    correlation_id: str | None = None
    message_id: str | None = None
    reason_code: str | None = None
    payload: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(slots=True)
class Snapshot:
    created_at_utc: str
    name: str
    data: dict[str, Any]
    source_path: str
    read_status: str = "OK"

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(slots=True)
class CodexTicket:
    schema_version: str
    ticket_id: str
    dedupe_key: str
    created_at_utc: str
    agent_name: str
    priority: str
    issue_type: str
    summary: str
    evidence_paths: list[str]
    suggested_audit_type: str
    suggested_scope: dict[str, Any]
    questions: list[str]
    impact: dict[str, Any]
    requires_operator_approval: bool
    codex_invocation_mode: str
    notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def build_codex_ticket(
    *,
    agent_name: str,
    priority: str,
    issue_type: str,
    summary: str,
    evidence_paths: list[str],
    suggested_audit_type: str,
    suggested_scope: dict[str, Any],
    questions: list[str],
    impact: dict[str, Any],
) -> CodexTicket:
    ticket_id = str(uuid4())
    dedupe_key = f"{agent_name}:{issue_type}:{priority}:{summary[:64]}"
    return CodexTicket(
        schema_version="oanda_mt5.observers.codex_ticket.v1",
        ticket_id=ticket_id,
        dedupe_key=dedupe_key,
        created_at_utc=utc_now_iso(),
        agent_name=agent_name,
        priority=priority,
        issue_type=issue_type,
        summary=summary,
        evidence_paths=evidence_paths,
        suggested_audit_type=suggested_audit_type,
        suggested_scope=suggested_scope,
        questions=questions,
        impact=impact,
        requires_operator_approval=True,
        codex_invocation_mode="MANUAL_BY_OPERATOR",
    )

