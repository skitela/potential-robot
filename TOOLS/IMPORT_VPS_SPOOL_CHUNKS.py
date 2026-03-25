#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
from collections import Counter
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import gotowe chunki spoola VPS do lokalnego inboxu research.")
    parser.add_argument(
        "--source-root",
        default=r"C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\spool",
    )
    parser.add_argument("--inbox-root", default=r"C:\TRADING_DATA\RESEARCH\vps_spool_inbox")
    parser.add_argument("--state-path", default=r"C:\TRADING_DATA\RESEARCH\reports\vps_spool_sync_state_latest.json")
    parser.add_argument("--output-json", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\vps_spool_sync_latest.json")
    parser.add_argument("--latest-md", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\vps_spool_sync_latest.md")
    return parser.parse_args()


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def read_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def atomic_copy(source: Path, destination: Path) -> None:
    ensure_dir(destination.parent)
    temp_path = destination.with_suffix(destination.suffix + ".tmp")
    shutil.copy2(source, temp_path)
    temp_path.replace(destination)


def write_report(report: dict[str, Any], output_json: Path, latest_md: Path) -> None:
    ensure_dir(output_json.parent)
    output_json.write_text(json.dumps(report, indent=2, ensure_ascii=True), encoding="utf-8")

    lines = [
        "# VPS Spool Sync",
        "",
        f"- ok: {report['ok']}",
        f"- source_root: {report['source_root']}",
        f"- inbox_root: {report['inbox_root']}",
        f"- ready_files: {report['ready_file_count']}",
        f"- copied_chunks: {report['copied_chunk_count']}",
        f"- reused_chunks: {report['reused_chunk_count']}",
        f"- missing_data: {report['missing_data_count']}",
        f"- missing_manifest: {report['missing_manifest_count']}",
    ]
    if report.get("streams"):
        lines.append("")
        lines.append("## Strumienie")
        for stream_name, count in sorted(report["streams"].items()):
            lines.append(f"- {stream_name}: {count}")
    ensure_dir(latest_md.parent)
    latest_md.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    args = parse_args()
    source_root = Path(args.source_root)
    inbox_root = Path(args.inbox_root)
    state_path = Path(args.state_path)
    output_json = Path(args.output_json)
    latest_md = Path(args.latest_md)

    state = read_json(state_path)
    known_chunks: dict[str, Any] = state.get("chunks", {}) if isinstance(state.get("chunks"), dict) else {}

    report: dict[str, Any] = {
        "schema_version": "1.0",
        "ts_local": __import__("datetime").datetime.now().astimezone().isoformat(),
        "ok": True,
        "source_root": str(source_root),
        "inbox_root": str(inbox_root),
        "state_path": str(state_path),
        "ready_file_count": 0,
        "copied_chunk_count": 0,
        "reused_chunk_count": 0,
        "missing_data_count": 0,
        "missing_manifest_count": 0,
        "streams": {},
        "chunks_copied": [],
        "chunks_reused": [],
        "chunks_missing_data": [],
        "chunks_missing_manifest": [],
    }

    if not source_root.exists():
        ensure_dir(state_path.parent)
        state_path.write_text(
            json.dumps(
                {
                    "schema_version": "1.0",
                    "ts_local": report["ts_local"],
                    "source_root": str(source_root),
                    "inbox_root": str(inbox_root),
                    "chunks": known_chunks,
                },
                indent=2,
                ensure_ascii=True,
            ),
            encoding="utf-8",
        )
        write_report(report, output_json, latest_md)
        return 0

    stream_counter: Counter[str] = Counter()
    ready_files = sorted(source_root.rglob("*.ready"))
    report["ready_file_count"] = len(ready_files)

    for ready_path in ready_files:
        data_path = Path(str(ready_path)[: -len(".ready")])
        manifest_path = Path(str(data_path) + ".manifest.json")
        if not data_path.exists():
            report["missing_data_count"] += 1
            report["chunks_missing_data"].append(str(ready_path))
            continue
        if not manifest_path.exists():
            report["missing_manifest_count"] += 1
            report["chunks_missing_manifest"].append(str(data_path))
            continue

        rel_path = data_path.relative_to(source_root)
        chunk_key = rel_path.as_posix()
        stat = data_path.stat()
        stream_name = rel_path.parts[0] if rel_path.parts else "UNKNOWN"
        stream_counter[stream_name] += 1

        previous = known_chunks.get(chunk_key, {})
        unchanged = (
            int(previous.get("size", -1)) == int(stat.st_size)
            and int(previous.get("mtime_ns", -1)) == int(stat.st_mtime_ns)
        )

        inbox_data_path = inbox_root / rel_path
        inbox_manifest_path = Path(str(inbox_data_path) + ".manifest.json")
        inbox_ready_path = Path(str(inbox_data_path) + ".ready")

        if unchanged and inbox_data_path.exists() and inbox_manifest_path.exists():
            report["reused_chunk_count"] += 1
            report["chunks_reused"].append(chunk_key)
            continue

        atomic_copy(data_path, inbox_data_path)
        atomic_copy(manifest_path, inbox_manifest_path)
        ensure_dir(inbox_ready_path.parent)
        inbox_ready_path.write_text("", encoding="ascii")

        known_chunks[chunk_key] = {
            "size": int(stat.st_size),
            "mtime_ns": int(stat.st_mtime_ns),
            "source_path": str(data_path),
            "manifest_path": str(manifest_path),
            "inbox_path": str(inbox_data_path),
            "stream": stream_name,
            "copied_at": report["ts_local"],
        }
        report["copied_chunk_count"] += 1
        report["chunks_copied"].append(chunk_key)

    report["streams"] = dict(stream_counter)

    ensure_dir(state_path.parent)
    state_path.write_text(
        json.dumps(
            {
                "schema_version": "1.0",
                "ts_local": report["ts_local"],
                "source_root": str(source_root),
                "inbox_root": str(inbox_root),
                "chunks": known_chunks,
            },
            indent=2,
            ensure_ascii=True,
        ),
        encoding="utf-8",
    )
    write_report(report, output_json, latest_md)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
