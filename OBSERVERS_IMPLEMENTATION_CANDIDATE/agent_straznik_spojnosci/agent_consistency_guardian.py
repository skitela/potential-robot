from __future__ import annotations

from datetime import datetime, timedelta, timezone

from ..common.base_agent import ReadOnlyAgentBase
from .artifact_freshness_checks import check_artifact_freshness
from .audit_trigger_rules import should_raise_audit_ticket, summarize_risks
from .contract_checks import check_data_contracts


class ConsistencyGuardianAgent(ReadOnlyAgentBase):
    AGENT_NAME = "agent_straznik_spojnosci"

    def run_cycle(self) -> dict[str, str | None]:
        now = datetime.now(timezone.utc)
        start = now - timedelta(hours=6)
        events = list(
            self.ro_data.fetch_events(
                start_utc=start.isoformat().replace("+00:00", "Z"),
                end_utc=now.isoformat().replace("+00:00", "Z"),
                filters={"contract_critical": True},
            )
        )[-500:]

        contract_findings = check_data_contracts(events, self.validator)
        artifacts = [
            self.out.paths.workspace_root / "EVIDENCE" / "no_live_drift_check.json",
            self.out.paths.workspace_root / "EVIDENCE" / "asia_symbol_preflight.json",
            self.out.paths.workspace_root / "RUN" / "live_trade_monitor_status.json",
        ]
        freshness_findings = check_artifact_freshness(artifacts, stale_after_sec=1200)

        all_findings = {
            "contracts": contract_findings,
            "artifact_freshness": freshness_findings,
            "config_live_scope": {"status": "NOT_CHECKED"},
            "reason_codes": {"status": "NOT_CHECKED"},
            "report_vs_repo": {"status": "NOT_CHECKED"},
            "tech_debt_candidates": {"status": "NOT_CHECKED"},
        }
        risk_summary = summarize_risks(all_findings)
        report = {
            "generated_at_utc": now.isoformat().replace("+00:00", "Z"),
            "findings": all_findings,
            "risk_summary": risk_summary,
            "guardrails": [
                "No runtime queries",
                "No patches",
                "No config mutations",
                "Identification and recommendation only",
            ],
        }
        report_path = self.emit_report("consistency_guardian_scan", report)
        alert_paths: list[str] = []
        if risk_summary["status"] in {"ALERT", "WARN"}:
            alert_paths.append(
                str(
                    self.emit_alert(
                        "HIGH" if risk_summary["status"] == "ALERT" else "MED",
                        {"type": "CONSISTENCY_GUARDIAN_RISK", "risk_summary": risk_summary},
                    )
                )
            )

        ticket_path: str | None = None
        if should_raise_audit_ticket(risk_summary):
            ticket_path = str(
                self.emit_codex_ticket(
                    priority="HIGH",
                    issue_type="POST_CHANGE_AUDIT_TRIGGER",
                    summary="Consistency guardian detected high-risk contract drift.",
                    evidence_paths=[str(report_path), *alert_paths],
                    suggested_audit_type="POST-CHANGE_HARD_AUDIT_SECOND_PASS",
                    suggested_scope={"layer": "observer+contracts", "window_hours": 6},
                    questions=["Are contract violations caused by schema drift or stale artifacts?"],
                    impact={"risk": "HIGH", "decision_loop_touched": False},
                )
            )

        return {"report_path": str(report_path), "ticket_path": ticket_path}

