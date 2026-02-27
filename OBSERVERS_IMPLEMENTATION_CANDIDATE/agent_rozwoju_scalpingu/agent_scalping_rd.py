from __future__ import annotations

from datetime import datetime, timedelta, timezone

from ..common.base_agent import ReadOnlyAgentBase
from ..common.escalation_policy import evaluate_ticket_permission
from .diagnosis_rules import generate_rd_hypotheses, separate_signal_vs_execution_vs_regime_effects
from .metrics_engine import calc_block_reason_distribution, calc_execution_quality, calc_pnl_net_by_symbol


class ScalpingRDAgent(ReadOnlyAgentBase):
    AGENT_NAME = "agent_rozwoju_scalpingu"

    def run_cycle(self) -> dict[str, str | None]:
        now = datetime.now(timezone.utc)
        start = now - timedelta(hours=24)
        events = list(
            self.ro_data.fetch_events(
                start_utc=start.isoformat().replace("+00:00", "Z"),
                end_utc=now.isoformat().replace("+00:00", "Z"),
                filters={"class": "trade_execution_cost"},
            )
        )

        metrics = {
            "pnl_net_by_symbol": calc_pnl_net_by_symbol(events),
            "execution_quality_by_symbol": calc_execution_quality(events),
            "block_reason_distribution": calc_block_reason_distribution(events),
        }
        diagnosis = separate_signal_vs_execution_vs_regime_effects(metrics)
        hypotheses = generate_rd_hypotheses(metrics, diagnosis)
        report = {
            "generated_at_utc": now.isoformat().replace("+00:00", "Z"),
            "analysis_window_utc": {
                "start": start.isoformat().replace("+00:00", "Z"),
                "end": now.isoformat().replace("+00:00", "Z"),
            },
            "event_count": len(events),
            "metrics": metrics,
            "diagnosis": diagnosis,
            "hypotheses": hypotheses,
            "notes": [
                "Read-only analytics only.",
                "No decision-loop changes.",
                "No live configuration changes.",
            ],
            "codex_escalation_policy": {
                "requested": False,
                "allowed": False,
                "reason": "NOT_REQUESTED",
            },
        }

        ticket_path: str | None = None
        policy_alert = None
        if hypotheses:
            permission = evaluate_ticket_permission(self.AGENT_NAME, "MED")
            report["codex_escalation_policy"] = {
                "requested": True,
                "allowed": permission.allowed,
                "reason": permission.reason,
            }
            if not permission.allowed:
                policy_alert = {
                    "type": "ESCALATION_POLICY_BLOCKED",
                    "severity": "LOW",
                    "agent_name": self.AGENT_NAME,
                    "requested_priority": "MED",
                    "reason": permission.reason,
                    "message": "Eskalacja R&D jest tylko rekomendacja; ticket do Codex tworzy Guardian.",
                }

        report_path = self.emit_report("scalping_rd_daily", report)
        if policy_alert is not None:
            self.emit_alert("LOW", policy_alert)

        return {"report_path": str(report_path), "ticket_path": ticket_path}
