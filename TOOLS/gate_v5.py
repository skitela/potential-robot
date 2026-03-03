# -*- coding: utf-8 -*-
"""
gate_v5.py — bramki PASS/FAIL dla warstwy operacyjnej i audytowej (v5).

Uwaga: to narzędzie NIE wykonuje autonomicznych napraw. Tylko:
- liczy i porównuje hasze,
- skanuje czystość,
- generuje dowody w EVIDENCE,
- raportuje PASS/FAIL.

Zakres skanowania:
- domyślnie: bieżący katalog repozytorium (ROOT = parent of this file)
- nie skanuje całego C:\\, tylko ROOT.

Wynik:
- kod 0 = PASS, kod 2 = FAIL
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from BIN import common_guards as cg  # noqa: E402

EXIT_PASS = 0
EXIT_FAIL = 2

FORBIDDEN_EXT = {".exe", ".bat", ".pyc", ".pyo"}
FORBIDDEN_DIR_NAMES = {"__pycache__"}

RE_LIKELY_SECRET = re.compile(
    r"(?i)(password|passwd|pwd|token|api[_-]?key|secret|bearer\s+[a-z0-9\-_\.]+)"
)

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def load_manifest(manifest_path: Path) -> Dict[str, str]:
    mapping: Dict[str, str] = {}
    if not manifest_path.exists():
        return mapping
    for line in manifest_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # format: <hash>  <relative_path>
        parts = line.split()
        if len(parts) < 2:
            continue
        h = parts[0]
        rel = " ".join(parts[1:]).strip()
        mapping[rel.replace("\\", "/")] = h.lower()
    return mapping

def compute_actual_hashes(root: Path, exclude_rel: List[str]) -> Dict[str, str]:
    mapping: Dict[str, str] = {}
    exclude_set = {p.replace("\\", "/") for p in exclude_rel}
    for p in root.rglob("*"):
        if p.is_file():
            rel = p.relative_to(root).as_posix()
            if rel in exclude_set:
                continue
            mapping[rel] = sha256_file(p).lower()
    return mapping

def scan_cleanliness(root: Path) -> List[str]:
    hits: List[str] = []
    for p in root.rglob("*"):
        if p.is_dir():
            if p.name in FORBIDDEN_DIR_NAMES:
                hits.append(p.relative_to(root).as_posix() + "/")
        elif p.is_file():
            if p.suffix.lower() in FORBIDDEN_EXT:
                hits.append(p.relative_to(root).as_posix())
    return sorted(set(hits))

def scan_secrets_in_text_files(root: Path, max_hits: int = 50) -> List[str]:
    hits: List[str] = []
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if p.suffix.lower() not in {".txt", ".json", ".py", ".toml", ".yaml", ".yml", ".md", ".ini", ".cfg"}:
            continue
        try:
            data = p.read_text(encoding="utf-8", errors="ignore")
        except Exception as e:
            cg.tlog(None, "WARN", "GATE_EXC", "nonfatal exception swallowed", e)
            continue
        if RE_LIKELY_SECRET.search(data):
            hits.append(p.relative_to(root).as_posix())
            if len(hits) >= max_hits:
                break
    return hits

def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)

def write_text(path: Path, text: str) -> None:
    ensure_dir(path.parent)
    path.write_text(text, encoding="utf-8", newline="\n")

def write_json(path: Path, obj: object) -> None:
    ensure_dir(path.parent)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="", help="Root projektu. Domyślnie: repo root.")
    ap.add_argument("--run-id", default="", help="Id przebiegu (opcjonalnie).")
    args = ap.parse_args()

    tool_root = Path(args.root).resolve() if args.root else Path(__file__).resolve().parents[1]
    run_id = args.run_id or datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")

    ev_root = tool_root / "EVIDENCE" / "gates"
    ensure_dir(ev_root)

    report_lines: List[str] = []
    status: Dict[str, str] = {}
    now_utc = datetime.now(timezone.utc).isoformat()

    # G0 — integrity by manifest
    manifest_path = tool_root / "MANIFEST.sha256"
    core_manifest_path = tool_root / "CORE" / "MANIFEST.sha256"
    exclude = ["MANIFEST.sha256", "CORE/MANIFEST.sha256"]
    actual = compute_actual_hashes(tool_root, exclude_rel=exclude)
    write_text(ev_root / f"manifest_actual_{run_id}.sha256",
               "\n".join([f"{h}  {rel}" for rel, h in sorted(actual.items())]) + "\n")

    expected = load_manifest(manifest_path)
    expected_core = load_manifest(core_manifest_path)

    g0_ok = True
    g0_reasons: List[str] = []
    if not expected:
        g0_ok = False
        g0_reasons.append("Brak MANIFEST.sha256 w root.")
    else:
        for rel, exp_hash in expected.items():
            if rel == "MANIFEST.sha256":
                continue
            act_hash = actual.get(rel)
            if act_hash != exp_hash:
                g0_ok = False
                g0_reasons.append(f"Mismatch: {rel}")
                break

    # core manifest checks (only within CORE subtree)
    if not expected_core:
        g0_ok = False
        g0_reasons.append("Brak CORE/MANIFEST.sha256.")
    else:
        for rel, exp_hash in expected_core.items():
            if rel == "MANIFEST.sha256":
                continue
            core_rel = f"CORE/{rel}" if not rel.startswith("CORE/") else rel
            act_hash = actual.get(core_rel)
            if act_hash != exp_hash:
                g0_ok = False
                g0_reasons.append(f"CORE mismatch: {core_rel}")
                break

    status["G0"] = "PASS" if g0_ok else "FAIL"

    # G1 — cleanliness
    clean_hits = scan_cleanliness(tool_root)
    write_text(ev_root / f"clean_scan_{run_id}.txt", "\n".join(clean_hits) + ("\n" if clean_hits else ""))
    status["G1"] = "PASS" if not clean_hits else "FAIL"

    # G3 — DIAG structure (static)
    latest = tool_root / "DIAG" / "bundles" / "LATEST"
    incidents = tool_root / "DIAG" / "bundles" / "INCIDENTS"
    required_files = ["error_bundle.json", "logs_snippet.txt", "env_snapshot.json", "gate_snapshot.txt"]
    g3_ok = latest.exists() and incidents.exists() and all((latest / f).exists() for f in required_files)
    status["G3"] = "PASS" if g3_ok else "FAIL"
    write_text(ev_root / f"diag_latest_{run_id}.txt",
               f"now_utc={now_utc}\nlatest={latest}\nincidents={incidents}\nrequired_ok={g3_ok}\n")

    # Secrets scan gate (fold into G1 logic: FAIL if secrets detected)
    secret_hits = scan_secrets_in_text_files(tool_root)
    write_text(ev_root / f"secrets_scan_{run_id}.txt", "\n".join(secret_hits) + ("\n" if secret_hits else ""))
    if secret_hits:
        # treat as FAIL
        status["SECRETS"] = "FAIL"
    else:
        status["SECRETS"] = "PASS"

    # Summary report
    report_lines.append(f"run_id={run_id}")
    report_lines.append(f"now_utc={now_utc}")
    report_lines.append(f"root={tool_root}")
    for k in sorted(status.keys()):
        report_lines.append(f"{k}={status[k]}")
    if g0_reasons:
        report_lines.append("G0_REASONS=" + "; ".join(g0_reasons))

    write_text(ev_root / f"gate_run_{run_id}.txt", "\n".join(report_lines) + "\n")

    # final decision
    must_pass = ["G0", "G1", "G3", "SECRETS"]
    ok = all(status.get(k) == "PASS" for k in must_pass)
    return EXIT_PASS if ok else EXIT_FAIL

if __name__ == "__main__":
    raise SystemExit(main())
