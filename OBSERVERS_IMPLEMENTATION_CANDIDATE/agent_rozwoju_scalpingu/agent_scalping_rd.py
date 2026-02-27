from __future__ import annotations

from datetime import datetime, timedelta, timezone

from ..common.base_agent import ReadOnlyAgentBase
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
        }
        report_path = self.emit_report("scalping_rd_daily", report)

        ticket_path: str | None = None
        if hypotheses:
            ticket_path = str(
                self.emit_codex_ticket(
                    priority="MED",
                    issue_type="RND_FOCUSED_ANALYSIS_OR_PATCH_PLANNING",
                    summary="R&D observer found hypotheses that require audit-level validation.",
                    evidence_paths=[str(report_path)],
                    suggested_audit_type="RND_FOCUSED_ANALYSIS_OR_PATCH_PLANNING",
                    suggested_scope={"window_hours": 24, "layers": ["execution", "cost", "contracts"]},
                    questions=["Are hypotheses supported by calibrated telemetry?"],
                    impact={"risk": "LOW_TO_MEDIUM", "decision_loop_touched": False},
                )
            )

        return {"report_path": str(report_path), "ticket_path": ticket_path}

