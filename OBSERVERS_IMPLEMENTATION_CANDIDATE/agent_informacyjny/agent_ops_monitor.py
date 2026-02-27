from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from ..common.base_agent import ReadOnlyAgentBase
from ..common.escalation_policy import evaluate_ticket_permission
from .rules_alerts import evaluate_alerts, should_raise_codex_ticket


class OperationsMonitoringAgent(ReadOnlyAgentBase):
    AGENT_NAME = "agent_informacyjny"

    def run_cycle(self) -> dict[str, Any]:
        now = datetime.now(timezone.utc)
        day_start = now - timedelta(hours=24)

        current_state = self.ro_data.fetch_latest_snapshot("current_system_state")
        preflight = self.ro_data.fetch_latest_snapshot("asia_preflight_summary")
        no_live_drift = self.ro_data.fetch_latest_snapshot("no_live_drift_summary")
        no_strategy_drift = self.ro_data.fetch_latest_snapshot("no_strategy_drift_summary")
        ipc_health = self.ro_data.fetch_latest_snapshot("ipc_health_summary")

        anomalies = self.ro_data.fetch_aggregate("execution_and_ipc_anomalies", {"window": "day"})
        gate_stats = self.ro_data.fetch_aggregate("gate_block_stats", {"window": "day"})
        pnl_net_daily = self.ro_data.fetch_aggregate("pnl_net_daily", {})
        pnl_net_session = self.ro_data.fetch_aggregate("pnl_net_session", {"session": "ASIA"})

        recent_events = list(
            self.ro_data.fetch_events(
                start_utc=day_start.isoformat().replace("+00:00", "Z"),
                end_utc=now.isoformat().replace("+00:00", "Z"),
                filters={"critical": True},
            )
        )[-50:]
        contract_issues: list[str] = []
        for event in recent_events:
            contract_issues.extend(self.validator.validate_event(event))

        report = {
            "generated_at_utc": now.isoformat().replace("+00:00", "Z"),
            "live_canary": (current_state.data.get("live_canary") if current_state else {}),
            "module_states": (current_state.data.get("module_states") if current_state else {}),
            "preflight_status": (preflight.to_dict() if preflight else {}),
            "drift_checks": {
                "no_live_drift": no_live_drift.to_dict() if no_live_drift else {},
                "no_strategy_drift": no_strategy_drift.to_dict() if no_strategy_drift else {},
                "status": _merge_drift_status(no_live_drift, no_strategy_drift),
            },
            "net_results": {"daily": pnl_net_daily, "session_asia": pnl_net_session},
            "gate_stats": gate_stats,
            "anomalies": anomalies,
            "ipc_health": ipc_health.to_dict() if ipc_health else {},
            "recent_critical_events": [e.to_dict() for e in recent_events],
            "data_contract_issues_detected": sorted(set(contract_issues)),
            "codex_escalation_policy": {
                "requested": False,
                "allowed": False,
                "reason": "NOT_REQUESTED",
            },
        }

        alerts = evaluate_alerts(report)
        ticket_policy_block = None
        ticket_path: str | None = None

        if should_raise_codex_ticket(report, alerts):
            permission = evaluate_ticket_permission(self.AGENT_NAME, "HIGH")
            report["codex_escalation_policy"] = {
                "requested": True,
                "allowed": permission.allowed,
                "reason": permission.reason,
            }
            if not permission.allowed:
                ticket_policy_block = {
                    "type": "ESCALATION_POLICY_BLOCKED",
                    "severity": "MED",
                    "agent_name": self.AGENT_NAME,
                    "requested_priority": "HIGH",
                    "reason": permission.reason,
                    "message": "Eskalacja do Codex zablokowana polityka guardian-only.",
                }

        report_path = self.emit_report("ops_monitoring_snapshot", report)
        alert_payloads = [*alerts]
        if ticket_policy_block is not None:
            alert_payloads.append(ticket_policy_block)
        alert_paths = [str(self.emit_alert(a["severity"], a)) for a in alert_payloads]

        return {
            "report_path": str(report_path),
            "alert_count": len(alert_payloads),
            "ticket_path": ticket_path,
        }


def _merge_drift_status(no_live_drift: Any, no_strategy_drift: Any) -> str:
    statuses = []
    for snap in (no_live_drift, no_strategy_drift):
        if snap is None:
            statuses.append("MISSING")
            continue
        data = snap.data if hasattr(snap, "data") else {}
        statuses.append(str(data.get("status") or "UNKNOWN").upper())
    if "FAIL" in statuses or "MISSING" in statuses:
        return "FAIL"
    if "OK" in statuses:
        return "OK"
    return "UNKNOWN"
