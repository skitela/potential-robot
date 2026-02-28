#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional


WINDOW_PHASE_RE = re.compile(r"WINDOW_PHASE\s+phase=([A-Z_]+)\s+window=([A-Z0-9_]+|NONE)")
DB_SUFFIXES = (".sqlite", ".db", ".sqlite3")


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def read_window_phase(safety_log: Path, *, tail_lines: int = 4000) -> Dict[str, str]:
    if not safety_log.exists():
        return {"phase": "UNKNOWN", "window": "NONE", "source": "missing_log"}
    try:
        lines = safety_log.read_text(encoding="utf-8", errors="ignore").splitlines()[-max(50, int(tail_lines)) :]
    except Exception:
        return {"phase": "UNKNOWN", "window": "NONE", "source": "read_error"}
    for line in reversed(lines):
        m = WINDOW_PHASE_RE.search(str(line))
        if m:
            return {"phase": str(m.group(1)).upper(), "window": str(m.group(2)).upper(), "source": "safetybot.log"}
    return {"phase": "UNKNOWN", "window": "NONE", "source": "not_found"}


def sqlite_file_list(db_root: Path) -> List[Path]:
    files: List[Path] = []
    if not db_root.exists():
        return files
    for p in db_root.iterdir():
        if p.is_file() and p.suffix.lower() in DB_SUFFIXES:
            files.append(p)
    files.sort(key=lambda x: x.name.lower())
    return files


def run_maintenance(
    db_path: Path,
    *,
    busy_timeout_ms: int,
    ensure_wal: bool,
    checkpoint_mode: str,
    run_optimize: bool,
) -> Dict[str, Any]:
    item: Dict[str, Any] = {
        "db_path": str(db_path),
        "status": "UNKNOWN",
        "journal_mode_before": "UNKNOWN",
        "journal_mode_after": "UNKNOWN",
        "wal_checkpoint": None,
        "page_count": "UNKNOWN",
        "freelist_count": "UNKNOWN",
        "error": "",
    }
    conn: Optional[sqlite3.Connection] = None
    try:
        conn = sqlite3.connect(str(db_path), timeout=max(1.0, float(busy_timeout_ms) / 1000.0), isolation_level=None, check_same_thread=False)
        conn.execute(f"PRAGMA busy_timeout={max(1, int(busy_timeout_ms))};")
        try:
            item["journal_mode_before"] = str(conn.execute("PRAGMA journal_mode;").fetchone()[0]).upper()
        except Exception:
            item["journal_mode_before"] = "UNKNOWN"

        if bool(ensure_wal):
            try:
                item["journal_mode_after"] = str(conn.execute("PRAGMA journal_mode=WAL;").fetchone()[0]).upper()
            except Exception:
                item["journal_mode_after"] = "UNKNOWN"
        else:
            item["journal_mode_after"] = item["journal_mode_before"]

        cp_mode = str(checkpoint_mode or "PASSIVE").upper()
        cp_row = conn.execute(f"PRAGMA wal_checkpoint({cp_mode});").fetchone()
        if isinstance(cp_row, tuple):
            item["wal_checkpoint"] = list(cp_row)
        else:
            item["wal_checkpoint"] = cp_row

        if bool(run_optimize):
            try:
                conn.execute("PRAGMA optimize;")
            except Exception:
                pass

        try:
            item["page_count"] = int(conn.execute("PRAGMA page_count;").fetchone()[0])
        except Exception:
            item["page_count"] = "UNKNOWN"
        try:
            item["freelist_count"] = int(conn.execute("PRAGMA freelist_count;").fetchone()[0])
        except Exception:
            item["freelist_count"] = "UNKNOWN"
        item["status"] = "PASS"
        return item
    except Exception as exc:
        item["status"] = "FAIL"
        item["error"] = f"{type(exc).__name__}: {exc}"
        return item
    finally:
        if conn is not None:
            try:
                conn.close()
            except Exception:
                pass


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Runtime-safe SQLite maintenance (WAL checkpoint + optimize).")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--db-root", default="DB")
    ap.add_argument("--safety-log", default="LOGS/safetybot.log")
    ap.add_argument("--allow-active", action="store_true", help="Allow maintenance during ACTIVE window phase.")
    ap.add_argument("--busy-timeout-ms", type=int, default=5000)
    ap.add_argument("--ensure-wal", action="store_true", default=True)
    ap.add_argument("--checkpoint-mode", default="PASSIVE", choices=["PASSIVE", "FULL", "RESTART", "TRUNCATE"])
    ap.add_argument("--run-optimize", action="store_true", default=True)
    ap.add_argument("--out", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    db_root = (root / str(args.db_root)).resolve()
    safety_log = (root / str(args.safety_log)).resolve()
    phase = read_window_phase(safety_log)

    report: Dict[str, Any] = {
        "schema": "oanda_mt5.sqlite_maintenance.v1",
        "ts_utc": utc_now_iso(),
        "root": str(root),
        "db_root": str(db_root),
        "window_phase": phase,
        "allow_active": bool(args.allow_active),
        "checkpoint_mode": str(args.checkpoint_mode).upper(),
        "busy_timeout_ms": int(max(1, int(args.busy_timeout_ms))),
        "results": [],
        "status": "PASS",
    }

    if (not bool(args.allow_active)) and str(phase.get("phase") or "").upper() == "ACTIVE":
        report["status"] = "SKIP_ACTIVE"
    else:
        db_files = sqlite_file_list(db_root)
        for db_file in db_files:
            result = run_maintenance(
                db_file,
                busy_timeout_ms=int(max(1, int(args.busy_timeout_ms))),
                ensure_wal=bool(args.ensure_wal),
                checkpoint_mode=str(args.checkpoint_mode).upper(),
                run_optimize=bool(args.run_optimize),
            )
            report["results"].append(result)
        if any(str(r.get("status")) == "FAIL" for r in report["results"]):
            report["status"] = "PARTIAL_FAIL"
        else:
            report["status"] = "PASS"

    out_path: Path
    if str(args.out or "").strip():
        out_path = Path(str(args.out))
        if not out_path.is_absolute():
            out_path = (root / out_path).resolve()
    else:
        out_dir = (root / "EVIDENCE" / "housekeeping").resolve()
        out_dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        out_path = out_dir / f"sqlite_maintenance_{stamp}.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"SQLITE_MAINTENANCE_DONE status={report['status']} dbs={len(report['results'])} out={out_path}")
    return 0 if str(report["status"]) in {"PASS", "SKIP_ACTIVE"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
