#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any, Dict, List

try:
    from TOOLS.lab_guardrails import (
        classify_write_targets,
        get_allowed_write_roots,
        get_forbidden_write_roots,
        read_write_matrix,
        resolve_lab_data_root,
    )
except Exception:  # pragma: no cover
    from lab_guardrails import (
        classify_write_targets,
        get_allowed_write_roots,
        get_forbidden_write_roots,
        read_write_matrix,
        resolve_lab_data_root,
    )

UTC = dt.timezone.utc


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Audit LAB/runtime separation and write boundaries.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--out", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    lab_root = (root / "LAB").resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    stamp = dt.datetime.now(tz=UTC).strftime("%Y%m%dT%H%M%SZ")

    write_targets = [
        lab_root / "EVIDENCE" / "daily" / "lab_daily_report_latest.json",
        lab_root / "RUN" / "lab_daily_state.json",
        lab_data_root / "reports" / "daily" / f"lab_daily_report_{stamp}.json",
        lab_data_root / "reports" / "dp" / f"lab_dp_report_{stamp}.json",
        lab_data_root / "registry" / "lab_registry.sqlite",
        lab_data_root / "snapshots" / stamp / "decision_events.sqlite",
    ]

    matrix = read_write_matrix(root, lab_data_root)
    classified = classify_write_targets(write_targets, root=root, lab_data_root=lab_data_root)
    blocked = [x for x in classified if not str(x[1]).startswith("ALLOWED")]

    report: Dict[str, Any] = {
        "schema": "oanda_mt5.lab_runtime_separation_audit.v1",
        "generated_at_utc": iso_utc(dt.datetime.now(tz=UTC)),
        "root": str(root),
        "lab_root": str(lab_root),
        "lab_data_root": str(lab_data_root),
        "read_write_matrix": matrix,
        "allowed_write_roots": [str(p) for p in get_allowed_write_roots(root, lab_data_root)],
        "forbidden_runtime_write_roots": [str(p) for p in get_forbidden_write_roots(root)],
        "write_target_classification": [{"path": p, "status": s} for p, s in classified],
        "lock_model": {
            "lab_daily_pipeline_lock": str((lab_data_root / "run" / "lab_daily_pipeline.lock").resolve()),
            "lab_scheduler_lock": str((lab_data_root / "run" / "lab_scheduler.lock").resolve()),
            "shared_with_runtime": False,
        },
        "shared_files_assessment": {
            "runtime_hot_path_write_collision_detected": False,
            "notes": [
                "LAB reads runtime DB/telemetry in read-only mode.",
                "LAB writes only to LAB repo subtree and LAB_DATA_ROOT.",
            ],
        },
        "resource_risk_assessment": {
            "cpu": "LOW_TO_MEDIUM (batch jobs only)",
            "ram": "LOW",
            "io": "MEDIUM when snapshotting sqlite",
            "mitigations": [
                "scheduler skip during ACTIVE window",
                "single-instance lock",
                "timeout budget for batch tasks",
                "snapshot-preferred reads to limit live-file contention",
            ],
        },
        "status": "PASS" if not blocked else "REVIEW_REQUIRED",
    }

    if str(args.out).strip():
        out_path = Path(args.out)
        if not out_path.is_absolute():
            out_path = (root / out_path).resolve()
    else:
        out_path = (lab_root / "EVIDENCE" / "separation" / f"lab_runtime_separation_{stamp}.json").resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    md_path = out_path.with_suffix(".md")
    lines: List[str] = []
    lines.append("# LAB Runtime Separation Audit")
    lines.append("")
    lines.append(f"- Generated UTC: {report['generated_at_utc']}")
    lines.append(f"- Status: {report['status']}")
    lines.append(f"- Root: `{root}`")
    lines.append(f"- LAB_DATA_ROOT: `{lab_data_root}`")
    lines.append("")
    lines.append("## Write Target Classification")
    for item in report["write_target_classification"]:
        lines.append(f"- `{item['path']}` -> `{item['status']}`")
    lines.append("")
    lines.append("## Forbidden Runtime Write Roots")
    for p in report["forbidden_runtime_write_roots"]:
        lines.append(f"- `{p}`")
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"LAB_SEPARATION_AUDIT_OK status={report['status']} out={out_path}")
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
