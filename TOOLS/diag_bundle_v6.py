#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
diag_bundle_v6.py — create DIAG/bundles/LATEST and archive previous bundles to DIAG/bundles/INCIDENTS.

Contract (offline):
- Always overwrite DIAG/bundles/LATEST
- Always archive previous LATEST to INCIDENTS (timestamped)
- Produce 4 files in LATEST:
    env_snapshot.json
    gate_snapshot.txt
    logs_snippet.txt
    error_bundle.json
- Produce EVIDENCE/gates/offline_runtime_<id>.txt (paths + timestamps)
"""

from __future__ import annotations

import datetime as _dt
import json
import os
import re
import shutil
from pathlib import Path
from typing import Dict, List, Optional
from BIN import common_guards as cg  # type: ignore

ROOT = Path(__file__).resolve().parents[1]
LATEST = ROOT / "DIAG" / "bundles" / "LATEST"
INCIDENTS = ROOT / "DIAG" / "bundles" / "INCIDENTS"
EVIDENCE_DIR = ROOT / "EVIDENCE" / "gates"
LOGS_DIR = ROOT / "LOGS"
DOCS_DIR = ROOT / "DOCS"


def now_id() -> str:
    return _dt.datetime.now().strftime("%Y%m%d_%H%M%S")


def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def redact(text: str) -> str:
    # Conservative redaction: key-like assignments
    text = re.sub(r"(?i)\b(password|passwd|passphrase|api[_-]?key|secret|token)\b\s*[:=]\s*([^\s'\"\n]+)", r"\1=<REDACTED>", text)
    # Bearer tokens
    text = re.sub(r"(?i)\bAuthorization\b\s*[:=]\s*Bearer\s+[A-Za-z0-9\-_\.=]+", "Authorization: Bearer <REDACTED>", text)
    return text


def archive_previous_latest(run_id: str) -> Optional[Path]:
    if not LATEST.exists():
        return None
    # if LATEST is empty dir, still archive it (auditable history)
    incident_dir = INCIDENTS / f"incident_{run_id}"
    ensure_dir(incident_dir)
    for p in LATEST.glob("*"):
        if p.is_file():
            shutil.copy2(p, incident_dir / p.name)
    return incident_dir


def collect_logs_snippet(max_lines: int = 400) -> str:
    if not LOGS_DIR.exists():
        return "NO_LOGS_DIR"
    log_files = sorted([p for p in LOGS_DIR.glob("*.log") if p.is_file()], key=lambda x: x.stat().st_mtime, reverse=True)
    if not log_files:
        return "NO_LOG_FILES"
    newest = log_files[0]
    lines = newest.read_text(encoding="utf-8", errors="ignore").splitlines()[-max_lines:]
    return redact("\n".join(lines))


def collect_gate_snapshot() -> str:
    # Prefer the newest evidence file, but do not require it.
    if not EVIDENCE_DIR.exists():
        return "NO_EVIDENCE_DIR"
    evidence = sorted([p for p in EVIDENCE_DIR.glob("*.txt") if p.is_file()], key=lambda x: x.stat().st_mtime, reverse=True)
    if not evidence:
        return "NO_GATE_EVIDENCE_FILES"
    newest = evidence[0]
    head = newest.read_text(encoding="utf-8", errors="ignore")
    return f"LATEST_EVIDENCE_FILE: {newest.name}\n\n" + redact(head[:8000])


def env_snapshot() -> Dict[str, object]:
    ts = _dt.datetime.now().isoformat()
    return {
        "timestamp": ts,
        "root": str(ROOT).replace("\\", "/"),
        "os_name": os.name,
        "python": {
            "version": os.sys.version,
        },
        "offline": True,
        "note": "OFFLINE diagnostic bundle; no network/KEY assumptions.",
    }


def error_bundle() -> Dict[str, object]:
    # Minimal offline bundle; detailed runtime errors live in LOGS.
    return {
        "timestamp": _dt.datetime.now().isoformat(),
        "errors": [],
        "note": "Populate from runtime incidents when ONLINE is enabled. OFFLINE run keeps this empty by design.",
        "do_weryfikacji_online": [
            "MT5/KEY/network dependent validations",
        ],
    }


def write_offline_runtime_evidence(run_id: str, incident_dir: Optional[Path]) -> Path:
    ensure_dir(EVIDENCE_DIR)
    out = EVIDENCE_DIR / f"offline_runtime_{run_id}.txt"
    latest_files = ["env_snapshot.json", "gate_snapshot.txt", "logs_snippet.txt", "error_bundle.json"]
    lines: List[str] = []
    lines.append("GATE: offline_runtime")
    lines.append("MODE: OFFLINE")
    lines.append("RESULT: PASS (bundle created)")
    lines.append("")
    latest_str = str(LATEST).replace("\\", "/")
    lines.append(f"DIAG/LATEST: {latest_str}")
    for fn in latest_files:
        p = LATEST / fn
        if p.exists():
            st = p.stat()
            lines.append(f"- {fn} size={st.st_size} mtime={_dt.datetime.fromtimestamp(st.st_mtime).isoformat()}")
        else:
            lines.append(f"- {fn} MISSING")
    lines.append("")
    if incident_dir:
        incident_str = str(incident_dir).replace("\\", "/")
        lines.append(f"ARCHIVE: {incident_str}")
    else:
        lines.append("ARCHIVE: none (no previous LATEST)")
    out.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return out


def main() -> int:
    run_id = now_id()

    ensure_dir(LATEST)
    ensure_dir(INCIDENTS)

    incident_dir = archive_previous_latest(run_id)

    # Marker used by gate_v6 diag_latest_check (tri-state: SKIP_PRE_DIAG vs PASS/FAIL)
    (LATEST / ".diag_ran").write_text(run_id + "\n", encoding="utf-8")

    # Create / overwrite LATEST files
    (LATEST / "env_snapshot.json").write_text(json.dumps(env_snapshot(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (LATEST / "gate_snapshot.txt").write_text(collect_gate_snapshot() + "\n", encoding="utf-8")
    (LATEST / "logs_snippet.txt").write_text(collect_logs_snippet() + "\n", encoding="utf-8")
    (LATEST / "error_bundle.json").write_text(json.dumps(error_bundle(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # Always archive the newly created snapshot as well
    incident_new = INCIDENTS / f"incident_{run_id}_LATEST"
    ensure_dir(incident_new)
    for p in LATEST.glob("*"):
        shutil.copy2(p, incident_new / p.name)

    # Offline runtime evidence (required)
    write_offline_runtime_evidence(run_id, incident_dir)

    cg.tlog(None, "INFO", "DIAG_CREATED", f"DIAG bundle created. run_id={run_id}")
    cg.tlog(None, "INFO", "DIAG_PATHS", f"LATEST: {LATEST}")
    cg.tlog(None, "INFO", "DIAG_PATHS", f"INCIDENTS: {INCIDENTS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
