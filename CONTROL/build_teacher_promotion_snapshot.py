#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, Optional


def read_json(path: Optional[Path]) -> Dict[str, Any]:
    if path is None or not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def coalesce(*values: Any, default: Any = None) -> Any:
    for value in values:
        if value not in (None, ""):
            return value
    return default


def to_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


def to_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def to_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def infer_sticky_diagnostic(learning_snapshot: Dict[str, Any], supervisor_snapshot: Dict[str, Any]) -> bool:
    explicit = coalesce(
        learning_snapshot.get("sticky_diagnostic"),
        supervisor_snapshot.get("sticky_diagnostic"),
    )
    if explicit not in (None, ""):
        return to_bool(explicit)
    reason_code = str(
        coalesce(
            learning_snapshot.get("last_reason_code"),
            supervisor_snapshot.get("last_reason_code"),
            default="",
        )
    )
    return reason_code.startswith("TIMER_FALLBACK") or reason_code.startswith("STICKY_DIAGNOSTIC")


def build_snapshot(
    learning_snapshot: Dict[str, Any],
    supervisor_snapshot: Dict[str, Any],
    teacher_snapshot: Dict[str, Any],
    cohort_audit: Dict[str, Any],
    student_gate: Dict[str, Any],
    window_metrics: Dict[str, Any],
    current_mode: str,
) -> Dict[str, Any]:
    lesson_ready = to_bool(
        coalesce(
            learning_snapshot.get("lesson_write_visible"),
            teacher_snapshot.get("lesson_ready"),
            window_metrics.get("lesson_ready"),
            default=False,
        )
    )
    knowledge_ready = to_bool(
        coalesce(
            learning_snapshot.get("knowledge_write_visible"),
            teacher_snapshot.get("knowledge_ready"),
            window_metrics.get("knowledge_ready"),
            default=False,
        )
    )
    gate_visible = to_bool(
        coalesce(
            learning_snapshot.get("gate_visible"),
            teacher_snapshot.get("gate_visible"),
            student_gate.get("gate_applied"),
            window_metrics.get("gate_visible"),
            default=False,
        )
    )
    outcome_ready = to_bool(
        coalesce(
            learning_snapshot.get("outcome_ready"),
            supervisor_snapshot.get("outcome_ready"),
            student_gate.get("outcome_ready"),
            window_metrics.get("outcome_ready"),
            default=False,
        )
    )
    teacher_score = to_float(
        coalesce(
            learning_snapshot.get("teacher_score"),
            teacher_snapshot.get("teacher_score"),
            supervisor_snapshot.get("teacher_score"),
            default=0.0,
        )
    )
    student_score = to_float(
        coalesce(
            learning_snapshot.get("student_score"),
            teacher_snapshot.get("student_score"),
            supervisor_snapshot.get("student_score"),
            default=0.0,
        )
    )

    return {
        "schema_version": "1.0",
        "symbol": str(
            coalesce(
                learning_snapshot.get("symbol"),
                supervisor_snapshot.get("symbol"),
                teacher_snapshot.get("symbol"),
                window_metrics.get("symbol"),
                default="",
            )
        ),
        "teacher_package_mode": str(
            coalesce(
                current_mode,
                teacher_snapshot.get("teacher_package_mode"),
                teacher_snapshot.get("teacher_mode"),
                window_metrics.get("teacher_package_mode"),
                default="GLOBAL_ONLY",
            )
        ),
        "teacher_score": teacher_score,
        "student_score": student_score,
        "lesson_ready": lesson_ready,
        "knowledge_ready": knowledge_ready,
        "gate_visible": gate_visible,
        "outcome_ready": outcome_ready,
        "full_lessons_window": to_int(
            coalesce(
                window_metrics.get("full_lessons_window"),
                window_metrics.get("fresh_full_lesson_count_window"),
                default=(1 if lesson_ready and knowledge_ready else 0),
            )
        ),
        "gate_visible_events_window": to_int(
            coalesce(
                window_metrics.get("gate_visible_events_window"),
                window_metrics.get("gate_visible_count_window"),
                default=(1 if gate_visible else 0),
            )
        ),
        "feature_coverage_ratio": to_float(
            coalesce(
                window_metrics.get("feature_coverage_ratio"),
                window_metrics.get("required_feature_coverage_ratio"),
                default=(1.0 if lesson_ready or knowledge_ready else 0.0),
            )
        ),
        "feature_quality_ratio": to_float(coalesce(window_metrics.get("feature_quality_ratio"), default=0.0)),
        "days_observed": to_int(coalesce(window_metrics.get("days_observed"), cohort_audit.get("days_observed"), default=0)),
        "unclassified_count": to_int(coalesce(window_metrics.get("unclassified_count"), default=0)),
        "sticky_diagnostic": infer_sticky_diagnostic(learning_snapshot, supervisor_snapshot)
        or to_bool(window_metrics.get("sticky_diagnostic")),
        "relative_quality_vs_global": to_float(coalesce(window_metrics.get("relative_quality_vs_global"), default=0.0)),
        "relative_quality_vs_family": to_float(coalesce(window_metrics.get("relative_quality_vs_family"), default=0.0)),
        "quality_drop_vs_baseline": to_float(coalesce(window_metrics.get("quality_drop_vs_baseline"), default=0.0)),
        "teacher_runtime_active": to_bool(coalesce(cohort_audit.get("teacher_runtime_active"), default=False)),
        "fresh_full_lesson": to_bool(coalesce(cohort_audit.get("fresh_full_lesson"), default=False)),
        "spread_points": to_float(
            coalesce(
                learning_snapshot.get("spread_points"),
                teacher_snapshot.get("spread_points"),
                supervisor_snapshot.get("spread_points"),
                default=0.0,
            )
        ),
        "server_ping_ms": to_float(
            coalesce(
                learning_snapshot.get("terminal_ping_ms"),
                teacher_snapshot.get("server_ping_ms"),
                supervisor_snapshot.get("terminal_ping_ms"),
                default=0.0,
            )
        ),
        "server_latency_us_avg": to_float(
            coalesce(
                learning_snapshot.get("local_latency_us_avg"),
                teacher_snapshot.get("server_latency_us_avg"),
                supervisor_snapshot.get("local_latency_us_avg"),
                default=0.0,
            )
        ),
        "last_reason_code": str(
            coalesce(
                learning_snapshot.get("last_reason_code"),
                teacher_snapshot.get("reason_code"),
                supervisor_snapshot.get("last_reason_code"),
                default="",
            )
        ),
        "source_refs": {
            "learning_snapshot_present": bool(learning_snapshot),
            "supervisor_snapshot_present": bool(supervisor_snapshot),
            "teacher_snapshot_present": bool(teacher_snapshot),
            "cohort_audit_present": bool(cohort_audit),
            "student_gate_present": bool(student_gate),
            "window_metrics_present": bool(window_metrics),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--learning-snapshot")
    parser.add_argument("--supervisor-snapshot")
    parser.add_argument("--teacher-snapshot")
    parser.add_argument("--cohort-audit")
    parser.add_argument("--student-gate")
    parser.add_argument("--window-metrics")
    parser.add_argument("--current-mode", default="")
    args = parser.parse_args()

    payload = build_snapshot(
        read_json(Path(args.learning_snapshot)) if args.learning_snapshot else {},
        read_json(Path(args.supervisor_snapshot)) if args.supervisor_snapshot else {},
        read_json(Path(args.teacher_snapshot)) if args.teacher_snapshot else {},
        read_json(Path(args.cohort_audit)) if args.cohort_audit else {},
        read_json(Path(args.student_gate)) if args.student_gate else {},
        read_json(Path(args.window_metrics)) if args.window_metrics else {},
        args.current_mode,
    )

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
