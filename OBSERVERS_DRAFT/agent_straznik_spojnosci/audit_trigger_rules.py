from __future__ import annotations

from typing import Any


def should_raise_audit_ticket(risk_summary: dict[str, Any]) -> bool:
    high = int(risk_summary.get("high_findings", 0) or 0)
    return high > 0


def summarize_risks(findings: dict[str, Any]) -> dict[str, Any]:
    high_findings = 0
    medium_findings = 0
    if findings.get("contracts", {}).get("issues"):
        high_findings += 1
    if (findings.get("artifact_freshness", {}) or {}).get("stale_count", 0) > 0:
        medium_findings += 1
    return {
        "high_findings": high_findings,
        "medium_findings": medium_findings,
        "status": "ALERT" if high_findings else ("WARN" if medium_findings else "OK"),
    }

