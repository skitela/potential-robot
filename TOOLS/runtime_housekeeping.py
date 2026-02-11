#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List


CACHE_DIR_NAMES = {"__pycache__", ".mypy_cache", ".pytest_cache", ".ruff_cache"}
RUNTIME_STATE_FILES = {
    "RUN/infobot.lock",
    "RUN/repair_agent.lock",
    "RUN/infobot_heartbeat.json",
    "RUN/infobot_alert.json",
    "RUN/repair_status.json",
}
EVIDENCE_RETENTION_GROUPS = (
    "EVIDENCE/dyrygent_smoke",
    "EVIDENCE/training_audit",
)


@dataclass
class Action:
    kind: str
    path: str
    applied: bool
    result: str
    bytes_before: int = 0
    bytes_after: int = 0


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def file_size(path: Path) -> int:
    try:
        return int(path.stat().st_size)
    except OSError:
        return 0


def dir_size(path: Path) -> int:
    total = 0
    for item in path.rglob("*"):
        if item.is_file():
            total += file_size(item)
    return total


def _trim_file_tail(path: Path, max_bytes: int) -> bool:
    if file_size(path) <= max_bytes:
        return False
    with path.open("rb") as handle:
        handle.seek(-max_bytes, 2)
        tail = handle.read(max_bytes)
    marker = b"[HOUSEKEEPING_TRUNCATED]\n"
    path.write_bytes(marker + tail)
    return True


def run_housekeeping(
    root: Path,
    *,
    apply: bool,
    keep_runs: int,
    max_single_log_mb: int,
) -> Dict[str, object]:
    actions: List[Action] = []

    for item in root.rglob("*"):
        if item.is_dir() and item.name in CACHE_DIR_NAMES:
            before = dir_size(item)
            if apply:
                shutil.rmtree(item, ignore_errors=True)
                exists = item.exists()
                actions.append(
                    Action(
                        kind="cache_dir",
                        path=str(item),
                        applied=True,
                        result="DELETED" if not exists else "FAILED",
                        bytes_before=before,
                        bytes_after=dir_size(item) if exists else 0,
                    )
                )
            else:
                actions.append(Action(kind="cache_dir", path=str(item), applied=False, result="PLAN", bytes_before=before))

    for item in root.rglob("*.pyc"):
        before = file_size(item)
        if apply:
            try:
                item.unlink(missing_ok=True)
                actions.append(
                    Action(
                        kind="pyc_file",
                        path=str(item),
                        applied=True,
                        result="DELETED" if not item.exists() else "FAILED",
                        bytes_before=before,
                    )
                )
            except OSError:
                actions.append(
                    Action(kind="pyc_file", path=str(item), applied=True, result="FAILED", bytes_before=before)
                )
        else:
            actions.append(Action(kind="pyc_file", path=str(item), applied=False, result="PLAN", bytes_before=before))

    for item in root.rglob("*.pyo"):
        before = file_size(item)
        if apply:
            try:
                item.unlink(missing_ok=True)
                actions.append(
                    Action(
                        kind="pyo_file",
                        path=str(item),
                        applied=True,
                        result="DELETED" if not item.exists() else "FAILED",
                        bytes_before=before,
                    )
                )
            except OSError:
                actions.append(
                    Action(kind="pyo_file", path=str(item), applied=True, result="FAILED", bytes_before=before)
                )
        else:
            actions.append(Action(kind="pyo_file", path=str(item), applied=False, result="PLAN", bytes_before=before))

    for rel in sorted(RUNTIME_STATE_FILES):
        path = (root / rel).resolve()
        if not path.exists():
            continue
        before = file_size(path)
        if apply:
            try:
                path.unlink(missing_ok=True)
                actions.append(
                    Action(
                        kind="runtime_state",
                        path=str(path),
                        applied=True,
                        result="DELETED" if not path.exists() else "FAILED",
                        bytes_before=before,
                    )
                )
            except OSError:
                actions.append(
                    Action(kind="runtime_state", path=str(path), applied=True, result="FAILED", bytes_before=before)
                )
        else:
            actions.append(Action(kind="runtime_state", path=str(path), applied=False, result="PLAN", bytes_before=before))

    max_log_bytes = int(max_single_log_mb) * 1024 * 1024
    logs_dir = (root / "LOGS").resolve()
    if logs_dir.exists():
        for log_file in logs_dir.glob("*.log"):
            before = file_size(log_file)
            if before <= max_log_bytes:
                continue
            if apply:
                changed = _trim_file_tail(log_file, max_log_bytes)
                after = file_size(log_file)
                actions.append(
                    Action(
                        kind="log_rotation",
                        path=str(log_file),
                        applied=True,
                        result="TRUNCATED" if changed else "FAILED",
                        bytes_before=before,
                        bytes_after=after,
                    )
                )
            else:
                actions.append(
                    Action(kind="log_rotation", path=str(log_file), applied=False, result="PLAN", bytes_before=before)
                )

    for rel in EVIDENCE_RETENTION_GROUPS:
        group = (root / rel).resolve()
        if not group.exists():
            continue
        children = [p for p in group.iterdir() if p.is_dir()]
        children.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        stale = children[int(keep_runs) :]
        for old in stale:
            before = dir_size(old)
            if apply:
                shutil.rmtree(old, ignore_errors=True)
                actions.append(
                    Action(
                        kind="evidence_retention",
                        path=str(old),
                        applied=True,
                        result="DELETED" if not old.exists() else "FAILED",
                        bytes_before=before,
                    )
                )
            else:
                actions.append(Action(kind="evidence_retention", path=str(old), applied=False, result="PLAN", bytes_before=before))

    deleted_bytes = sum(a.bytes_before for a in actions if a.result in {"DELETED", "TRUNCATED"})
    return {
        "status": "PASS",
        "root": str(root),
        "apply": apply,
        "keep_runs": int(keep_runs),
        "max_single_log_mb": int(max_single_log_mb),
        "ts_utc": utc_now_iso(),
        "actions": [a.__dict__ for a in actions],
        "summary": {
            "actions_total": len(actions),
            "actions_applied": sum(1 for a in actions if a.applied),
            "actions_failed": sum(1 for a in actions if a.result == "FAILED"),
            "bytes_reclaimed_estimate": deleted_bytes,
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Safe housekeeping for runtime/tooling artifacts.")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--evidence", default="")
    parser.add_argument("--keep-runs", type=int, default=40)
    parser.add_argument("--max-single-log-mb", type=int, default=8)
    parser.add_argument("--apply", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    report = run_housekeeping(
        root,
        apply=bool(args.apply),
        keep_runs=max(1, int(args.keep_runs)),
        max_single_log_mb=max(1, int(args.max_single_log_mb)),
    )

    if args.evidence:
        evidence_path = Path(args.evidence)
        if not evidence_path.is_absolute():
            evidence_path = (root / evidence_path).resolve()
        evidence_path.parent.mkdir(parents=True, exist_ok=True)
        evidence_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"HOUSEKEEPING_OK actions={report['summary']['actions_total']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
