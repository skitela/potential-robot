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
SCHEMA = "oanda.mt5.shadow_soft_guard_candidate.v1"


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _safe_load(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _latest_by_pattern(base: Path, pattern: str) -> Optional[Path]:
    files = sorted(base.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0] if files else None


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Build soft-guard candidate rules from shadow/runtime diagnostics.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--out-report", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    now = dt.datetime.now(tz=UTC)
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    stage1_dir = (lab_data_root / "reports" / "stage1").resolve()
    stamp = now.strftime("%Y%m%dT%H%M%SZ")

    out_report = (
        Path(args.out_report).resolve()
        if str(args.out_report).strip()
        else (stage1_dir / f"shadow_soft_guard_candidate_{stamp}.json").resolve()
    )
    out_report = ensure_write_parent(out_report, root=root, lab_data_root=lab_data_root)
    latest_out = ensure_write_parent((stage1_dir / "shadow_soft_guard_candidate_latest.json").resolve(), root=root, lab_data_root=lab_data_root)

    kpi_dir = (root / "EVIDENCE" / "runtime_kpi").resolve()
    bridge_dir = (root / "EVIDENCE" / "bridge_audit").resolve()
    kpi_path = _latest_by_pattern(kpi_dir, "runtime_kpi_snapshot_*.json")
    bridge_path = _latest_by_pattern(bridge_dir, "bridge_soak_compare_*.json")
    kpi = _safe_load(kpi_path) if kpi_path else {}
    bridge = _safe_load(bridge_path) if bridge_path else {}
    progression = _safe_load((stage1_dir / "shadow_plus_progression_latest.json").resolve())

    timeout_count = int(((kpi.get("kpi") or {}).get("timeout_count") or 0))
    deadlock_proxy = int(((kpi.get("kpi") or {}).get("deadlock_or_crash_proxy_count") or 0))
    trade_p95_ms = float((((bridge.get("after_soak_window") or {}).get("metrics") or {}).get("bridge_wait", {}) or {}).get("p95_ms") or 0.0)
    candidate_enabled = bool((progression.get("feature_flags") or {}).get("enable_soft_guard_candidate_pack"))

    candidate_ready = bool(candidate_enabled and timeout_count <= 0 and deadlock_proxy <= 0 and (trade_p95_ms <= 250.0 if trade_p95_ms > 0 else True))
    proposed_rules: Dict[str, Any] = {
        "mode": "ADVISORY_ONLY",
        "trigger_if": {
            "runtime_timeout_count_gt": 0,
            "deadlock_proxy_count_gt": 0,
            "bridge_wait_p95_ms_gt": 250.0,
        },
        "action": "PROPOSE_PROFILE_DOWNGRADE_TO_BEZPIECZNY",
        "apply_to_live": False,
    }

    payload: Dict[str, Any] = {
        "schema": SCHEMA,
        "generated_at_utc": iso_utc(now),
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "candidate_enabled": candidate_enabled,
        "candidate_ready": candidate_ready,
        "inputs": {
            "runtime_kpi_path": str(kpi_path) if kpi_path else "MISSING",
            "bridge_soak_path": str(bridge_path) if bridge_path else "MISSING",
        },
        "observed": {
            "timeout_count": timeout_count,
            "deadlock_proxy_count": deadlock_proxy,
            "bridge_wait_p95_ms": trade_p95_ms if trade_p95_ms > 0 else "UNKNOWN",
        },
        "proposed_rules": proposed_rules,
        "notes": [
            "Soft-guard candidate is advisory only.",
            "No live/runtime mutation in this tool.",
        ],
    }

    out_report.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    latest_out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"SHADOW_SOFT_GUARD_CANDIDATE_DONE candidate_ready={str(candidate_ready).lower()} report={out_report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

