#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
No-strategy-drift validation harness for Wave 2R.
Detects whether modified files intersect strategy/signal/risk logic surfaces.
"""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Set


STRATEGY_SURFACES: Set[str] = {
    "BIN/safetybot.py",
    "BIN/risk_manager.py",
    "BIN/scheduler.py",
    "BIN/oanda_limits_guard.py",
}


def utc_now_z() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _git_changed_files(root: Path) -> List[str]:
    try:
        proc = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=str(root),
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
    except Exception:
        return []
    out: List[str] = []
    for raw in (proc.stdout or "").splitlines():
        if not raw.strip():
            continue
        if len(raw) < 4:
            continue
        path = raw[3:].strip()
        if path:
            out.append(path.replace("\\", "/"))
    return sorted(set(out))


def evaluate(changed: List[str]) -> Dict[str, object]:
    strategy_touched = [p for p in changed if p in STRATEGY_SURFACES]
    if strategy_touched:
        verdict = "REVIEW_REQUIRED"
        strategy_drift_risk = True
    else:
        verdict = "PASS"
        strategy_drift_risk = False
    return {
        "ts_utc": utc_now_z(),
        "no_strategy_drift_check": {
            "verdict": verdict,
            "strategy_drift_risk": strategy_drift_risk,
            "changed_files": changed,
            "strategy_surfaces": sorted(STRATEGY_SURFACES),
            "strategy_surfaces_touched": strategy_touched,
            "notes": (
                "Any change in strategy surfaces requires explicit human review."
                if strategy_touched
                else "No strategy surfaces changed."
            ),
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="No strategy drift check")
    ap.add_argument("--root", default=".", help="Repo root")
    ap.add_argument("--out", default="EVIDENCE/no_strategy_drift_check.json", help="Output JSON path")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    changed = _git_changed_files(root)
    report = evaluate(changed)
    out_path = (root / args.out).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(json.dumps({
        "status": "OK",
        "out": str(out_path),
        "verdict": report["no_strategy_drift_check"]["verdict"],
        "strategy_surfaces_touched": report["no_strategy_drift_check"]["strategy_surfaces_touched"],
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
