#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    from TOOLS.lab_guardrails import ensure_write_parent, resolve_lab_data_root
except Exception:  # pragma: no cover
    from lab_guardrails import ensure_write_parent, resolve_lab_data_root

UTC = dt.timezone.utc
SCHEMA = "oanda.mt5.shadow_live_advisory_pack.v1"


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _safe_load(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Build live-advisory pack from Shadow reports (no live mutation).")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--out-report", default="")
    return ap.parse_args()


def _extract_recommendations(eval_payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    rows = eval_payload.get("evaluation_by_symbol") if isinstance(eval_payload.get("evaluation_by_symbol"), list) else []
    for row in rows:
        if not isinstance(row, dict):
            continue
        rec = row.get("recommendation_for_tomorrow") if isinstance(row.get("recommendation_for_tomorrow"), dict) else {}
        out.append(
            {
                "symbol": str(row.get("symbol") or "").upper(),
                "recommended_profile": str(rec.get("recommended_profile") or ""),
                "guard_reason": str(rec.get("guard_reason") or ""),
                "human_decision_required": bool(rec.get("human_decision_required", True)),
                "auto_apply": bool(rec.get("auto_apply", False)),
            }
        )
    return [r for r in out if r["symbol"]]


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
        else (stage1_dir / f"shadow_live_advisory_{stamp}.json").resolve()
    )
    out_report = ensure_write_parent(out_report, root=root, lab_data_root=lab_data_root)
    latest_out = ensure_write_parent((stage1_dir / "shadow_live_advisory_latest.json").resolve(), root=root, lab_data_root=lab_data_root)

    gonogo = _safe_load((stage1_dir / "stage1_shadow_gonogo_latest.json").resolve())
    eval_payload = _safe_load((stage1_dir / "stage1_profile_pack_eval_latest.json").resolve())
    progression = _safe_load((stage1_dir / "shadow_plus_progression_latest.json").resolve())

    verdict = str(gonogo.get("verdict") or "").upper()
    status = str(gonogo.get("status") or "").upper()
    recs = _extract_recommendations(eval_payload)
    advisory_enabled = bool((progression.get("feature_flags") or {}).get("enable_live_advisory_pack"))

    payload: Dict[str, Any] = {
        "schema": SCHEMA,
        "generated_at_utc": iso_utc(now),
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "advisory_enabled": advisory_enabled,
        "source_status": {"gonogo_verdict": verdict or "UNKNOWN", "gonogo_status": status or "UNKNOWN"},
        "recommendations": recs,
        "summary": {
            "symbols_n": len(recs),
            "requires_human_decision_n": sum(1 for r in recs if r.get("human_decision_required")),
        },
        "notes": [
            "Advisory package only. No runtime/live mutation.",
            "Use this pack for operator review before any live change.",
        ],
    }

    out_report.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    latest_out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"SHADOW_LIVE_ADVISORY_DONE symbols_n={len(recs)} report={out_report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

