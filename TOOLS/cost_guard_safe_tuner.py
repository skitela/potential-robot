#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import datetime as dt
import hashlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

UTC = dt.timezone.utc
STATE_SCHEMA = "oanda.mt5.cost_guard_safe_tuner_state.v1"

PROFILE_PRESETS: Dict[str, Dict[str, Any]] = {
    "fast_relax_stable": {
        "cost_guard_auto_relax_enabled": True,
        "cost_guard_auto_relax_min_total_decisions": 120,
        "cost_guard_auto_relax_min_wave1_decisions": 24,
        "cost_guard_auto_relax_min_unknown_blocks": 20,
        "cost_guard_auto_relax_hysteresis_enabled": True,
        "cost_guard_auto_relax_hysteresis_total_ratio": 0.80,
        "cost_guard_auto_relax_hysteresis_wave1_ratio": 0.80,
        "cost_guard_auto_relax_hysteresis_unknown_ratio": 0.80,
        "cost_guard_auto_relax_flap_window_minutes": 30,
        "cost_guard_auto_relax_flap_alert_threshold": 3,
    }
}


def iso_utc(ts: Optional[dt.datetime] = None) -> str:
    return (ts or dt.datetime.now(tz=UTC)).astimezone(UTC).isoformat().replace("+00:00", "Z")


def canonical_json_hash(payload: Dict[str, Any]) -> str:
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def atomic_write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".tmp_cost_tuner_", suffix=".json", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2, sort_keys=True)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            try:
                os.remove(tmp)
            except OSError:
                pass


def load_json(path: Path, default: Dict[str, Any]) -> Dict[str, Any]:
    if not path.exists():
        return copy.deepcopy(default)
    try:
        obj = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return copy.deepcopy(default)
    if not isinstance(obj, dict):
        return copy.deepcopy(default)
    return obj


def default_state() -> Dict[str, Any]:
    return {
        "schema_version": STATE_SCHEMA,
        "updated_at_utc": iso_utc(),
        "changes": [],
    }


def _today_changes(changes: List[Dict[str, Any]], now: dt.datetime) -> List[Dict[str, Any]]:
    day = now.astimezone(UTC).strftime("%Y-%m-%d")
    out: List[Dict[str, Any]] = []
    for row in changes:
        ts = str(row.get("ts_utc") or "")
        if ts.startswith(day):
            out.append(row)
    return out


def apply_profile(
    *,
    root: Path,
    profile: str,
    daily_limit: int,
    note: str = "",
) -> Dict[str, Any]:
    if profile not in PROFILE_PRESETS:
        raise ValueError(f"Unknown profile: {profile}")
    now = dt.datetime.now(tz=UTC)
    config_path = root / "CONFIG" / "strategy.json"
    state_path = root / "RUN" / "cost_guard_safe_tuner_state.json"
    backup_dir = root / "RUN" / "cost_gate_prepared"
    evidence_dir = root / "EVIDENCE"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    backup_dir.mkdir(parents=True, exist_ok=True)

    cfg = json.loads(config_path.read_text(encoding="utf-8"))
    if not isinstance(cfg, dict):
        raise RuntimeError("CONFIG/strategy.json is not a JSON object")
    state = load_json(state_path, default_state())
    changes = list(state.get("changes") or [])
    today_changes = _today_changes(changes, now)
    if len(today_changes) >= int(max(1, daily_limit)):
        return {
            "status": "SKIP_DAILY_LIMIT",
            "reason": "DAILY_LIMIT_REACHED",
            "today_changes": len(today_changes),
            "daily_limit": int(max(1, daily_limit)),
        }

    backup_path = backup_dir / f"strategy_tuner_backup_{now.strftime('%Y%m%dT%H%M%SZ')}.json"
    atomic_write_json(backup_path, cfg)

    before_hash = canonical_json_hash(cfg)
    new_cfg = copy.deepcopy(cfg)
    for k, v in PROFILE_PRESETS[profile].items():
        new_cfg[str(k)] = v
    after_hash = canonical_json_hash(new_cfg)
    atomic_write_json(config_path, new_cfg)

    change = {
        "ts_utc": iso_utc(now),
        "action": "apply",
        "profile": str(profile),
        "backup_path": str(backup_path),
        "config_hash_before": before_hash,
        "config_hash_after": after_hash,
        "note": str(note or ""),
    }
    changes.append(change)
    state["changes"] = changes
    state["updated_at_utc"] = iso_utc(now)
    atomic_write_json(state_path, state)

    report_path = evidence_dir / f"cost_guard_safe_tuner_apply_{now.strftime('%Y%m%dT%H%M%SZ')}.json"
    report = {
        "schema_version": "oanda.mt5.cost_guard_safe_tuner_apply.v1",
        "status": "PASS",
        "applied_at_utc": iso_utc(now),
        "profile": str(profile),
        "backup_path": str(backup_path),
        "state_path": str(state_path),
        "config_path": str(config_path),
        "daily_limit": int(max(1, daily_limit)),
        "today_changes_after_apply": len(_today_changes(changes, now)),
        "config_hash_before": before_hash,
        "config_hash_after": after_hash,
    }
    atomic_write_json(report_path, report)
    report["report_path"] = str(report_path)
    return report


def rollback_last(*, root: Path, backup_path: str = "", note: str = "") -> Dict[str, Any]:
    now = dt.datetime.now(tz=UTC)
    config_path = root / "CONFIG" / "strategy.json"
    state_path = root / "RUN" / "cost_guard_safe_tuner_state.json"
    evidence_dir = root / "EVIDENCE"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    state = load_json(state_path, default_state())
    changes = list(state.get("changes") or [])

    candidate = Path(backup_path).resolve() if str(backup_path).strip() else None
    if candidate is None:
        for row in reversed(changes):
            bp = row.get("backup_path")
            if isinstance(bp, str) and bp.strip():
                p = Path(bp)
                if p.exists():
                    candidate = p
                    break
    if candidate is None or not candidate.exists():
        return {"status": "FAIL", "reason": "BACKUP_NOT_FOUND"}

    backup_cfg = json.loads(candidate.read_text(encoding="utf-8"))
    if not isinstance(backup_cfg, dict):
        return {"status": "FAIL", "reason": "BACKUP_INVALID_JSON"}

    before_cfg = json.loads(config_path.read_text(encoding="utf-8"))
    before_hash = canonical_json_hash(before_cfg if isinstance(before_cfg, dict) else {})
    after_hash = canonical_json_hash(backup_cfg)
    atomic_write_json(config_path, backup_cfg)

    change = {
        "ts_utc": iso_utc(now),
        "action": "rollback",
        "profile": "rollback",
        "backup_path": str(candidate),
        "config_hash_before": before_hash,
        "config_hash_after": after_hash,
        "note": str(note or ""),
    }
    changes.append(change)
    state["changes"] = changes
    state["updated_at_utc"] = iso_utc(now)
    atomic_write_json(state_path, state)

    report_path = evidence_dir / f"cost_guard_safe_tuner_rollback_{now.strftime('%Y%m%dT%H%M%SZ')}.json"
    report = {
        "schema_version": "oanda.mt5.cost_guard_safe_tuner_rollback.v1",
        "status": "PASS",
        "rollback_at_utc": iso_utc(now),
        "backup_path": str(candidate),
        "state_path": str(state_path),
        "config_path": str(config_path),
        "config_hash_before": before_hash,
        "config_hash_after": after_hash,
    }
    atomic_write_json(report_path, report)
    report["report_path"] = str(report_path)
    return report


def tuner_status(*, root: Path) -> Dict[str, Any]:
    state_path = root / "RUN" / "cost_guard_safe_tuner_state.json"
    config_path = root / "CONFIG" / "strategy.json"
    state = load_json(state_path, default_state())
    cfg = json.loads(config_path.read_text(encoding="utf-8"))
    cfg_hash = canonical_json_hash(cfg if isinstance(cfg, dict) else {})
    return {
        "status": "PASS",
        "state_path": str(state_path),
        "config_path": str(config_path),
        "changes_total": len(list(state.get("changes") or [])),
        "last_change": (list(state.get("changes") or [])[-1] if list(state.get("changes") or []) else None),
        "config_hash": cfg_hash,
    }


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Safe tuner for cost-guard runtime settings.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--mode", choices=("status", "apply", "rollback"), default="status")
    ap.add_argument("--profile", default="fast_relax_stable")
    ap.add_argument("--daily-limit", type=int, default=2)
    ap.add_argument("--backup-path", default="")
    ap.add_argument("--note", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    if args.mode == "status":
        payload = tuner_status(root=root)
    elif args.mode == "apply":
        payload = apply_profile(
            root=root,
            profile=str(args.profile),
            daily_limit=int(max(1, args.daily_limit)),
            note=str(args.note or ""),
        )
    else:
        payload = rollback_last(root=root, backup_path=str(args.backup_path or ""), note=str(args.note or ""))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0 if str(payload.get("status")) in {"PASS", "SKIP_DAILY_LIMIT"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
