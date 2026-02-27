from __future__ import annotations

from dataclasses import asdict
from typing import Any

from .contracts import CodexTicket, EventRecord, TIMESTAMP_SEMANTICS


ENTRY_BLOCK_PREFIX = "ENTRY_BLOCK_"


class DataContractValidator:
    """Validates observer-side contracts only (read-only layer)."""

    def validate_event(self, event_record: EventRecord) -> list[str]:
        issues: list[str] = []
        if event_record.timestamp_semantics not in TIMESTAMP_SEMANTICS:
            issues.append("INVALID_TIMESTAMP_SEMANTICS")
        if event_record.symbol_raw and not event_record.symbol_canonical:
            issues.append("MISSING_SYMBOL_CANONICAL")
        if event_record.event_type.startswith(ENTRY_BLOCK_PREFIX) and not event_record.reason_code:
            issues.append("MISSING_REASON_CODE_FOR_ENTRY_BLOCK")
        if not event_record.source:
            issues.append("MISSING_SOURCE")
        return issues

    def validate_ticket(self, ticket: CodexTicket) -> list[str]:
        issues: list[str] = []
        raw = asdict(ticket)
        if raw.get("requires_operator_approval") is not True:
            issues.append("REQUIRES_OPERATOR_APPROVAL_MUST_BE_TRUE")
        if raw.get("codex_invocation_mode") != "MANUAL_BY_OPERATOR":
            issues.append("CODEX_INVOCATION_MODE_MUST_BE_MANUAL_BY_OPERATOR")
        if not raw.get("ticket_id"):
            issues.append("MISSING_TICKET_ID")
        if not raw.get("schema_version"):
            issues.append("MISSING_SCHEMA_VERSION")
        return issues

    def validate_report_envelope(self, payload: dict[str, Any]) -> list[str]:
        issues: list[str] = []
        if "generated_at_utc" not in payload:
            issues.append("MISSING_GENERATED_AT_UTC")
        if "agent_name" not in payload:
            issues.append("MISSING_AGENT_NAME")
        return issues

