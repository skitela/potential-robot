from __future__ import annotations

from dataclasses import dataclass


GUARDIAN_AGENT_NAME = "agent_straznik_spojnosci"
ALLOWED_GUARDIAN_PRIORITIES: tuple[str, ...] = ("LOW", "MED", "HIGH", "CRITICAL")


@dataclass(frozen=True)
class TicketPermission:
    allowed: bool
    reason: str


def evaluate_ticket_permission(agent_name: str, priority: str) -> TicketPermission:
    """Guardian-only Codex escalation policy for observer layer."""
    norm_agent = (agent_name or "").strip().lower()
    norm_priority = (priority or "").strip().upper()
    if norm_agent != GUARDIAN_AGENT_NAME:
        return TicketPermission(
            allowed=False,
            reason="GUARDIAN_ONLY_ESCALATION_POLICY",
        )
    if norm_priority not in ALLOWED_GUARDIAN_PRIORITIES:
        return TicketPermission(
            allowed=False,
            reason="INVALID_PRIORITY_FOR_GUARDIAN",
        )
    return TicketPermission(allowed=True, reason="ALLOWED")

