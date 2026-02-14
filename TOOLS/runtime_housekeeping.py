#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
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
RUN_TEMP_FILE_PATTERNS = (
    "*.tmp",
)
TEMP_ROOTS_TO_PURGE = (
    "TMP_AUDIT_IO",
    "tests/_tmp_housekeeping",
    "EVIDENCE/test_tmp",
    "EVIDENCE/codex_repair_pycache",
    "EVIDENCE/_pycache_check",
    "EVIDENCE/repo_map_test",
    "EVIDENCE/tmp_py_write_test",
)
EVIDENCE_RETENTION_GROUPS_DIR_ONLY = (
    "EVIDENCE/dyrygent_smoke",
    "EVIDENCE/training_audit",
    "EVIDENCE/hard_xcross",
    "EVIDENCE/preflight_safe",
)
EVIDENCE_RETENTION_GROUPS_ANY = (
    "EVIDENCE/online_smoke",
    "EVIDENCE/housekeeping",
    "EVIDENCE/test_runs",
    "EVIDENCE/hard_xcross_smoke",
)
EVIDENCE_RETENTION_GROUP_AUDIT_V12 = "EVIDENCE/audit_v12_live"
EVIDENCE_RETENTION_GROUP_GATES = "EVIDENCE/gates"
TEMP_EVIDENCE_GLOB_DIRS = (
    "perm_probe_*",
    "hk_test_*",
)
DEFAULT_KEEP_RUNS = 20
DEFAULT_KEEP_AUDIT_V12_RUNS = 8
DEFAULT_KEEP_GATES = 200
DEFAULT_MAX_SINGLE_LOG_MB = 8


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
    for base, _, files in os.walk(path, onerror=lambda _e: None):
        for fname in files:
            total += file_size(Path(base) / fname)
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


def _remove_path(path: Path) -> bool:
    if not path.exists():
        return True
    try:
        if path.is_dir():
            shutil.rmtree(path, ignore_errors=True)
        else:
            path.unlink(missing_ok=True)
    except OSError:
        return False
    return not path.exists()


def run_housekeeping(
    root: Path,
    *,
    apply: bool,
    keep_runs: int,
    keep_audit_v12_runs: int,
    keep_gates: int,
    max_single_log_mb: int,
) -> Dict[str, object]:
    actions: List[Action] = []

    for rel in TEMP_ROOTS_TO_PURGE:
        p = (root / rel).resolve()
        if not p.exists():
            continue
        before = dir_size(p) if p.is_dir() else file_size(p)
        if apply:
            ok = _remove_path(p)
            actions.append(
                Action(
                    kind="temp_root",
                    path=str(p),
                    applied=True,
                    result="DELETED" if ok else "FAILED",
                    bytes_before=before,
                    bytes_after=0 if ok else (dir_size(p) if p.is_dir() else file_size(p)),
                )
            )
        else:
            actions.append(Action(kind="temp_root", path=str(p), applied=False, result="PLAN", bytes_before=before))

    evidence_root = (root / "EVIDENCE").resolve()
    if evidence_root.exists():
        for pattern in TEMP_EVIDENCE_GLOB_DIRS:
            for p in evidence_root.glob(pattern):
                if not p.is_dir():
                    continue
                before = dir_size(p)
                if apply:
                    ok = _remove_path(p)
                    actions.append(
                        Action(
                            kind="temp_root_glob",
                            path=str(p),
                            applied=True,
                            result="DELETED" if ok else "FAILED",
                            bytes_before=before,
                            bytes_after=0 if ok else dir_size(p),
                        )
                    )
                else:
                    actions.append(
                        Action(kind="temp_root_glob", path=str(p), applied=False, result="PLAN", bytes_before=before)
                    )

    for base, dirs, files in os.walk(root, topdown=True, onerror=lambda _e: None):
        base_path = Path(base)

        for dname in list(dirs):
            if dname not in CACHE_DIR_NAMES:
                continue
            item = base_path / dname
            before = dir_size(item)
            if apply:
                ok = _remove_path(item)
                actions.append(
                    Action(
                        kind="cache_dir",
                        path=str(item),
                        applied=True,
                        result="DELETED" if ok else "FAILED",
                        bytes_before=before,
                        bytes_after=0 if ok else dir_size(item),
                    )
                )
            else:
                actions.append(Action(kind="cache_dir", path=str(item), applied=False, result="PLAN", bytes_before=before))
            dirs.remove(dname)

        for fname in files:
            item = base_path / fname
            ext = item.suffix.lower()
            if ext not in {".pyc", ".pyo"}:
                continue
            before = file_size(item)
            kind = "pyc_file" if ext == ".pyc" else "pyo_file"
            if apply:
                ok = _remove_path(item)
                actions.append(
                    Action(
                        kind=kind,
                        path=str(item),
                        applied=True,
                        result="DELETED" if ok else "FAILED",
                        bytes_before=before,
                    )
                )
            else:
                actions.append(Action(kind=kind, path=str(item), applied=False, result="PLAN", bytes_before=before))

    for rel in sorted(RUNTIME_STATE_FILES):
        path = (root / rel).resolve()
        if not path.exists():
            continue
        before = file_size(path)
        if apply:
            ok = _remove_path(path)
            actions.append(
                Action(
                    kind="runtime_state",
                    path=str(path),
                    applied=True,
                    result="DELETED" if ok else "FAILED",
                    bytes_before=before,
                )
            )
        else:
            actions.append(Action(kind="runtime_state", path=str(path), applied=False, result="PLAN", bytes_before=before))

    run_dir = (root / "RUN").resolve()
    if run_dir.exists():
        for pattern in RUN_TEMP_FILE_PATTERNS:
            for path in run_dir.glob(pattern):
                if not path.is_file():
                    continue
                before = file_size(path)
                if apply:
                    ok = _remove_path(path)
                    actions.append(
                        Action(
                            kind="run_temp_file",
                            path=str(path),
                            applied=True,
                            result="DELETED" if ok else "FAILED",
                            bytes_before=before,
                        )
                    )
                else:
                    actions.append(
                        Action(kind="run_temp_file", path=str(path), applied=False, result="PLAN", bytes_before=before)
                    )

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

    retention_groups = [(rel, int(keep_runs), True) for rel in EVIDENCE_RETENTION_GROUPS_DIR_ONLY]
    retention_groups.extend((rel, int(keep_runs), False) for rel in EVIDENCE_RETENTION_GROUPS_ANY)
    retention_groups.append((EVIDENCE_RETENTION_GROUP_AUDIT_V12, int(keep_audit_v12_runs), True))
    retention_groups.append((EVIDENCE_RETENTION_GROUP_GATES, int(keep_gates), False))

    for rel, keep_count, dirs_only in retention_groups:
        group = (root / rel).resolve()
        if not group.exists():
            continue
        if dirs_only:
            children = [p for p in group.iterdir() if p.is_dir()]
        else:
            children = [p for p in group.iterdir() if p.is_dir() or p.is_file()]
        children.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        stale = children[int(keep_count) :]
        for old in stale:
            before = dir_size(old) if old.is_dir() else file_size(old)
            if apply:
                ok = _remove_path(old)
                actions.append(
                    Action(
                        kind="evidence_retention",
                        path=str(old),
                        applied=True,
                        result="DELETED" if ok else "FAILED",
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
        "keep_audit_v12_runs": int(keep_audit_v12_runs),
        "keep_gates": int(keep_gates),
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
    parser.add_argument("--keep-runs", type=int, default=DEFAULT_KEEP_RUNS)
    parser.add_argument("--keep-audit-v12-runs", type=int, default=DEFAULT_KEEP_AUDIT_V12_RUNS)
    parser.add_argument("--keep-gates", type=int, default=DEFAULT_KEEP_GATES)
    parser.add_argument("--max-single-log-mb", type=int, default=DEFAULT_MAX_SINGLE_LOG_MB)
    parser.add_argument("--apply", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    report = run_housekeeping(
        root,
        apply=bool(args.apply),
        keep_runs=max(1, int(args.keep_runs)),
        keep_audit_v12_runs=max(1, int(args.keep_audit_v12_runs)),
        keep_gates=max(1, int(args.keep_gates)),
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
