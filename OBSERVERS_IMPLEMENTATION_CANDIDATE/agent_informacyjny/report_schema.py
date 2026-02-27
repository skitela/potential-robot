from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(slots=True)
class OpsMonitoringReport:
    generated_at_utc: str
    live_canary: dict[str, Any]
    module_states: dict[str, Any]
    preflight_status: dict[str, Any]
    drift_checks: dict[str, Any]
    net_results: dict[str, Any]
    gate_stats: dict[str, Any]
    anomalies: dict[str, Any]
    ipc_health: dict[str, Any]
    recent_critical_events: list[dict[str, Any]]
    data_contract_issues_detected: list[str]

