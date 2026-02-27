from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ..common.base_agent import ReadOnlyAgentBase
from .prioritization import prioritize_recommendations


class ImprovementRecommendationAgent(ReadOnlyAgentBase):
    AGENT_NAME = "agent_rekomendacyjny"

    def run_cycle(self) -> dict[str, str | None]:
        reports_root = self.out.paths.reports_root
        ops_reports = _latest_reports(reports_root / "agent_informacyjny", limit=5)
        rd_reports = _latest_reports(reports_root / "agent_rozwoju_scalpingu", limit=5)
        guardian_reports = _latest_reports(reports_root / "agent_straznik_spojnosci", limit=5)

        issues: list[dict[str, Any]] = []
        if not ops_reports:
            issues.append(
                {
                    "priority": "HIGH",
                    "problem": "Brak raportów agenta informacyjnego",
                    "evidence": "No files in outputs/reports/agent_informacyjny",
                    "impact": "Operator blind spot",
                    "risk": "HIGH",
                    "scope": "observer layer",
                    "requires_codex": False,
                    "verify_after_change": "reports count > 0",
                }
            )
        if rd_reports and guardian_reports:
            issues.append(
                {
                    "priority": "MED",
                    "problem": "Skompilować wspólne scorecardy R&D i Guardian",
                    "evidence": "Both report streams present",
                    "impact": "Better prioritization",
                    "risk": "LOW",
                    "scope": "observer analytics",
                    "requires_codex": True,
                    "verify_after_change": "recommendation hit-rate review",
                }
            )

        recommendations = prioritize_recommendations(issues)
        report = {
            "generated_at_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "input_report_counts": {
                "ops": len(ops_reports),
                "rd": len(rd_reports),
                "guardian": len(guardian_reports),
            },
            "recommendations": recommendations,
            "top_3_next_actions": recommendations[:3],
            "explicit_limits": [
                "No patching",
                "No runtime queries",
                "No live config changes",
            ],
        }
        report_path = self.emit_report("improvement_recommendations", report)
        ticket_path: str | None = None
        if recommendations and any(r.get("requires_codex") for r in recommendations):
            top = recommendations[0]
            ticket_path = str(
                self.emit_codex_ticket(
                    priority=str(top.get("priority", "MED")),
                    issue_type="IMPROVEMENT_RECOMMENDATION",
                    summary=str(top.get("problem", "Top recommendation")),
                    evidence_paths=[str(report_path)],
                    suggested_audit_type="PATCH_PLANNING_ONLY",
                    suggested_scope={"observer_recommendation": top.get("scope", "UNKNOWN")},
                    questions=["Does recommendation preserve read-only observer constitution?"],
                    impact={"risk": top.get("risk", "UNKNOWN"), "decision_loop_touched": False},
                )
            )

        return {"report_path": str(report_path), "ticket_path": ticket_path}


def _latest_reports(path: Path, limit: int) -> list[Path]:
    if not path.exists():
        return []
    files = [p for p in path.glob("*.json") if p.is_file()]
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return files[:limit]

