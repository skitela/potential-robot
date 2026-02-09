# -*- coding: utf-8 -*-
r"""
diag_collect_v5.py — tworzy DIAG bundle (LATEST + INCIDENTS) bez autonomicznych napraw.

Wykonuje:
- nadpisuje DIAG\\bundles\\LATEST\\ (4 pliki),
- archiwizuje kopię do DIAG\\bundles\\INCIDENTS\\incident_YYYYMMDD_HHMMSS\\,
- stosuje redakcję prostych wzorców sekretów w wycinku logów.

Nie wykonuje:
- żadnych zmian w CORE,
- żadnych hotfixów,
- żadnych restartów.

Użycie (operator):
python TOOLS\\diag_collect_v5.py --root C:\\OANDA_MT5_SYSTEM --severity CRITICAL --component safetybot
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import List

RE_LIKELY_SECRET = re.compile(
    r"(?i)(password|passwd|pwd|token|api[_-]?key|secret|bearer\s+[a-z0-9\-_\.]+)"
)


def redact(text: str) -> str:
    return RE_LIKELY_SECRET.sub("[REDACTED]", text or "")


def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def write_text(path: Path, text: str) -> None:
    ensure_dir(path.parent)
    path.write_text(text, encoding="utf-8", newline="\n")


def write_json(path: Path, obj: object) -> None:
    ensure_dir(path.parent)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def tail_lines(path: Path, n: int) -> List[str]:
    if n <= 0:
        return []
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        return lines[-n:]
    except Exception:
        return []


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="", help="Root repo (domyslnie: katalog projektu).")
    ap.add_argument("--release-id", default="", help="Release id (opcjonalnie).")
    ap.add_argument("--severity", default="CRITICAL")
    ap.add_argument("--component", default="safetybot")
    ap.add_argument("--summary", default="")
    ap.add_argument("--log-file", default="LOGS/safetybot.log", help="Relatywna sciezka do logu zrodlowego.")
    ap.add_argument("--tail", type=int, default=300, help="Ile ostatnich linii wziac.")
    args = ap.parse_args()

    root = Path(args.root).resolve() if args.root else Path(__file__).resolve().parents[1]
    release_id = args.release_id or "(unknown)"
    now = datetime.now(timezone.utc)
    run_id = now.strftime("%Y%m%d_%H%M%S")
    incident_id = "incident_" + now.strftime("%Y%m%d_%H%M%S")

    latest = root / "DIAG" / "bundles" / "LATEST"
    incidents_root = root / "DIAG" / "bundles" / "INCIDENTS"
    incident_dir = incidents_root / incident_id

    ensure_dir(latest)
    ensure_dir(incident_dir)

    src_log = root / args.log_file
    lines = tail_lines(src_log, int(args.tail))
    snippet = "\n".join([redact(l) for l in lines]) + ("\n" if lines else "")

    error_bundle = {
        "release_id": release_id,
        "run_id": run_id,
        "event_id": "",
        "severity": args.severity,
        "component": args.component,
        "summary": redact(args.summary),
        "first_seen_utc": "",
        "last_seen_utc": now.isoformat(),
        "counts": {"occurrences": 1},
        "redactions_applied": True,
    }
    env_snapshot = {
        "os": "Windows 11",
        "root": str(root),
        "key_label_expected": "OANDAKEY",
        "key_present": None,
        "time_utc": now.isoformat(),
        "time_warsaw": "",
    }

    write_json(latest / "error_bundle.json", error_bundle)
    write_text(latest / "logs_snippet.txt", snippet)
    write_json(latest / "env_snapshot.json", env_snapshot)
    write_text(latest / "gate_snapshot.txt", "")

    for fn in ["error_bundle.json", "logs_snippet.txt", "env_snapshot.json", "gate_snapshot.txt"]:
        shutil.copy2(latest / fn, incident_dir / fn)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
