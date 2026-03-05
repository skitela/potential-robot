from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Iterable, List, Tuple


@dataclass(frozen=True)
class CostGuardMetrics:
    decision_total: int
    decision_wave1: int
    unknown_blocks: int
    critical_incidents: int
    error_or_worse_incidents: int


@dataclass(frozen=True)
class CostGuardThresholds:
    min_total_on: int
    min_wave1_on: int
    min_unknown_on: int
    max_critical: int
    max_errors: int
    min_total_off: int
    min_wave1_off: int
    min_unknown_off: int


def derive_off_threshold(on_value: int, ratio: float) -> int:
    base = int(max(1, on_value))
    r = float(max(0.0, min(1.0, ratio)))
    return int(max(1, round(base * r)))


def evaluate_cost_guard_state(
    *,
    prev_active: bool,
    enabled: bool,
    metrics: CostGuardMetrics,
    thresholds: CostGuardThresholds,
    hysteresis_enabled: bool,
) -> Dict[str, object]:
    checks_on = {
        "decision_total_ok": int(metrics.decision_total) >= int(thresholds.min_total_on),
        "decision_wave1_ok": int(metrics.decision_wave1) >= int(thresholds.min_wave1_on),
        "unknown_blocks_ok": int(metrics.unknown_blocks) >= int(thresholds.min_unknown_on),
        "critical_ok": int(metrics.critical_incidents) <= int(thresholds.max_critical),
        "errors_ok": int(metrics.error_or_worse_incidents) <= int(thresholds.max_errors),
    }
    checks_off = {
        "decision_total_ok": int(metrics.decision_total) >= int(thresholds.min_total_off),
        "decision_wave1_ok": int(metrics.decision_wave1) >= int(thresholds.min_wave1_off),
        "unknown_blocks_ok": int(metrics.unknown_blocks) >= int(thresholds.min_unknown_off),
        "critical_ok": int(metrics.critical_incidents) <= int(thresholds.max_critical),
        "errors_ok": int(metrics.error_or_worse_incidents) <= int(thresholds.max_errors),
    }

    if not bool(enabled):
        return {
            "active": False,
            "reason": "DISABLED_IN_CONFIG",
            "checks_on": checks_on,
            "checks_off": checks_off,
            "hysteresis_hold": False,
        }

    if all(bool(v) for v in checks_on.values()):
        return {
            "active": True,
            "reason": "AUTO_RELAX_ACTIVE_THRESHOLD_MET",
            "checks_on": checks_on,
            "checks_off": checks_off,
            "hysteresis_hold": False,
        }

    if bool(prev_active) and bool(hysteresis_enabled) and all(bool(v) for v in checks_off.values()):
        return {
            "active": True,
            "reason": "AUTO_RELAX_ACTIVE_HYSTERESIS_HOLD",
            "checks_on": checks_on,
            "checks_off": checks_off,
            "hysteresis_hold": True,
        }

    missing = [name for name, ok in checks_on.items() if not bool(ok)]
    reason = ("WAIT_" + "_".join(missing[:3])).upper() if missing else "WAIT_CONDITIONS"
    return {
        "active": False,
        "reason": reason,
        "checks_on": checks_on,
        "checks_off": checks_off,
        "hysteresis_hold": False,
    }


def update_transition_window(
    *,
    history_ts: Iterable[float],
    now_ts: float,
    window_sec: int,
    changed: bool,
) -> Tuple[List[float], int]:
    win = max(1, int(window_sec))
    threshold_ts = float(now_ts) - float(win)
    kept = [float(x) for x in history_ts if float(x) >= threshold_ts]
    if bool(changed):
        kept.append(float(now_ts))
    return kept, len(kept)
