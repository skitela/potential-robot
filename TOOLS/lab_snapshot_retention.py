#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import shutil
from pathlib import Path
from typing import Any, Dict, List

try:
    from TOOLS.lab_guardrails import ensure_write_parent, resolve_lab_data_root
    from TOOLS.lab_registry import connect_registry, init_registry_schema, insert_job_run
except Exception:  # pragma: no cover
    from lab_guardrails import ensure_write_parent, resolve_lab_data_root
    from lab_registry import connect_registry, init_registry_schema, insert_job_run

UTC = dt.timezone.utc


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Retain LAB snapshots under LAB_DATA_ROOT/snapshots.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--keep-days", type=int, default=14)
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--out", default="")
    return ap.parse_args()


def _collect_snapshot_dirs(snapshots_root: Path, cutoff: dt.datetime) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    if not snapshots_root.exists():
        return rows
    for entry in sorted(snapshots_root.iterdir(), key=lambda p: p.name):
        if not entry.is_dir():
            continue
        mtime_utc = dt.datetime.fromtimestamp(entry.stat().st_mtime, tz=UTC)
        size_bytes = 0
        files_count = 0
        for p in entry.rglob("*"):
            if p.is_file():
                files_count += 1
                size_bytes += int(p.stat().st_size)
        rows.append(
            {
                "path": str(entry.resolve()),
                "name": entry.name,
                "mtime_utc": iso_utc(mtime_utc),
                "files_count": int(files_count),
                "size_bytes": int(size_bytes),
                "expired": bool(mtime_utc < cutoff),
            }
        )
    return rows


def main() -> int:
    args = parse_args()
    started = dt.datetime.now(tz=UTC)
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    keep_days = max(1, int(args.keep_days))
    cutoff = started - dt.timedelta(days=keep_days)
    run_id = f"SNAP_RET_{started.strftime('%Y%m%dT%H%M%SZ')}"

    out_path = (
        Path(args.out).resolve()
        if str(args.out).strip()
        else (lab_data_root / "reports" / "retention" / f"lab_snapshot_retention_{started.strftime('%Y%m%dT%H%M%SZ')}.json").resolve()
    )
    out_path = ensure_write_parent(out_path, root=root, lab_data_root=lab_data_root)
    pointer_json = ensure_write_parent(
        (root / "LAB" / "EVIDENCE" / "retention" / "lab_snapshot_retention_latest.json").resolve(),
        root=root,
        lab_data_root=lab_data_root,
    )
    pointer_txt = ensure_write_parent(
        (root / "LAB" / "EVIDENCE" / "retention" / "lab_snapshot_retention_latest.txt").resolve(),
        root=root,
        lab_data_root=lab_data_root,
    )
    registry_path = ensure_write_parent(
        (lab_data_root / "registry" / "lab_registry.sqlite").resolve(),
        root=root,
        lab_data_root=lab_data_root,
    )
    snapshots_root = (lab_data_root / "snapshots").resolve()

    conn = connect_registry(registry_path)
    init_registry_schema(conn)
    try:
        rows = _collect_snapshot_dirs(snapshots_root, cutoff)
        expired = [r for r in rows if bool(r["expired"])]
        removed_rows: List[Dict[str, Any]] = []
        removed_bytes = 0
        if bool(args.apply):
            for row in expired:
                p = Path(str(row["path"]))
                try:
                    shutil.rmtree(p)
                    removed_rows.append(row)
                    removed_bytes += int(row["size_bytes"])
                except Exception:
                    # Keep entry but mark as failed removal in report.
                    row_fail = dict(row)
                    row_fail["remove_error"] = "FAILED"
                    removed_rows.append(row_fail)
        status = "PASS"
        reason = "RETENTION_APPLIED" if bool(args.apply) else "DRY_RUN"

        finished = dt.datetime.now(tz=UTC)
        report: Dict[str, Any] = {
            "schema": "oanda_mt5.lab_snapshot_retention.v1",
            "run_id": run_id,
            "started_at_utc": iso_utc(started),
            "finished_at_utc": iso_utc(finished),
            "status": status,
            "reason": reason,
            "root": str(root),
            "lab_data_root": str(lab_data_root),
            "snapshots_root": str(snapshots_root),
            "keep_days": int(keep_days),
            "cutoff_utc": iso_utc(cutoff),
            "apply": bool(args.apply),
            "summary": {
                "snapshot_dirs_total": len(rows),
                "snapshot_dirs_expired": len(expired),
                "snapshot_dirs_removed": len(removed_rows) if bool(args.apply) else 0,
                "snapshot_bytes_removed": int(removed_bytes) if bool(args.apply) else 0,
            },
            "expired_items": expired,
            "removed_items": removed_rows if bool(args.apply) else [],
        }
        out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

        insert_job_run(
            conn,
            {
                "run_id": run_id,
                "run_type": "SNAPSHOT_RETENTION",
                "started_at_utc": report["started_at_utc"],
                "finished_at_utc": report["finished_at_utc"],
                "status": status,
                "source_type": "LAB_DATA_ROOT",
                "dataset_hash": "",
                "config_hash": "",
                "readiness": "N/A",
                "reason": reason,
                "evidence_path": str(out_path),
                "details_json": json.dumps(report["summary"], ensure_ascii=False),
            },
        )

        pointer_payload = {
            "schema": "oanda_mt5.lab_snapshot_retention.pointer.v1",
            "generated_at_utc": iso_utc(finished),
            "status": status,
            "reason": reason,
            "report_path": str(out_path),
            "summary": report["summary"],
        }
        pointer_json.write_text(json.dumps(pointer_payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        pointer_txt.write_text(
            "\n".join(
                [
                    "LAB_SNAPSHOT_RETENTION",
                    f"Status: {status}",
                    f"Reason: {reason}",
                    f"Keep days: {keep_days}",
                    f"Expired dirs: {report['summary']['snapshot_dirs_expired']}",
                    f"Removed dirs: {report['summary']['snapshot_dirs_removed']}",
                    f"Removed bytes: {report['summary']['snapshot_bytes_removed']}",
                    f"Report: {out_path}",
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        print(
            "LAB_SNAPSHOT_RETENTION_OK status={0} apply={1} removed_dirs={2} removed_bytes={3} out={4}".format(
                status,
                int(bool(args.apply)),
                int(report["summary"]["snapshot_dirs_removed"]),
                int(report["summary"]["snapshot_bytes_removed"]),
                str(out_path),
            )
        )
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

