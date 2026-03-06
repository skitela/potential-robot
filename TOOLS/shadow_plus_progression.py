#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any, Dict, Optional

try:
    from TOOLS.lab_guardrails import ensure_write_parent, resolve_lab_data_root
except Exception:  # pragma: no cover
    from lab_guardrails import ensure_write_parent, resolve_lab_data_root

UTC = dt.timezone.utc
STATE_SCHEMA = "oanda.mt5.shadow_plus_progress_state.v1"
REPORT_SCHEMA = "oanda.mt5.shadow_plus_progress_report.v1"


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _safe_load(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return _load_json(path)
    except Exception:
        return {}


def _latest_by_pattern(base: Path, pattern: str) -> Optional[Path]:
    files = sorted(base.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0] if files else None


def _compute_streak(history: Dict[str, str], today: dt.date) -> int:
    key = today.isoformat()
    if str(history.get(key) or "").upper() != "STABLE":
        return 0
    streak = 1
    cur = today
    while True:
        cur = cur - dt.timedelta(days=1)
        if str(history.get(cur.isoformat()) or "").upper() == "STABLE":
            streak += 1
            continue
        break
    return int(streak)


def _stage_from_streak(streak: int, d3: int, d7: int, d14: int) -> str:
    if streak >= d14:
        return "SOFT_GUARD_CANDIDATE"
    if streak >= d7:
        return "LIVE_ADVISORY_READY"
    if streak >= d3:
        return "SHADOW_PLUS_EXTENDED"
    return "WARMUP"


def _days_to_next(streak: int, d3: int, d7: int, d14: int) -> Dict[str, int]:
    return {
        "to_shadow_plus_extended": max(0, d3 - streak),
        "to_live_advisory_ready": max(0, d7 - streak),
        "to_soft_guard_candidate": max(0, d14 - streak),
    }


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Track 3/7/14-day Shadow+ progression gates.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--stable-verdicts", default="PASS,REVIEW_REQUIRED")
    ap.add_argument("--extended-days", type=int, default=3)
    ap.add_argument("--advisory-days", type=int, default=7)
    ap.add_argument("--soft-guard-days", type=int, default=14)
    ap.add_argument("--state-file", default="")
    ap.add_argument("--out-report", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    now = dt.datetime.now(tz=UTC)
    today = now.date()
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    stage1_dir = (lab_data_root / "reports" / "stage1").resolve()
    run_dir = (lab_data_root / "run").resolve()
    stamp = now.strftime("%Y%m%dT%H%M%SZ")

    stable_verdicts = {x.strip().upper() for x in str(args.stable_verdicts).split(",") if x.strip()}
    d3 = max(1, int(args.extended_days))
    d7 = max(d3 + 1, int(args.advisory_days))
    d14 = max(d7 + 1, int(args.soft_guard_days))

    state_file = (
        Path(args.state_file).resolve()
        if str(args.state_file).strip()
        else (run_dir / "shadow_plus_progress_state.json").resolve()
    )
    out_report = (
        Path(args.out_report).resolve()
        if str(args.out_report).strip()
        else (stage1_dir / f"shadow_plus_progression_{stamp}.json").resolve()
    )
    state_file = ensure_write_parent(state_file, root=root, lab_data_root=lab_data_root)
    out_report = ensure_write_parent(out_report, root=root, lab_data_root=lab_data_root)
    latest_out = ensure_write_parent((stage1_dir / "shadow_plus_progression_latest.json").resolve(), root=root, lab_data_root=lab_data_root)

    gonogo_path = (stage1_dir / "stage1_shadow_gonogo_latest.json").resolve()
    gonogo = _safe_load(gonogo_path)
    verdict = str(gonogo.get("verdict") or "").upper()
    status = str(gonogo.get("status") or "").upper()
    stable_run = bool(verdict in stable_verdicts and status in {"PASS", "WARN"})

    state = _safe_load(state_file)
    history = state.get("history_days") if isinstance(state.get("history_days"), dict) else {}
    history = {str(k): str(v).upper() for k, v in history.items()}

    day_key = today.isoformat()
    prev_mark = str(history.get(day_key) or "")
    new_mark = "STABLE" if stable_run else "UNSTABLE"
    if not prev_mark:
        history[day_key] = new_mark
    elif prev_mark == "STABLE" and new_mark == "UNSTABLE":
        history[day_key] = "UNSTABLE"
    # If previously UNSTABLE, keep UNSTABLE for conservatism.

    # keep only last 60 calendar days to bound state growth
    min_day = today - dt.timedelta(days=60)
    for k in list(history.keys()):
        try:
            if dt.date.fromisoformat(k) < min_day:
                history.pop(k, None)
        except Exception:
            history.pop(k, None)

    stable_total = sum(1 for v in history.values() if str(v).upper() == "STABLE")
    unstable_total = sum(1 for v in history.values() if str(v).upper() == "UNSTABLE")
    streak = _compute_streak(history, today)
    stage = _stage_from_streak(streak, d3, d7, d14)
    days_left = _days_to_next(streak, d3, d7, d14)

    report: Dict[str, Any] = {
        "schema": REPORT_SCHEMA,
        "generated_at_utc": iso_utc(now),
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "source": {
            "stage1_shadow_gonogo": str(gonogo_path),
            "verdict": verdict or "UNKNOWN",
            "status": status or "UNKNOWN",
        },
        "stable_run": bool(stable_run),
        "thresholds_days": {
            "shadow_plus_extended": d3,
            "live_advisory_ready": d7,
            "soft_guard_candidate": d14,
        },
        "progress": {
            "stable_streak_days": int(streak),
            "stable_days_total": int(stable_total),
            "unstable_days_total": int(unstable_total),
            "stage": stage,
            "days_to_next": days_left,
        },
        "feature_flags": {
            "enable_extended_shadow_profiles": bool(stage in {"SHADOW_PLUS_EXTENDED", "LIVE_ADVISORY_READY", "SOFT_GUARD_CANDIDATE"}),
            "enable_live_advisory_pack": bool(stage in {"LIVE_ADVISORY_READY", "SOFT_GUARD_CANDIDATE"}),
            "enable_soft_guard_candidate_pack": bool(stage in {"SOFT_GUARD_CANDIDATE"}),
        },
        "notes": [
            "Stage progression is SHADOW-only; no live mutation.",
            "Daily streak counts calendar days with STABLE go/no-go outcomes.",
        ],
    }

    state_payload = {
        "schema": STATE_SCHEMA,
        "updated_at_utc": iso_utc(now),
        "history_days": history,
        "thresholds_days": report["thresholds_days"],
        "stable_streak_days": int(streak),
        "stage": stage,
    }

    state_file.write_text(json.dumps(state_payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    out_report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    latest_out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "SHADOW_PLUS_PROGRESSION_DONE stage={0} stable_streak_days={1} stable_run={2} report={3}".format(
            stage,
            streak,
            str(bool(stable_run)).lower(),
            str(out_report),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

