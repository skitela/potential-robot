# -*- coding: utf-8 -*-
r"""runtime_root.py — V6.2 hard-root + run-mode policy (P0)

Kontrakt:
- Windows: jedyny dozwolony root to C:\\OANDA_MT5_SYSTEM (bez wyjątków).
- Tryb LIVE jest możliwy wyłącznie, gdy bootstrap ustawi OANDA_RUN_MODE=LIVE.
- LIVE: terminal OANDA MT5 jest hard requirement i ma failować natychmiast, zanim spróbujemy connect.
- OFFLINE: dopuszczalny (analizy/diag), ale status MT5 musi być jawnie raportowany w EVIDENCE.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Literal

try:
    from . import common_guards as cg
except Exception:  # pragma: no cover
    import common_guards as cg

HARD_ROOT_WIN = Path(r"C:\OANDA_MT5_SYSTEM")
REQUIRED_OANDA_MT5_EXE = Path(r"C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe")

RunMode = Literal["OFFLINE", "LIVE"]

def _norm(p: Path) -> Path:
    # Resolve without requiring existence.
    try:
        return p.resolve()
    except Exception:
        cg.tlog(None, "WARN", "RR_EXC", "nonfatal exception swallowed")
        return Path(os.path.abspath(str(p)))

def get_run_mode() -> RunMode:
    v = (os.environ.get("OANDA_RUN_MODE") or "OFFLINE").strip().upper()
    return "LIVE" if v == "LIVE" else "OFFLINE"

def get_runtime_root(*, enforce: bool = True) -> Path:
    """Return runtime root.

    Windows:
      - Enforce HARD_ROOT_WIN.
      - OANDA_MT5_ROOT override is allowed only if it equals HARD_ROOT_WIN exactly (case-insensitive).
      - If enforce=True and code is not executed from within HARD_ROOT_WIN -> FAIL.

    Non-Windows:
      - Return repo root inferred from this file (allows offline auditing).
    """
    if os.name != "nt":
        # allow offline audit runs in non-Windows environments
        return _norm(Path(__file__).resolve().parents[1])

    expected = _norm(HARD_ROOT_WIN)

    env_root = os.environ.get("OANDA_MT5_ROOT")
    if env_root:
        envp = _norm(Path(env_root))
        if str(envp).lower().rstrip("\\/") != str(expected).lower().rstrip("\\/"):
            raise RuntimeError(f"HARD_ROOT_FAIL: OANDA_MT5_ROOT={env_root} (expected {expected})")

    # Ensure current code location is under the expected root
    if enforce:
        here = _norm(Path(__file__).resolve())
        if str(here).lower().startswith(str(expected).lower()):
            pass
        else:
            raise RuntimeError(f"HARD_ROOT_FAIL: executing from {here} (expected under {expected})")

    # Normalize env for child processes (process-local)
    os.environ["OANDA_MT5_ROOT"] = str(expected)
    return expected

def require_live_oanda_terminal() -> Path:
    """LIVE: terminal OANDA MT5 is mandatory. Fail-fast."""
    exe = REQUIRED_OANDA_MT5_EXE
    if not exe.is_file():
        raise RuntimeError(f"LIVE_MT5_FAIL: missing required terminal: {exe}")
    return exe

def project_paths(root: Path) -> dict[str, Path]:
    return {
        "root": root,
        "bin": root / "BIN",
        "meta": root / "META",
        "db": root / "DB",
        "logs": root / "LOGS",
        "run": root / "RUN",
        "backups": root / "DB_BACKUPS",
        "lock": root / "LOCK",
        "evidence": root / "EVIDENCE",
        "diag": root / "DIAG",
    }

def ensure_dirs(paths: dict[str, Path]) -> None:
    for k, p in paths.items():
        if k in ("root",):
            continue
        p.mkdir(parents=True, exist_ok=True)
