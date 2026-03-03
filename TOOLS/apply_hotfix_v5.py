# -*- coding: utf-8 -*-
r"""
apply_hotfix_v5.py — aktywacja HOTFIX przez operatora (human-in-the-loop).

Gwarancje:
- NIE zapisuje do CORE.
- NIE uruchamia się sam.
- NIE wykonuje autonomicznych napraw.
- Zapisuje dowody do EVIDENCE\\hotfix_records\\.

Użycie:
python TOOLS\\apply_hotfix_v5.py --root C:\\OANDA_MT5_SYSTEM --hotfix-id HF_20260204_1320
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List

FORBIDDEN_EXT = {".exe", ".bat", ".pyc", ".pyo"}
MANIFEST_NAME = "HOTFIX_MANIFEST.sha256"
RECORD_NAME = "HOTFIX_RECORD.txt"
HEALTH_CHECK_NAME = "health_check.py"

def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)

def write_json(path: Path, obj: object) -> None:
    ensure_dir(path.parent)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def parse_manifest_sha256(path: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    if not path.exists():
        return entries
    data = path.read_text(encoding="utf-8", errors="ignore")
    for line in data.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        digest = parts[0].strip().lower()
        relpath = " ".join(parts[1:]).strip().strip('"')
        relpath = relpath.replace("\\", "/")
        if relpath.startswith("./"):
            relpath = relpath[2:]
        if relpath.startswith("/"):
            relpath = relpath[1:]
        entries[relpath] = digest
    return entries

def verify_manifest_sha256(base_dir: Path, manifest: Path) -> tuple[bool, list[str]]:
    ok = True
    lines: list[str] = []
    base_dir_resolved = base_dir.resolve()
    entries = parse_manifest_sha256(manifest)
    for relpath, expected_hex in entries.items():
        candidate = base_dir / relpath
        try:
            file_path = candidate.resolve()
        except Exception:
            ok = False
            lines.append(f"RESOLVE_FAIL: {relpath}")
            continue
        try:
            file_path.relative_to(base_dir_resolved)
        except ValueError:
            ok = False
            lines.append(f"TRAVERSAL: {relpath}")
            continue
        if not file_path.exists():
            ok = False
            lines.append(f"MISS: {relpath}")
            continue
        got = sha256_file(file_path)
        if got.lower() != expected_hex.lower():
            ok = False
            lines.append(f"SHA_MISMATCH: {relpath} expected={expected_hex} got={got}")
    return ok, lines

def run_health_check(root: Path, hotfix_dir: Path) -> tuple[bool, str]:
    script = hotfix_dir / HEALTH_CHECK_NAME
    if not script.exists():
        return True, "SKIP (no health_check.py)"
    try:
        cp = subprocess.run(
            [sys.executable, "-B", str(script)],
            cwd=str(root),
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        out = (cp.stdout or "") + (cp.stderr or "")
        return (cp.returncode == 0), out.strip()[:4000]
    except Exception as e:
        return False, f"EXC:{type(e).__name__}:{e}"

def scan_forbidden(root: Path) -> List[str]:
    hits: List[str] = []
    for p in root.rglob("*"):
        if p.is_dir() and p.name == "__pycache__":
            hits.append(p.relative_to(root).as_posix() + "/")
        elif p.is_file() and p.suffix.lower() in FORBIDDEN_EXT:
            hits.append(p.relative_to(root).as_posix())
    return sorted(set(hits))

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="", help="Root projektu.")
    ap.add_argument("--hotfix-id", required=True, help="Id hotfixa (folder w HOTFIX/incoming).")
    args = ap.parse_args()

    root = Path(args.root).resolve() if args.root else Path(__file__).resolve().parents[1]
    now = datetime.now(timezone.utc)
    run_id = now.strftime("%Y%m%d_%H%M%S")
    hotfix_id = args.hotfix_id

    incoming = root / "HOTFIX" / "incoming" / hotfix_id
    active = root / "HOTFIX" / "active" / hotfix_id
    archive = root / "HOTFIX" / "archive" / hotfix_id

    record_path = root / "EVIDENCE" / "hotfix_records" / f"hotfix_record_{hotfix_id}.json"

    record: Dict[str, object] = {
        "hotfix_id": hotfix_id,
        "run_id": run_id,
        "started_at_utc": now.isoformat(),
        "status": "STARTED",
        "go_no_go": "PENDING",
        "blocking_issues": [],
        "checks": {},
        "paths": {
            "incoming": str(incoming),
            "active": str(active),
            "archive": str(archive),
        },
        "notes": [],
    }

    if not incoming.exists():
        record["status"] = "FAIL"
        record["go_no_go"] = "NO-GO"
        record["blocking_issues"].append("MISSING_INCOMING")
        record["notes"].append("Brak HOTFIX/incoming/<hotfix_id>.")
        write_json(record_path, record)
        return 2

    # safety: forbid any writes under CORE by policy
    if any("CORE/" in p.as_posix() for p in incoming.rglob("*") if p.is_file()):
        record["status"] = "FAIL"
        record["go_no_go"] = "NO-GO"
        record["blocking_issues"].append("CORE_PATH_FORBIDDEN")
        record["notes"].append("Hotfix zawiera ścieżki CORE/ — zakazane.")
        write_json(record_path, record)
        return 2

    # cleanliness scan on incoming
    hits = scan_forbidden(incoming)
    record["checks"]["cleanliness_incoming_hits"] = hits
    if hits:
        record["status"] = "FAIL"
        record["go_no_go"] = "NO-GO"
        record["blocking_issues"].append("FORBIDDEN_ARTEFACTS")
        record["notes"].append("Hotfix zawiera zabronione artefakty (exe/bat/pyc/pyo/__pycache__).")
        write_json(record_path, record)
        return 2

    # Optional hotfix record (human summary)
    rec_file = incoming / RECORD_NAME
    if rec_file.exists():
        try:
            txt = rec_file.read_text(encoding="utf-8", errors="ignore")
            record["notes"].append(f"HOTFIX_RECORD_PRESENT: {RECORD_NAME}")
            record["hotfix_record_preview"] = txt.strip()[:2000]
        except Exception:
            record["notes"].append("HOTFIX_RECORD_READ_FAIL")

    # Optional manifest verification for incoming
    manifest = incoming / MANIFEST_NAME
    if manifest.exists():
        ok, lines = verify_manifest_sha256(incoming, manifest)
        record["checks"]["manifest_incoming_ok"] = bool(ok)
        record["checks"]["manifest_incoming_issues"] = lines
        if not ok:
            record["status"] = "FAIL"
            record["go_no_go"] = "NO-GO"
            record["blocking_issues"].append("MANIFEST_INCOMING_FAIL")
            record["notes"].append("Hotfix manifest verification failed.")
            write_json(record_path, record)
            return 2
    else:
        record["checks"]["manifest_incoming_ok"] = "SKIP (missing HOTFIX_MANIFEST.sha256)"

    # archive previous active, if any
    if active.exists():
        ensure_dir(archive.parent)
        if archive.exists():
            shutil.rmtree(archive, ignore_errors=True)
        shutil.copytree(active, archive)

    # activate: replace active with incoming (copy, do not move incoming)
    if active.exists():
        shutil.rmtree(active, ignore_errors=True)
    shutil.copytree(incoming, active)

    # Optional health check after activation
    health_ok, health_info = run_health_check(root, incoming)
    record["checks"]["health_check_ok"] = bool(health_ok)
    if health_info:
        record["checks"]["health_check_info"] = health_info
    if not health_ok:
        record["status"] = "FAIL"
        record["go_no_go"] = "NO-GO"
        record["blocking_issues"].append("HEALTH_CHECK_FAIL")
        record["notes"].append("Health check failed after activation.")
        # rollback to previous active if available
        if archive.exists():
            if active.exists():
                shutil.rmtree(active, ignore_errors=True)
            shutil.copytree(archive, active)
            record["notes"].append("ROLLBACK_PERFORMED")
        record["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
        write_json(record_path, record)
        return 2

    # Optional gate run (post-activation)
    gate_tool = root / "TOOLS" / "gate_v6.py"
    if gate_tool.exists():
        try:
            cp = subprocess.run(
                [sys.executable, "-B", str(gate_tool), "--mode", "offline"],
                cwd=str(root),
                capture_output=True,
                text=True,
                timeout=300,
                check=False,
            )
            record["checks"]["gate_v6_exit_code"] = int(cp.returncode)
            if cp.returncode != 0:
                record["status"] = "FAIL"
                record["go_no_go"] = "NO-GO"
                record["blocking_issues"].append("GATES_FAIL")
                record["notes"].append("Post-activation gates failed.")
        except Exception as e:
            record["checks"]["gate_v6_exit_code"] = "ERROR"
            record["status"] = "FAIL"
            record["go_no_go"] = "NO-GO"
            record["blocking_issues"].append("GATES_ERROR")
            record["notes"].append(f"Post-activation gates error: {type(e).__name__}")
    else:
        record["status"] = "FAIL"
        record["go_no_go"] = "NO-GO"
        record["blocking_issues"].append("GATES_TOOL_MISSING")
        record["notes"].append("TOOLS/gate_v6.py missing; cannot assert GO.")

    if record["status"] != "FAIL":
        record["status"] = "PASS"
        record["go_no_go"] = "GO"
    record["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
    write_json(record_path, record)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
