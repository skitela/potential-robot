#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple


FORBIDDEN_RUNTIME_WRITE_DIRS = (
    "BIN",
    "MQL5",
    "RUN",
    "LOGS",
    "DB",
    "META",
    "CONFIG",
    "OANDAKEY",
    "OBSERVERS_IMPLEMENTATION_CANDIDATE",
)

ALLOWED_REPO_WRITE_DIRS = (
    "LAB",
    "DOCS",
    "SCHEMAS",
    "tests",
)


def resolve_lab_data_root(root: Path) -> Path:
    env = str(os.environ.get("LAB_DATA_ROOT") or "").strip()
    if env:
        p = Path(env).expanduser()
    else:
        # External by default to keep heavy LAB artifacts outside repo.
        p = Path("C:/OANDA_MT5_LAB_DATA")
    if not p.is_absolute():
        p = (root / p).resolve()
    return p.resolve()


def normalize_path(path: Path) -> Path:
    return path.expanduser().resolve()


def _is_subpath(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except Exception:
        return False


def get_forbidden_write_roots(root: Path) -> List[Path]:
    out: List[Path] = []
    for rel in FORBIDDEN_RUNTIME_WRITE_DIRS:
        out.append((root / rel).resolve())
    return out


def get_allowed_write_roots(root: Path, lab_data_root: Path) -> List[Path]:
    out: List[Path] = [normalize_path(lab_data_root)]
    for rel in ALLOWED_REPO_WRITE_DIRS:
        out.append((root / rel).resolve())
    return out


def ensure_allowed_write(path: Path, *, root: Path, lab_data_root: Path) -> None:
    target = normalize_path(path)
    allowed = get_allowed_write_roots(root, lab_data_root)
    forbidden = get_forbidden_write_roots(root)

    if not any(_is_subpath(target, a) for a in allowed):
        raise PermissionError(f"LAB_WRITE_BLOCKED target outside allowed roots: {target}")
    if any(_is_subpath(target, f) for f in forbidden):
        raise PermissionError(f"LAB_WRITE_BLOCKED target inside forbidden runtime root: {target}")


def ensure_write_parent(path: Path, *, root: Path, lab_data_root: Path) -> Path:
    p = normalize_path(path)
    ensure_allowed_write(p, root=root, lab_data_root=lab_data_root)
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def canonical_json_hash(payload: Dict[str, Any]) -> str:
    data = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def read_write_matrix(root: Path, lab_data_root: Path) -> Dict[str, Any]:
    return {
        "read_paths": [
            str((root / "DB" / "decision_events.sqlite").resolve()),
            str((root / "DB" / "m5_bars.sqlite").resolve()),
            str((root / "CONFIG" / "strategy.json").resolve()),
            str((root / "EVIDENCE" / "bridge_audit").resolve()),
            str((root / "EVIDENCE").resolve()),
        ],
        "write_paths_allowed": [str(p) for p in get_allowed_write_roots(root, lab_data_root)],
        "write_paths_forbidden_runtime": [str(p) for p in get_forbidden_write_roots(root)],
    }


def classify_write_targets(targets: Iterable[Path], *, root: Path, lab_data_root: Path) -> List[Tuple[str, str]]:
    out: List[Tuple[str, str]] = []
    for t in targets:
        p = normalize_path(t)
        try:
            ensure_allowed_write(p, root=root, lab_data_root=lab_data_root)
            out.append((str(p), "ALLOWED"))
        except Exception as exc:
            out.append((str(p), f"BLOCKED:{type(exc).__name__}"))
    return out
