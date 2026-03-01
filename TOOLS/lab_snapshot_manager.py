#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import sqlite3
from pathlib import Path
from typing import Dict, Tuple

try:
    from TOOLS.lab_guardrails import ensure_write_parent, resolve_lab_data_root
except Exception:  # pragma: no cover
    from lab_guardrails import ensure_write_parent, resolve_lab_data_root

UTC = dt.timezone.utc


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def sqlite_backup(src: Path, dst: Path) -> Tuple[bool, str]:
    try:
        dst.parent.mkdir(parents=True, exist_ok=True)
        with sqlite3.connect(f"file:{src}?mode=ro", uri=True, timeout=10) as s_conn:
            with sqlite3.connect(str(dst), timeout=10) as d_conn:
                s_conn.backup(d_conn)
                d_conn.commit()
        return True, "OK"
    except Exception as exc:
        return False, f"{type(exc).__name__}:{exc}"


def make_snapshots(root: Path, lab_data_root: Path) -> Dict[str, Dict[str, str]]:
    ts = dt.datetime.now(tz=UTC).strftime("%Y%m%dT%H%M%SZ")
    snap_dir = (lab_data_root / "snapshots" / ts).resolve()
    snap_dir.mkdir(parents=True, exist_ok=True)

    sources = {
        "decision_events": (root / "DB" / "decision_events.sqlite").resolve(),
        "m5_bars": (root / "DB" / "m5_bars.sqlite").resolve(),
    }
    results: Dict[str, Dict[str, str]] = {}
    for key, src in sources.items():
        dst = ensure_write_parent(snap_dir / f"{key}.sqlite", root=root, lab_data_root=lab_data_root)
        if not src.exists():
            results[key] = {"status": "MISSING_SOURCE", "source": str(src), "snapshot": str(dst)}
            continue
        ok, note = sqlite_backup(src, dst)
        results[key] = {
            "status": "OK" if ok else "FAILED",
            "source": str(src),
            "snapshot": str(dst),
            "note": note,
        }
    return results


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Create LAB sqlite snapshots from runtime DB (read-only source).")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--out", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)

    results = make_snapshots(root=root, lab_data_root=lab_data_root)
    status = "PASS" if all(v.get("status") == "OK" for v in results.values()) else "PARTIAL"
    report = {
        "schema": "oanda_mt5.lab_snapshot_manager.v1",
        "generated_at_utc": iso_utc(dt.datetime.now(tz=UTC)),
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "results": results,
        "status": status,
    }

    if str(args.out).strip():
        out_path = Path(args.out)
        if not out_path.is_absolute():
            out_path = (root / out_path).resolve()
    else:
        out_path = (lab_data_root / "reports" / "snapshots" / f"lab_snapshot_report_{dt.datetime.now(tz=UTC).strftime('%Y%m%dT%H%M%SZ')}.json").resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"LAB_SNAPSHOT_MANAGER_DONE status={status} out={out_path}")
    return 0 if status in {"PASS", "PARTIAL"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
