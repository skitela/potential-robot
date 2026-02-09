# -*- coding: utf-8 -*-
"""pack_release.py — build a clean release ZIP for OANDA_MT5.

P0:
- deterministic archive (stable ordering)
- exclude build artifacts (dist/, build/, caches, *.egg-info)
- exclude runtime state (DB/*.sqlite, LOGS/*.log, META/*.json, etc.) — ship only .keep placeholders
- run tests + gate before and after packing
- no silent exceptions: each except logs via cg.tlog as first statement
"""

from __future__ import annotations

import json
import hashlib
from datetime import datetime, timezone
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import List, Set, Tuple

# Ensure project root is importable even when this script is executed from TOOLS/
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from BIN import common_guards as cg  # type: ignore


# Allowlist: what goes into the release ZIP (everything else is excluded).
ALLOWED_TOP_FILES: Set[str] = {
    "requirements.txt",
    "requirements-dev.txt",
    "pyproject.toml",
    "bandit.yaml",
    "RELEASE_META.json",
}
ALLOWED_DIRS_FULL: Set[str] = {"BIN", "TOOLS", "tests", "README"}

# Runtime dirs must exist, but only .keep placeholders are shipped (no state).
KEEP_ONLY_DIRS: Set[str] = {"DB", "DB_BACKUPS", "LOGS", "META", "LOCK", "RUN"}
KEEP_ONLY_FILENAMES: Set[str] = {".keep"}

# Explicitly excluded directories (even if someone adds them later).
EXCLUDE_DIRS: Set[str] = {
    "dist",
    "build",
    ".git",
    ".venv",
    "venv",
    "__pycache__",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
}


def _iter_allowed_files(root: Path) -> List[Path]:
    """Return absolute Paths to include in ZIP (deterministic order)."""
    out: List[Path] = []

    # Top-level files
    for name in sorted(ALLOWED_TOP_FILES):
        p = root / name
        if p.is_file():
            out.append(p)

    # Full dirs
    for d in sorted(ALLOWED_DIRS_FULL):
        dp = root / d
        if not dp.exists():
            continue
        for p in sorted(dp.rglob("*")):
            if p.is_dir():
                continue
            rel_parts = p.relative_to(root).parts
            if any(part in EXCLUDE_DIRS for part in rel_parts):
                continue
            if p.suffix in {".pyc", ".pyo"}:
                continue
            out.append(p)

    # Keep-only dirs: only .keep
    for d in sorted(KEEP_ONLY_DIRS):
        dp = root / d
        if not dp.exists():
            continue
        for p in sorted(dp.rglob("*")):
            if p.is_dir():
                continue
            if p.name in KEEP_ONLY_FILENAMES:
                out.append(p)

    # Unique
    uniq: List[Path] = []
    seen: Set[str] = set()
    for p in out:
        rp = str(p.resolve())
        if rp not in seen:
            seen.add(rp)
            uniq.append(p)
    return uniq


def _clean_pycache(root: Path) -> None:
    """Remove bytecode and __pycache__ (P0)."""
    try:
        for p in root.rglob("__pycache__"):
            if p.is_dir():
                shutil.rmtree(p, ignore_errors=True)
        for p in root.rglob("*.pyc"):
            try:
                p.unlink()
            except Exception as e:
                cg.tlog(None, "WARN", "PACK_EXC", "nonfatal exception swallowed", e)
        for p in root.rglob("*.pyo"):
            try:
                p.unlink()
            except Exception as e:
                cg.tlog(None, "WARN", "PACK_EXC", "nonfatal exception swallowed", e)
    except Exception as e:
        cg.tlog(None, "WARN", "PACK_EXC", "nonfatal exception swallowed", e)


def _run(cmd: List[str], timeout_s: int = 900) -> int:
    """Run a subprocess with timeout; return exit code."""
    try:
        r = subprocess.run(cmd, cwd=str(ROOT), timeout=timeout_s, check=False)
        return int(r.returncode)
    except Exception as e:
        cg.tlog(None, "WARN", "PACK_EXC", "nonfatal exception swallowed", e)
        return 1


def _now_utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")


def _sha256_path(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _zip_add_tree(zf: zipfile.ZipFile, base_dir: Path, arc_prefix: str) -> None:
    # Deterministic: sorted paths, files only.
    for p in sorted(base_dir.rglob('*')):
        if p.is_dir():
            continue
        rel = p.relative_to(base_dir).as_posix()
        zf.write(str(p), arcname=f"{arc_prefix}/{rel}")


def build_release_zip(out_zip: Path) -> Path:
    """Create release ZIP at out_zip and return out_zip."""
    out_zip.parent.mkdir(parents=True, exist_ok=True)

    files = _iter_allowed_files(ROOT)

    try:
        if out_zip.exists():
            out_zip.unlink()
    except Exception as e:
        cg.tlog(None, "WARN", "PACK_EXC", "nonfatal exception swallowed", e)

    try:
        with zipfile.ZipFile(str(out_zip), "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for p in files:
                rel = p.relative_to(ROOT).as_posix()
                zf.write(str(p), arcname=rel)
    except Exception as e:
        cg.tlog(None, "ERROR", "PACK_FAIL", f"cannot build zip: {out_zip}", e)
        raise

    return out_zip


def _ensure_keep_dirs() -> None:
    try:
        for d in KEEP_ONLY_DIRS:
            dp = ROOT / d
            dp.mkdir(parents=True, exist_ok=True)
            kp = dp / ".keep"
            if not kp.exists():
                kp.write_text("", encoding="utf-8")
    except Exception as e:
        cg.tlog(None, "WARN", "PACK_EXC", "nonfatal exception swallowed", e)


def main() -> int:
    _clean_pycache(ROOT)
    _ensure_keep_dirs()

    dist_dir = ROOT / "dist"
    # Clean old build outputs before packing (P0 hygiene).
    try:
        if dist_dir.exists():
            shutil.rmtree(dist_dir, ignore_errors=True)
    except Exception as e:
        cg.tlog(None, "WARN", "PACK_EXC", "nonfatal exception swallowed", e)
    dist_dir.mkdir(parents=True, exist_ok=True)

    stamp = _now_utc_stamp()
    evidence_root = dist_dir / f"evidence_{stamp}"
    evidence_pre = evidence_root / "pre"
    evidence_post = evidence_root / "post"
    evidence_pre.mkdir(parents=True, exist_ok=True)
    evidence_post.mkdir(parents=True, exist_ok=True)

    # Pre-pack validation (gate includes unittest/compileall/bandit/pip-audit)
    rc = _run([sys.executable, "TOOLS/gate.py", "--mode", "release", "--evidence-dir", str(evidence_pre), "--evidence-id", f"pre_{stamp}"])
    if rc != 0:
        cg.tlog(None, "ERROR", "PACK_FAIL", "Gate failed.")
        return rc

    # Name ZIP from RELEASE_META.json to avoid ambiguity across iterations.
    out_name = "oanda_mt5_release.zip"
    try:
        meta = json.loads((ROOT / "RELEASE_META.json").read_text(encoding="utf-8"))
        rid = str(meta.get("release_id") or "").strip()
        ver = str(meta.get("release_version") or meta.get("version") or "").strip()
        if rid:
            out_name = f"{rid}.zip"
        elif ver:
            out_name = f"oanda_mt5_{ver}.zip"
    except Exception as e:
        cg.tlog(None, "WARN", "PACK_EXC", "nonfatal exception swallowed", e)

    out_zip = dist_dir / out_name
    build_release_zip(out_zip)

    zip_sha256 = _sha256_path(out_zip)

    # Post-pack validation includes ZIP scanning + evidence
    rc = _run([sys.executable, "TOOLS/gate.py", "--mode", "release", "--zip-only", "--zip", str(out_zip), "--evidence-dir", str(evidence_post), "--evidence-id", f"post_{stamp}"])
    if rc != 0:
        cg.tlog(None, "ERROR", "PACK_FAIL", "Gate (zip) failed.")
        return rc

    # Summary meta (lightweight)
    try:
        meta = json.loads((ROOT / "RELEASE_META.json").read_text(encoding="utf-8"))
    except Exception as e:
        cg.tlog(None, "WARN", "PACK_EXC", "cannot read RELEASE_META.json, using defaults", e)
        meta = {}
    audit_meta = {
        "id": str(meta.get("release_id") or out_zip.stem),
        "stamp_utc": stamp,
        "release_version": str(meta.get("release_version") or meta.get("version") or ""),
        "zip_name": out_zip.name,
        "zip_size_bytes": int(out_zip.stat().st_size),
        "zip_sha256": zip_sha256,
        "evidence_dir": str(evidence_root.relative_to(dist_dir)),
    }
    try:
        (dist_dir / "AUDIT_META.json").write_text(json.dumps(audit_meta, indent=2, sort_keys=True), encoding="utf-8")
    except Exception as e:
        cg.tlog(None, "WARN", "PACK_EXC", "nonfatal exception swallowed", e)

    

    # Build standalone evidence ZIP (AUDIT_META.json + evidence tree)
    try:
        audit_meta_path = dist_dir / 'AUDIT_META.json'
        evidence_zip = dist_dir / f"{out_zip.stem}_EVIDENCE.zip"
        if evidence_zip.exists():
            evidence_zip.unlink()
        with zipfile.ZipFile(str(evidence_zip), 'w', compression=zipfile.ZIP_DEFLATED) as zf:
            if audit_meta_path.exists():
                zf.write(str(audit_meta_path), arcname='AUDIT_META.json')
            if evidence_root.exists():
                _zip_add_tree(zf, evidence_root, evidence_root.name)
    except Exception as e:
        cg.tlog(None, 'WARN', 'PACK_EXC', 'nonfatal exception swallowed', e)

    # Embed audit artifacts into the release ZIP for single-file handoff
    try:
        audit_meta_path = dist_dir / 'AUDIT_META.json'
        with zipfile.ZipFile(str(out_zip), 'a', compression=zipfile.ZIP_DEFLATED) as zf:
            if audit_meta_path.exists():
                zf.write(str(audit_meta_path), arcname='AUDIT_META.json')
            if evidence_root.exists():
                _zip_add_tree(zf, evidence_root, f"EVIDENCE/{evidence_root.name}")
    except Exception as e:
        cg.tlog(None, 'WARN', 'PACK_EXC', 'nonfatal exception swallowed', e)

    cg.tlog(None, "INFO", "PACK_OK", f"built {out_zip.name} ({out_zip.stat().st_size} bytes) sha256={zip_sha256}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
