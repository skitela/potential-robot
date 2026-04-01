#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional


def read_json(path: Optional[Path]) -> Dict[str, Any]:
    if path is None:
        return {}
    if not path.exists():
        raise FileNotFoundError(path)
    return json.loads(path.read_text(encoding="utf-8"))


def parse_timestamp(value: Any) -> Optional[datetime]:
    if value in (None, ""):
        return None
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(float(value), tz=timezone.utc)
    text = str(value).strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        try:
            parsed = datetime.fromtimestamp(float(text), tz=timezone.utc)
        except ValueError:
            return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def resolve_effective_gate(curriculum: Dict[str, Any], policy: Dict[str, Any]) -> Dict[str, Any]:
    gate = dict(curriculum.get("promotion_gate", {}))
    threshold_overrides = policy.get("threshold_overrides", {}) if isinstance(policy.get("threshold_overrides"), dict) else {}
    scope = str(curriculum.get("scope", "GLOBAL")).upper()
    default_overrides = threshold_overrides.get("default", {}) if isinstance(threshold_overrides.get("default"), dict) else {}
    scope_overrides = threshold_overrides.get(scope, {}) if isinstance(threshold_overrides.get(scope), dict) else {}
    gate.update(default_overrides)
    gate.update(scope_overrides)
    return gate


def recent_approve_streak(history: Dict[str, Any]) -> int:
    entries = history.get("recent_verdicts", [])
    if not isinstance(entries, list):
        return 0
    streak = 0
    for item in reversed(entries):
        verdict = str(item.get("verdict") or "") if isinstance(item, dict) else str(item or "")
        if verdict == "PROMOTE_TO_PERSONAL":
            streak += 1
            continue
        break
    return streak


def cooldown_active(history: Dict[str, Any], field_name: str, hours: float) -> bool:
    if hours <= 0:
        return False
    timestamp = parse_timestamp(history.get(field_name))
    if timestamp is None:
        return False
    age_seconds = (datetime.now(timezone.utc) - timestamp).total_seconds()
    return age_seconds < hours * 3600.0


def evaluate_gate(snapshot: Dict[str, Any], gate: Dict[str, Any]) -> List[str]:
    reasons: List[str] = []
    if snapshot.get("full_lessons_window", 0) < gate.get("min_full_lessons", 0):
        reasons.append("LESSONS_BELOW_MIN")
    if snapshot.get("gate_visible_events_window", 0) < gate.get("min_gate_visible_events", 0):
        reasons.append("GATE_EVENTS_BELOW_MIN")
    if snapshot.get("feature_coverage_ratio", 0.0) < gate.get("min_feature_coverage_ratio", 0.0):
        reasons.append("FEATURE_COVERAGE_BELOW_MIN")
    if "min_feature_quality_ratio" in gate and snapshot.get("feature_quality_ratio", 0.0) < gate.get("min_feature_quality_ratio", 0.0):
        reasons.append("FEATURE_QUALITY_BELOW_MIN")
    if snapshot.get("days_observed", 0) < gate.get("min_days_observed", 0):
        reasons.append("DAYS_OBSERVED_BELOW_MIN")
    if gate.get("require_no_unclassified", True) and snapshot.get("unclassified_count", 0) > 0:
        reasons.append("UNCLASSIFIED_PRESENT")
    if gate.get("require_outcome_ready", True) and not snapshot.get("outcome_ready", False):
        reasons.append("OUTCOME_NOT_READY")
    if gate.get("require_no_sticky_diagnostic", True) and snapshot.get("sticky_diagnostic", False):
        reasons.append("STICKY_DIAGNOSTIC_PRESENT")
    if snapshot.get("relative_quality_vs_global", -999.0) < gate.get("min_relative_quality_vs_global", -999.0):
        reasons.append("RELATIVE_QUALITY_BELOW_MIN")
    if "min_relative_quality_vs_family" in gate and snapshot.get("relative_quality_vs_family", -999.0) < gate.get("min_relative_quality_vs_family", -999.0):
        reasons.append("FAMILY_RELATIVE_QUALITY_BELOW_MIN")
    return reasons


def evaluate_rollback(snapshot: Dict[str, Any], policy: Dict[str, Any]) -> List[str]:
    triggers = policy.get("rollback_triggers", {}) if isinstance(policy.get("rollback_triggers"), dict) else {}
    reasons: List[str] = []
    quality_drop_threshold = float(triggers.get("quality_drop_vs_baseline_gt", 0.10) or 0.10)
    if snapshot.get("quality_drop_vs_baseline", 0.0) > quality_drop_threshold:
        reasons.append("QUALITY_DROP_TOO_HIGH")
    if bool(triggers.get("sticky_diagnostic", True)) and snapshot.get("sticky_diagnostic", False):
        reasons.append("ROLLBACK_STICKY_DIAGNOSTIC")
    relative_quality_floor = triggers.get("relative_quality_vs_global_lt")
    if relative_quality_floor is not None and snapshot.get("relative_quality_vs_global", 0.0) < float(relative_quality_floor):
        reasons.append("ROLLBACK_RELATIVE_QUALITY_TOO_LOW")
    return reasons


def resolve_recommended_mode(verdict: str, current_mode: str) -> str:
    normalized = current_mode or "GLOBAL_ONLY"
    if verdict == "ROLLBACK_TO_GLOBAL":
        return "GLOBAL_ONLY"
    if verdict != "PROMOTE_TO_PERSONAL":
        return normalized
    if normalized == "GLOBAL_ONLY":
        return "GLOBAL_PLUS_PERSONAL"
    return "PERSONAL_PRIMARY"


def decide(
    curriculum: Dict[str, Any],
    snapshot: Dict[str, Any],
    policy: Dict[str, Any],
    history: Dict[str, Any],
    current_mode: str,
) -> Dict[str, Any]:
    gate = resolve_effective_gate(curriculum, policy)
    reasons = evaluate_gate(snapshot, gate)
    rollback_reasons = evaluate_rollback(snapshot, policy)

    hysteresis = policy.get("mode_hysteresis", {}) if isinstance(policy.get("mode_hysteresis"), dict) else {}
    min_consecutive = int(hysteresis.get("min_consecutive_approve_windows", 1) or 1)
    promotion_cooldown_hours = float(hysteresis.get("promotion_cooldown_hours", 0) or 0)
    rollback_cooldown_hours = float(hysteresis.get("rollback_cooldown_hours", 0) or 0)

    verdict = "PROMOTE_TO_PERSONAL" if not reasons else "HOLD_GLOBAL"
    current_mode_normalized = current_mode or str(history.get("current_mode") or "GLOBAL_ONLY")

    if rollback_reasons:
        reasons.extend(rollback_reasons)
        if current_mode_normalized != "GLOBAL_ONLY":
            verdict = "ROLLBACK_TO_GLOBAL"
        else:
            verdict = "HOLD_GLOBAL"

    if verdict == "PROMOTE_TO_PERSONAL":
        approval_streak = recent_approve_streak(history) + 1
        if approval_streak < min_consecutive:
            verdict = "HOLD_GLOBAL"
            reasons.append("APPROVAL_STREAK_BELOW_MIN")
        elif cooldown_active(history, "last_rollback_at_utc", rollback_cooldown_hours):
            verdict = "HOLD_GLOBAL"
            reasons.append("ROLLBACK_COOLDOWN_ACTIVE")
        elif current_mode_normalized == "GLOBAL_PLUS_PERSONAL" and cooldown_active(
            history,
            "last_promotion_at_utc",
            promotion_cooldown_hours,
        ):
            verdict = "HOLD_GLOBAL"
            reasons.append("PROMOTION_COOLDOWN_ACTIVE")

    recommended_mode = resolve_recommended_mode(verdict, current_mode_normalized)
    return {
        "teacher_id": curriculum["teacher_id"],
        "symbol": curriculum["symbol"],
        "verdict": verdict,
        "recommended_mode": recommended_mode,
        "policy_id": str(policy.get("policy_id") or "TEACHER_PROMOTION_POLICY_V1"),
        "reasons": reasons,
        "effective_gate": gate,
        "decision_context": {
            "current_mode": current_mode_normalized,
            "approval_streak_after_current_window": recent_approve_streak(history) + (1 if not evaluate_gate(snapshot, gate) else 0),
            "promotion_cooldown_active": cooldown_active(history, "last_promotion_at_utc", promotion_cooldown_hours),
            "rollback_cooldown_active": cooldown_active(history, "last_rollback_at_utc", rollback_cooldown_hours),
        },
        "metrics": snapshot,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--curriculum", required=True)
    parser.add_argument("--snapshot", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--policy", help="Optional promotion policy JSON")
    parser.add_argument("--history", help="Optional promotion history JSON")
    parser.add_argument("--current-mode", default="", help="Current teacher_package_mode")
    args = parser.parse_args()

    curriculum = read_json(Path(args.curriculum))
    snapshot = read_json(Path(args.snapshot))
    policy = read_json(Path(args.policy)) if args.policy else {}
    history = read_json(Path(args.history)) if args.history else {}
    result = decide(curriculum, snapshot, policy, history, args.current_mode)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
