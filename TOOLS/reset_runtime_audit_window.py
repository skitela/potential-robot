#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


UTC = timezone.utc


@dataclass(frozen=True)
class TargetLog:
    rel_path: str
    ts_keys: tuple[str, ...]


TARGETS: tuple[TargetLog, ...] = (
    TargetLog("LOGS/incident_journal.jsonl", ("ts_utc",)),
    TargetLog("LOGS/audit_trail.jsonl", ("timestamp_utc", "ts_utc")),
    TargetLog("LOGS/execution_telemetry_v2.jsonl", ("ts_utc", "timestamp_utc")),
)


def utc_now_iso() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def parse_iso_utc(raw: str) -> Optional[datetime]:
    txt = str(raw or "").strip()
    if not txt:
        return None
    try:
        if txt.endswith("Z"):
            txt = txt[:-1] + "+00:00"
        dt = datetime.fromisoformat(txt)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=UTC)
        return dt.astimezone(UTC)
    except Exception:
        return None


def atomic_write_lines(path: Path, lines: Iterable[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    data = "".join(f"{ln.rstrip()}\n" for ln in lines)
    tmp.write_text(data, encoding="utf-8")
    tmp.replace(path)


def split_lines_by_cutoff(path: Path, ts_keys: tuple[str, ...], cutoff_utc: datetime) -> Dict[str, Any]:
    if not path.exists():
        return {
            "exists": False,
            "total": 0,
            "kept": 0,
            "removed": 0,
            "malformed": 0,
            "kept_lines": [],
            "removed_lines": [],
        }

    raw_lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    kept: List[str] = []
    removed: List[str] = []
    malformed = 0
    for ln in raw_lines:
        row = str(ln or "").strip()
        if not row:
            continue
        ts: Optional[datetime] = None
        try:
            obj = json.loads(row)
            for key in ts_keys:
                if key in obj:
                    ts = parse_iso_utc(str(obj.get(key) or ""))
                    if ts is not None:
                        break
        except Exception:
            malformed += 1
            kept.append(row)
            continue
        if ts is None:
            malformed += 1
            kept.append(row)
            continue
        if ts < cutoff_utc:
            removed.append(row)
        else:
            kept.append(row)

    return {
        "exists": True,
        "total": len(raw_lines),
        "kept": len(kept),
        "removed": len(removed),
        "malformed": int(malformed),
        "kept_lines": kept,
        "removed_lines": removed,
    }


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description="Reset runtime audit window by archiving old incident/telemetry lines while preserving evidence."
    )
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--keep-minutes", type=int, default=30)
    ap.add_argument("--dry-run", action="store_true")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    keep_minutes = max(1, int(args.keep_minutes))
    now_utc = datetime.now(UTC)
    cutoff_utc = now_utc - timedelta(minutes=keep_minutes)
    stamp = now_utc.strftime("%Y%m%dT%H%M%SZ")

    pack_dir = (root / "EVIDENCE" / "runtime_resets" / f"audit_window_reset_{stamp}").resolve()
    run_status = (root / "RUN" / "runtime_audit_window_reset_last.json").resolve()

    files_summary: List[Dict[str, Any]] = []
    total_removed = 0
    total_kept = 0
    total_malformed = 0

    for target in TARGETS:
        path = (root / target.rel_path).resolve()
        split = split_lines_by_cutoff(path, target.ts_keys, cutoff_utc)
        row = {
            "path": str(path),
            "exists": bool(split["exists"]),
            "total": int(split["total"]),
            "kept": int(split["kept"]),
            "removed": int(split["removed"]),
            "malformed": int(split["malformed"]),
        }
        files_summary.append(row)
        total_removed += int(split["removed"])
        total_kept += int(split["kept"])
        total_malformed += int(split["malformed"])

        if not split["exists"]:
            continue
        if args.dry_run:
            continue

        pack_dir.mkdir(parents=True, exist_ok=True)
        removed_out = pack_dir / (path.name + ".removed.jsonl")
        kept_out = pack_dir / (path.name + ".kept.preview.jsonl")
        atomic_write_lines(removed_out, split["removed_lines"])
        # Keep small preview for quick audit without opening runtime log.
        atomic_write_lines(kept_out, split["kept_lines"][-200:])
        atomic_write_lines(path, split["kept_lines"])

    status: Dict[str, Any] = {
        "schema": "oanda_mt5.runtime_audit_window_reset.v1",
        "ts_utc": utc_now_iso(),
        "root": str(root),
        "keep_minutes": int(keep_minutes),
        "cutoff_utc": cutoff_utc.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "dry_run": bool(args.dry_run),
        "pack_dir": str(pack_dir) if not args.dry_run else "",
        "summary": {
            "files": files_summary,
            "total_removed_lines": int(total_removed),
            "total_kept_lines": int(total_kept),
            "total_malformed_kept": int(total_malformed),
        },
        "status": "PASS",
    }

    run_status.parent.mkdir(parents=True, exist_ok=True)
    run_status.write_text(json.dumps(status, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        "RUNTIME_AUDIT_WINDOW_RESET_DONE "
        f"status={status['status']} keep_minutes={keep_minutes} "
        f"removed={total_removed} kept={total_kept} out={run_status}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
