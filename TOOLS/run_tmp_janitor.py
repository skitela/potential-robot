#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Tuple


DEFAULT_MIN_AGE_SEC = 20 * 60
DEFAULT_KEEP_PER_PREFIX = 4
DEFAULT_MAX_DELETE = 50000


@dataclass
class JanitorAction:
    kind: str
    path: str
    applied: bool
    result: str
    age_sec: int
    size_bytes: int
    prefix: str


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _safe_size(path: Path) -> int:
    try:
        return int(path.stat().st_size)
    except OSError:
        return 0


def _safe_age_sec(path: Path, now_ts: float) -> int:
    try:
        mtime = float(path.stat().st_mtime)
    except OSError:
        return 10**9
    return max(0, int(now_ts - mtime))


def _tmp_prefix(filename: str) -> str:
    marker = ".tmp."
    idx = filename.find(marker)
    if idx < 0:
        return filename
    return filename[: idx + len(marker)]


def _iter_tmpdot_files(run_dir: Path) -> Iterable[Path]:
    yield from run_dir.glob("*.tmp.*")


def run_janitor(
    root: Path,
    *,
    run_rel: str,
    min_age_sec: int,
    keep_per_prefix: int,
    max_delete: int,
    apply: bool,
) -> Dict[str, object]:
    now_ts = datetime.now(timezone.utc).timestamp()
    run_dir = (root / run_rel).resolve()
    actions: List[JanitorAction] = []

    if not run_dir.exists():
        return {
            "status": "PASS",
            "root": str(root),
            "run_dir": str(run_dir),
            "apply": bool(apply),
            "ts_utc": utc_now_iso(),
            "actions": [],
            "summary": {
                "candidates_total": 0,
                "planned_delete": 0,
                "deleted": 0,
                "failed": 0,
                "bytes_reclaimed": 0,
            },
        }

    groups: Dict[str, List[Tuple[Path, float]]] = {}
    for path in _iter_tmpdot_files(run_dir):
        if not path.is_file():
            continue
        prefix = _tmp_prefix(path.name)
        try:
            mtime = float(path.stat().st_mtime)
        except OSError:
            mtime = 0.0
        groups.setdefault(prefix, []).append((path, mtime))

    candidates_total = sum(len(v) for v in groups.values())
    planned: List[Tuple[Path, str, int, int]] = []

    for prefix, items in groups.items():
        # newest first
        items.sort(key=lambda pair: pair[1], reverse=True)
        protected = max(0, int(keep_per_prefix))
        for idx, (path, _mtime) in enumerate(items):
            if idx < protected:
                continue
            age_sec = _safe_age_sec(path, now_ts)
            if age_sec < max(0, int(min_age_sec)):
                continue
            size = _safe_size(path)
            planned.append((path, prefix, age_sec, size))

    planned.sort(key=lambda t: t[2], reverse=True)  # oldest first
    if max_delete > 0:
        planned = planned[: int(max_delete)]

    bytes_reclaimed = 0
    deleted = 0
    failed = 0

    for path, prefix, age_sec, size in planned:
        if apply:
            ok = False
            try:
                path.unlink(missing_ok=True)
                ok = (not path.exists())
            except OSError:
                ok = False
            if ok:
                deleted += 1
                bytes_reclaimed += size
                actions.append(
                    JanitorAction(
                        kind="run_tmpdot",
                        path=str(path),
                        applied=True,
                        result="DELETED",
                        age_sec=int(age_sec),
                        size_bytes=int(size),
                        prefix=prefix,
                    )
                )
            else:
                failed += 1
                actions.append(
                    JanitorAction(
                        kind="run_tmpdot",
                        path=str(path),
                        applied=True,
                        result="FAILED",
                        age_sec=int(age_sec),
                        size_bytes=int(size),
                        prefix=prefix,
                    )
                )
        else:
            actions.append(
                JanitorAction(
                    kind="run_tmpdot",
                    path=str(path),
                    applied=False,
                    result="PLAN",
                    age_sec=int(age_sec),
                    size_bytes=int(size),
                    prefix=prefix,
                )
            )

    return {
        "status": "PASS",
        "root": str(root),
        "run_dir": str(run_dir),
        "apply": bool(apply),
        "min_age_sec": int(min_age_sec),
        "keep_per_prefix": int(keep_per_prefix),
        "max_delete": int(max_delete),
        "ts_utc": utc_now_iso(),
        "actions": [a.__dict__ for a in actions],
        "summary": {
            "candidates_total": int(candidates_total),
            "planned_delete": int(len(planned)),
            "deleted": int(deleted),
            "failed": int(failed),
            "bytes_reclaimed": int(bytes_reclaimed),
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Cleanup orphaned RUN/*.tmp.* artifacts with retention guard.")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--run-rel", default="RUN")
    parser.add_argument("--min-age-sec", type=int, default=DEFAULT_MIN_AGE_SEC)
    parser.add_argument("--keep-per-prefix", type=int, default=DEFAULT_KEEP_PER_PREFIX)
    parser.add_argument("--max-delete", type=int, default=DEFAULT_MAX_DELETE)
    parser.add_argument("--evidence", default="")
    parser.add_argument("--apply", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    report = run_janitor(
        root,
        run_rel=str(args.run_rel),
        min_age_sec=max(0, int(args.min_age_sec)),
        keep_per_prefix=max(0, int(args.keep_per_prefix)),
        max_delete=max(0, int(args.max_delete)),
        apply=bool(args.apply),
    )

    if args.evidence:
        evidence_path = Path(args.evidence)
        if not evidence_path.is_absolute():
            evidence_path = (root / evidence_path).resolve()
        evidence_path.parent.mkdir(parents=True, exist_ok=True)
        evidence_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    summary = report["summary"]
    print(
        "RUN_TMP_JANITOR_OK candidates={0} planned={1} deleted={2} failed={3}".format(
            summary["candidates_total"],
            summary["planned_delete"],
            summary["deleted"],
            summary["failed"],
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
