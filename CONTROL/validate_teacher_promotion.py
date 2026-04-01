#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict


def read_json(path: Path) -> Dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(path)
    return json.loads(path.read_text(encoding="utf-8"))


def decide(curriculum: Dict[str, Any], snapshot: Dict[str, Any]) -> Dict[str, Any]:
    gate = curriculum["promotion_gate"]
    reasons = []

    if snapshot.get("full_lessons_window", 0) < gate["min_full_lessons"]:
        reasons.append("LESSONS_BELOW_MIN")
    if snapshot.get("gate_visible_events_window", 0) < gate["min_gate_visible_events"]:
        reasons.append("GATE_EVENTS_BELOW_MIN")
    if snapshot.get("feature_coverage_ratio", 0.0) < gate["min_feature_coverage_ratio"]:
        reasons.append("FEATURE_COVERAGE_BELOW_MIN")
    if snapshot.get("days_observed", 0) < gate["min_days_observed"]:
        reasons.append("DAYS_OBSERVED_BELOW_MIN")
    if gate.get("require_no_unclassified", True) and snapshot.get("unclassified_count", 0) > 0:
        reasons.append("UNCLASSIFIED_PRESENT")
    if gate.get("require_outcome_ready", True) and not snapshot.get("outcome_ready", False):
        reasons.append("OUTCOME_NOT_READY")
    if gate.get("require_no_sticky_diagnostic", True) and snapshot.get("sticky_diagnostic", False):
        reasons.append("STICKY_DIAGNOSTIC_PRESENT")
    if snapshot.get("relative_quality_vs_global", -999.0) < gate["min_relative_quality_vs_global"]:
        reasons.append("RELATIVE_QUALITY_BELOW_MIN")

    verdict = "PROMOTE_TO_PERSONAL" if not reasons else "HOLD_GLOBAL"
    if snapshot.get("quality_drop_vs_baseline", 0.0) > 0.10:
        verdict = "ROLLBACK_TO_GLOBAL"
        reasons.append("QUALITY_DROP_TOO_HIGH")

    return {
        "teacher_id": curriculum["teacher_id"],
        "symbol": curriculum["symbol"],
        "verdict": verdict,
        "reasons": reasons,
        "metrics": snapshot
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--curriculum", required=True)
    parser.add_argument("--snapshot", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    curriculum = read_json(Path(args.curriculum))
    snapshot = read_json(Path(args.snapshot))
    result = decide(curriculum, snapshot)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
