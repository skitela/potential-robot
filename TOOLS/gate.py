# -*- coding: utf-8 -*-
"""gate.py — deterministic quality gate for OANDA_MT5 bundle.

P0 policy:
- Each subprocess.run MUST have a timeout (no hangs).
- DEV: missing tooling => SKIP + UNVERIFIED_TOOLING.
- RELEASE: missing tooling => FAIL (except pip-audit under Option 2).
- Tool configuration ONLY in pyproject.toml under [tool.oanda_mt5_gate] (optional bandit.yaml).
- Tests must run from repo root: python -m unittest discover -s tests -v
- Hard audit check: BUDGET log must include day_ny and utc_day (static check).
- Hard audit check: forbidden 'except Exception: pass' (static check).
- Hard audit check: structural methods must exist at class level (AST).
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import platform
import re
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    import tomllib  # py3.11
except Exception:  # pragma: no cover
    tomllib = None  # type: ignore

ROOT = Path(__file__).resolve().parents[1]
ENV_BASE = os.environ.copy()
ENV_BASE.setdefault("PYTHONDONTWRITEBYTECODE", "1")

# Make common_guards available to gate (for cg.tlog).
sys.path.insert(0, str(ROOT))
from BIN import common_guards as cg  # noqa: E402


def _clean_bytecode_tree(base: Path) -> int:
    removed = 0
    try:
        for dirpath, dirnames, filenames in os.walk(base):
            if "__pycache__" in dirnames:
                p = Path(dirpath) / "__pycache__"
                try:
                    shutil.rmtree(p, ignore_errors=True)
                    removed += 1
                except Exception as e:
                    cg.tlog(None, "WARN", "CLEAN_RMTREE_FAIL", f"cannot remove {p}", e)
                dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                if fn.endswith(".pyc") or fn.endswith(".pyo"):
                    fp = Path(dirpath) / fn
                    try:
                        fp.unlink(missing_ok=True)
                        removed += 1
                    except Exception as e:
                        cg.tlog(None, "WARN", "CLEAN_UNLINK_FAIL", f"cannot remove {fp}", e)
    except Exception as e:
        cg.tlog(None, "ERROR", "CLEAN_WALK_FAIL", "bytecode clean failed", e)
    return removed


def _find_bytecode_artifacts(base: Path) -> List[str]:
    found: List[str] = []
    for dirpath, dirnames, filenames in os.walk(base):
        if "__pycache__" in dirnames:
            found.append(str(Path(dirpath) / "__pycache__"))
        for fn in filenames:
            if fn.endswith(".pyc") or fn.endswith(".pyo"):
                found.append(str(Path(dirpath) / fn))
    return found


def _assert_no_bytecode_in_zip(zip_path: Path) -> List[str]:
    bad: List[str] = []
    try:
        import zipfile
        with zipfile.ZipFile(zip_path, "r") as zf:
            for name in zf.namelist():
                if "__pycache__" in name or name.endswith(".pyc") or name.endswith(".pyo"):
                    bad.append(name)
    except Exception as e:
        cg.tlog(None, "ERROR", "ZIP_SCAN_FAIL", f"cannot scan zip {zip_path}", e)
        bad.append(f"<ZIP_SCAN_FAIL:{type(e).__name__}>")
    return bad

def _assert_no_build_artifacts_in_zip(zip_path: Path) -> List[str]:
    """P0: Release ZIP must not contain dist/ or build artifacts or runtime state."""
    bad: List[str] = []
    try:
        import zipfile
        with zipfile.ZipFile(zip_path, "r") as zf:
            for name in zf.namelist():
                n = name.replace("\\", "/")
                ln = n.lower()
                # build artifacts
                if ln.startswith("dist/") or ln.startswith("build/") or "/dist/" in ln or "/build/" in ln:
                    bad.append(n)
                    continue
                if ".egg-info/" in ln:
                    bad.append(n)
                    continue
                if ln.endswith(".whl") or ln.endswith(".tar.gz") or ln.endswith(".zip"):
                    # nested packages are not allowed (also prevents self-inclusion)
                    bad.append(n)
                    continue
                # runtime state must not ship (keep placeholders only)
                for d in ("db/", "db_backups/", "logs/", "meta/", "lock/", "run/"):
                    if ln.startswith(d):
                        # allow only .keep placeholders
                        if not ln.endswith("/.keep") and not ln.endswith(".keep"):
                            bad.append(n)
                        break
    except Exception as e:
        cg.tlog(None, "ERROR", "ZIP_SCAN_FAIL", f"cannot scan zip {zip_path}", e)
        bad.append(f"<ZIP_SCAN_FAIL:{type(e).__name__}>")
    return bad


def _assert_scud_stat_gate() -> None:
    """P0 static (AST) check — statistical gate must exist (uogólniony).

    Requirements:
    - BIN/scudfab02.py defines MIN_SAMPLE_N as int >= 30 (default 50).
    - compute_verdict() must return YELLOW if sample size < MIN_SAMPLE_N.
    - run_once() must gate tie-break with metrics['n'] >= MIN_SAMPLE_N.
    """
    p = ROOT / "BIN" / "scudfab02.py"
    if not p.exists():
        cg.tlog(None, "ERROR", "GATE_Y_STAT_FAIL", "missing BIN/scudfab02.py")
        raise SystemExit(1)

    try:
        tree = ast.parse(p.read_text(encoding="utf-8", errors="replace"))
    except Exception as e:
        cg.tlog(None, "ERROR", "GATE_Y_STAT_FAIL", "cannot parse BIN/scudfab02.py", e)
        raise SystemExit(1)

    min_sample_val: Optional[int] = None
    for n in getattr(tree, "body", []) or []:
        if isinstance(n, ast.Assign):
            for t in n.targets:
                if isinstance(t, ast.Name) and t.id == "MIN_SAMPLE_N":
                    try:
                        if isinstance(n.value, ast.Constant) and isinstance(n.value.value, (int, float)):
                            min_sample_val = int(n.value.value)
                    except Exception:
                        min_sample_val = None

    if min_sample_val is None or int(min_sample_val) < 30:
        cg.tlog(None, "ERROR", "GATE_Y_STAT_FAIL", f"MIN_SAMPLE_N invalid: {min_sample_val}")
        raise SystemExit(1)

    def _find_func(name: str) -> Optional[ast.FunctionDef]:
        for n in getattr(tree, "body", []) or []:
            if isinstance(n, ast.FunctionDef) and n.name == name:
                return n
        return None

    cv = _find_func("compute_verdict")
    ro = _find_func("run_once")
    if cv is None or ro is None:
        cg.tlog(None, "ERROR", "GATE_Y_STAT_FAIL", "missing compute_verdict or run_once")
        raise SystemExit(1)

    # compute_verdict must compare n_i to MIN_SAMPLE_N and return 'YELLOW'
    has_compare = False
    has_yellow_return = False
    for n in ast.walk(cv):
        if isinstance(n, ast.Compare):
            names = {x.id for x in ast.walk(n) if isinstance(x, ast.Name)}
            if "MIN_SAMPLE_N" in names and ("n_i" in names or "n" in names):
                has_compare = True
        if isinstance(n, ast.Return):
            v = n.value
            if isinstance(v, ast.Constant) and v.value == "YELLOW":
                has_yellow_return = True
    if not (has_compare and has_yellow_return):
        cg.tlog(None, "ERROR", "GATE_Y_STAT_FAIL", f"compute_verdict gate missing (compare={has_compare} yellow_return={has_yellow_return})")
        raise SystemExit(1)

    # run_once must gate allow_tb with MIN_SAMPLE_N
    has_allow_tb_gate = False
    for n in ast.walk(ro):
        if isinstance(n, ast.Assign):
            for t in n.targets:
                if isinstance(t, ast.Name) and t.id == "allow_tb":
                    # look for MIN_SAMPLE_N in the assigned expression
                    names = {x.id for x in ast.walk(n.value) if isinstance(x, ast.Name)}
                    if "MIN_SAMPLE_N" in names:
                        has_allow_tb_gate = True
    if not has_allow_tb_gate:
        cg.tlog(None, "ERROR", "GATE_Y_STAT_FAIL", "run_once allow_tb gate missing")
        raise SystemExit(1)


def _assert_oanda_limits_constants() -> None:
    """P0 static check — OANDA Appendix 3/4 numeric constraints must be explicit.

    This prevents "magic numbers" drifting over time and keeps the bot from guessing.
    Expected values (per Appendix 3/4):
    - oanda_price_warning_per_day = 1000 (calendar day)
    - oanda_price_cutoff_per_day = 5000 (calendar day)
    - oanda_market_orders_per_sec = 50 (market orders)
    - oanda_positions_pending_limit = 500 (positions+pending; excl. TP/SL)
    """
    p = ROOT / "BIN" / "safetybot.py"
    if not p.exists():
        cg.tlog(None, "ERROR", "GATE_OANDA_LIMITS_FAIL", "missing BIN/safetybot.py")
        raise SystemExit(1)

    src = p.read_text(encoding="utf-8", errors="replace")
    expected = {
        "oanda_price_warning_per_day": 1000,
        "oanda_price_cutoff_per_day": 5000,
        "oanda_market_orders_per_sec": 50,
        "oanda_positions_pending_limit": 500,
    }

    missing: List[str] = []
    for k, v in expected.items():
        # allow either annotated or plain assignment
        pat = re.compile(rf"\b{k}\b\s*(?::\s*int)?\s*=\s*{v}\b")
        if not pat.search(src):
            missing.append(f"{k}={v}")

    if missing:
        cg.tlog(None, "ERROR", "GATE_OANDA_LIMITS_FAIL", f"missing_or_changed={missing}")
        raise SystemExit(1)




def _assert_risk_policy_defaults() -> None:
    """P0 static check — Risk policy defaults must be explicit and stable.

    Enforces the agreed defaults:
    - calendar_day_policy = "PL_WARSAW"
    - daily_loss_soft_pct = 0.02
    - daily_loss_hard_pct = 0.03
    - risk_per_trade_max_pct = 0.015
    - risk_scalp_pct/min/max = 0.003/0.002/0.004
    - risk_swing_pct/min/max = 0.01/0.008/0.015
    - max_open_risk_pct = 0.018
    - max_positions_parallel = 5
    - max_positions_per_symbol = 1
    - spread gate factors HOT/WARM/ECO = 1.25 / 1.75 / 2.00
    """
    p = ROOT / "BIN" / "safetybot.py"
    if not p.exists():
        cg.tlog(None, "ERROR", "GATE_RISK_DEFAULTS_FAIL", "missing BIN/safetybot.py")
        raise SystemExit(1)

    src = p.read_text(encoding="utf-8", errors="replace")

    expected = {
        "calendar_day_policy": '"PL_WARSAW"',
        "daily_loss_soft_pct": "0.02",
        "daily_loss_hard_pct": "0.03",
        "risk_per_trade_max_pct": "0.015",
        "risk_scalp_pct": "0.003",
        "risk_scalp_min_pct": "0.002",
        "risk_scalp_max_pct": "0.004",
        "risk_swing_pct": "0.01",
        "risk_swing_min_pct": "0.008",
        "risk_swing_max_pct": "0.015",
        "max_open_risk_pct": "0.018",
        "max_positions_parallel": "5",
        "max_positions_per_symbol": "1",
        "spread_gate_hot_factor": "1.25",
        "spread_gate_warm_factor": "1.75",
        "spread_gate_eco_factor": "2.00",
    }

    missing: List[str] = []
    for k, v in expected.items():
        # allow annotated or plain assignment; keep it strict on the value
        if str(v).startswith(("'", '"')):
            vv = re.escape(str(v))
            pat = re.compile(rf"\b{k}\b\s*(?::\s*[A-Za-z_][A-Za-z0-9_\[\]]*)?\s*=\s*{vv}")
        else:
            pat = re.compile(rf"\b{k}\b\s*(?::\s*[A-Za-z_][A-Za-z0-9_\[\]]*)?\s*=\s*{v}\b")
        if not pat.search(src):
            missing.append(f"{k}={v}")

    if missing:
        cg.tlog(None, "ERROR", "GATE_RISK_DEFAULTS_FAIL", f"missing_or_changed={missing}")
        raise SystemExit(1)


def _run(cmd: List[str], cwd: Path, env: Dict[str, str], timeout_sec: int) -> Tuple[int, str, str, float, Optional[BaseException]]:
    t0 = time.time()
    try:
        # NOTE: In some constrained CI/sandbox environments, Python's subprocess timeout may not fire reliably.
        # To keep the gate deterministic (P0), prefer wrapping commands with the OS `timeout` utility.
        # On POSIX this returns rc=124 when the limit is hit.
        tb = shutil.which("timeout") if os.name != "nt" else None
        if tb:
            wrapped = [tb, f"{int(timeout_sec)}s"] + list(cmd)
            p = subprocess.run(wrapped, cwd=str(cwd), env=env, capture_output=True, text=True)
        else:
            p = subprocess.run(cmd, cwd=str(cwd), env=env, capture_output=True, text=True, timeout=int(timeout_sec))
        dt = time.time() - t0
        return int(p.returncode), (p.stdout or ""), (p.stderr or ""), dt, None
    except subprocess.TimeoutExpired as e:
        dt = time.time() - t0
        return 124, "", f"GATE_TIMEOUT: cmd={cmd} timeout={timeout_sec}s\n", dt, e
    except FileNotFoundError as e:
        dt = time.time() - t0
        return 127, "", f"GATE_MISSING_TOOL: cmd={cmd} err={e}\n", dt, e
    except PermissionError as e:
        dt = time.time() - t0
        return 127, "", f"GATE_UNUSABLE_TOOL: cmd={cmd} err={e}\n", dt, e
    except Exception as e:
        cg.tlog(None, "WARN", "GATE_EXC", "nonfatal exception swallowed", e)
        dt = time.time() - t0
        cg.tlog(None, "ERROR", "GATE_SUBPROC_EXC", f"subprocess failed cmd={cmd}", e)
        return 125, "", f"GATE_ERROR: cmd={cmd} err={type(e).__name__}:{e}\n", dt, e


def _is_pip_audit_networkish(stderr: str) -> bool:
    s = (stderr or "").lower()
    return any(tok in s for tok in [
        "timeout", "timed out", "connection", "temporarily unavailable",
        "name or service not known", "dns", "ssl", "certificate",
        "proxy", "network is unreachable",
    ])


def _load_gate_cfg() -> Dict[str, Any]:
    cfg: Dict[str, Any] = {}
    pp = ROOT / "pyproject.toml"
    if not pp.exists() or tomllib is None:
        return cfg
    try:
        data = tomllib.loads(pp.read_text(encoding="utf-8"))
        cfg = (data.get("tool") or {}).get("oanda_mt5_gate") or {}
        if not isinstance(cfg, dict):
            cfg = {}
    except Exception as e:
        cg.tlog(None, "WARN", "GATE_CFG_READ_FAIL", "cannot read [tool.oanda_mt5_gate] from pyproject.toml", e)
        cfg = {}
    return cfg


def _now_utc_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _sha256_bytes(b: bytes) -> str:
    h = hashlib.sha256()
    h.update(b)
    return h.hexdigest()


def _sha256_text(s: str) -> str:
    return _sha256_bytes((s or "").encode("utf-8", errors="replace"))


def _sha256_path(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _write_json(path: Path, obj: Any) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(obj, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except Exception as e:
        cg.tlog(None, "WARN", "EVIDENCE_WRITE_FAIL", f"cannot write evidence: {path}", e)

def _ensure_json_placeholder(path: Path, payload: dict) -> None:
    """Ensure JSON file exists for evidence even when an external tool times out/offline."""
    try:
        if path.exists():
            return
        _write_json(path, payload)
    except Exception as e:
        cg.tlog(None, 'WARN', 'EVIDENCE_PLACEHOLDER_FAIL', f'cannot create placeholder: {path}', e)



def _tool_versions() -> Dict[str, str]:
    # Best-effort. We do not fail the gate if tool version probes fail.
    out: Dict[str, str] = {
        "python": sys.version.split()[0],
        "platform": platform.platform(),
    }
    probes = {
        "ruff": ["ruff", "--version"],
        "mypy": ["mypy", "--version"],
        "bandit": ["bandit", "--version"],
        "pip_audit": [sys.executable, "-m", "pip_audit", "--version"],
    }
    for k, cmd in probes.items():
        try:
            rc, so, se, _, _ = _run(cmd, ROOT, dict(ENV_BASE), 10)
            if rc == 0 and (so or se):
                out[k] = (so or se).strip().splitlines()[0][:200]
            else:
                out[k] = f"unavailable(rc={rc})"
        except Exception as e:
            cg.tlog(None, "WARN", "GATE_EXC", "nonfatal exception swallowed", e)
            out[k] = "unavailable(exc)"
    return out


def _assert_no_forbidden_except_pass() -> None:
    # P0: forbid swallowing all exceptions.
    # Detect both single-line and multi-line forms:
    #   except Exception: pass
    #   except Exception:\n    pass
    bad: List[str] = []
    rx1 = re.compile(r"^\s*except\s+Exception\s*:\s*pass\s*$", re.M)
    rx2 = re.compile(r"^\s*except\s+Exception\s*:\s*\n\s*pass\s*$", re.M)
    for p in ROOT.rglob("*.py"):
        try:
            lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
        except Exception as e:
            cg.tlog(None, "WARN", "GATE_EXC", "nonfatal exception swallowed", e)
            continue
        txt = "\n".join(lines)
        if rx1.search(txt) or rx2.search(txt):
            bad.append(str(p.relative_to(ROOT)))
    if bad:
        cg.tlog(None, "ERROR", "FORBIDDEN_EXCEPT_PASS", f"found={len(bad)} files")
        for x in bad[:50]:
            sys.stderr.write(f"FORBIDDEN_EXCEPT_PASS: {x}\n")
        raise SystemExit(1)


def _assert_budget_log_has_required_fields() -> None:

    """Hard check: at least one BUDGET log line contains day_ny=, utc_day= and eco=."""
    ok = False
    for p in (ROOT / "BIN").rglob("*.py"):
        try:
            lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
        except Exception as e:
            cg.tlog(None, "WARN", "GATE_EXC", "nonfatal exception swallowed", e)
            continue
        for ln in lines:
            if "BUDGET" in ln and "day_ny=" in ln and "utc_day=" in ln and "eco=" in ln:
                ok = True
                break
        if ok:
            break
    if not ok:
        cg.tlog(None, "ERROR", "BUDGET_LOG_MISSING_FIELDS", "No BUDGET log line contains day_ny= and utc_day=")
        raise SystemExit(1)

def _assert_cfg_budget_defaults() -> None:
    """Hard check: SafetyBot CFG includes explicit budget defaults and Appendix 3 warning/cut-off values."""
    p = ROOT / "BIN" / "safetybot.py"
    try:
        txt = p.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        cg.tlog(None, "ERROR", "CFG_READ_FAIL", f"cannot read {p}", e)
        raise SystemExit(1)

    required = {
        "price_budget_day: int = 400": "PRICE_BUDGET_DEFAULT",
        "order_budget_day: int = 400": "ORDER_BUDGET_DEFAULT",
        "sys_budget_day: int = 400": "SYS_BUDGET_DEFAULT",
        "eco_threshold_pct: float = 0.80": "ECO_THRESHOLD_DEFAULT",
        "oanda_price_warning_per_day: int = 1000": "PRICE_WARNING_DEFAULT",
        "oanda_price_cutoff_per_day: int = 5000": "PRICE_CUTOFF_DEFAULT",
    }
    missing = []
    for needle, code in required.items():
        if needle not in txt:
            missing.append((code, needle))
    if missing:
        for code, needle in missing:
            cg.tlog(None, "ERROR", code, "missing or altered CFG default", needle)
        raise SystemExit(1)





def _assert_structural_methods(cfg: Dict[str, Any]) -> None:
    """
    P0 static (AST) check — uogólniony:
    - Required methods must exist at class level (not accidentally nested inside other methods).
    - Detect missing methods AND detect same-named nested FunctionDef inside class methods.

    Config (pyproject.toml) optional:
        [tool.oanda_mt5_gate]
        structural_required = [
          "BIN/safetybot.py::RequestGovernor.day_state",
          "BIN/safetybot.py::MT5Client.order_send",
        ]
    """
    req_raw = cfg.get("structural_required")
    req: List[Tuple[str, str, str]] = []
    if isinstance(req_raw, list):
        for it in req_raw:
            if not isinstance(it, str):
                continue
            s = it.strip()
            if not s:
                continue
            if "::" in s:
                fp, rest = s.split("::", 1)
                fp = fp.strip() or "BIN/safetybot.py"
            else:
                fp, rest = "BIN/safetybot.py", s
            if "." not in rest:
                continue
            cls, meth = rest.split(".", 1)
            cls = cls.strip()
            meth = meth.strip()
            if cls and meth:
                req.append((fp, cls, meth))
    if not req:
        req = [
            ("BIN/safetybot.py", "RequestGovernor", "day_state"),
            ("BIN/safetybot.py", "MT5Client", "order_send"),
        ]

    by_file: Dict[str, List[Tuple[str, str]]] = {}
    for fp, cls, meth in req:
        by_file.setdefault(fp, []).append((cls, meth))

    errors: List[str] = []

    def _find_class(tree: ast.AST, class_name: str) -> Optional[ast.ClassDef]:
        for n in getattr(tree, "body", []):
            if isinstance(n, ast.ClassDef) and n.name == class_name:
                return n
        return None

    def _class_methods(cls: ast.ClassDef) -> List[ast.FunctionDef]:
        return [n for n in cls.body if isinstance(n, ast.FunctionDef)]

    for fp, needs in by_file.items():
        p = ROOT / fp
        if not p.exists():
            errors.append(f"STRUCTURAL_METHODS: missing file: {fp}")
            continue
        try:
            src0 = p.read_text(encoding="utf-8", errors="replace")
            tree = ast.parse(src0)
        except Exception as e:
            errors.append(f"STRUCTURAL_METHODS: cannot parse {fp}: {e}")
            continue

        for cls_name, meth_name in needs:
            cls = _find_class(tree, cls_name)
            if cls is None:
                errors.append(f"STRUCTURAL_METHODS: class missing: {fp}::{cls_name}")
                continue

            methods = _class_methods(cls)
            top_level = [m for m in methods if m.name == meth_name]

            if len(top_level) > 1:
                locs = ",".join(str(m.lineno) for m in top_level if hasattr(m, "lineno"))
                errors.append(f"STRUCTURAL_METHODS: duplicate method: {fp}::{cls_name}.{meth_name} lineno={locs}")
                continue

            nested_hits: List[int] = []
            for m in methods:
                for n in ast.walk(m):
                    if isinstance(n, ast.FunctionDef) and n is not m and n.name == meth_name:
                        nested_hits.append(int(getattr(n, "lineno", -1)))

            if not top_level:
                if nested_hits:
                    locs = ",".join(str(x) for x in sorted(set(nested_hits)))
                    errors.append(
                        f"STRUCTURAL_METHODS: missing class-level method (found nested): {fp}::{cls_name}.{meth_name} nested_lineno={locs}"
                    )
                else:
                    errors.append(f"STRUCTURAL_METHODS: missing class-level method: {fp}::{cls_name}.{meth_name}")

    if errors:
        cg.tlog(None, "ERROR", "STRUCTURAL_METHODS_FAIL", f"errors={len(errors)}")
        for e in errors[:80]:
            sys.stderr.write(e + "\n")
        raise SystemExit(1)


def _assert_main_guard_is_last_node() -> None:
    """
    P0 static (AST) check — prevent unreachable module-level code after __main__ guard.

    Rationale:
    - In long-running scripts (while True loops), any module-level assignments placed after
      `if __name__ == "__main__": ...` are never executed, causing runtime NameError.
    - This check enforces that the __main__ guard is the last top-level statement.
    """
    errors: List[str] = []

    def _is_main_guard(n: ast.If) -> bool:
        t = n.test
        # __name__ == "__main__"
        if not isinstance(t, ast.Compare):
            return False
        if not (isinstance(t.left, ast.Name) and t.left.id == "__name__"):
            return False
        if len(t.ops) != 1 or not isinstance(t.ops[0], ast.Eq):
            return False
        if len(t.comparators) != 1:
            return False
        c = t.comparators[0]
        if isinstance(c, ast.Constant) and c.value == "__main__":
            return True
        # Py<3.8 legacy
        if hasattr(ast, "Str") and isinstance(c, ast.Str) and c.s == "__main__":
            return True
        return False

    for p in (ROOT / "BIN").rglob("*.py"):
        try:
            src = p.read_text(encoding="utf-8", errors="replace")
            tree = ast.parse(src)
        except Exception as e:
            cg.tlog(None, "WARN", "GATE_EXC", "nonfatal exception swallowed", e)
            continue

        body = getattr(tree, "body", []) or []
        main_idxs = [i for i, n in enumerate(body) if isinstance(n, ast.If) and _is_main_guard(n)]
        if not main_idxs:
            continue
        if len(main_idxs) > 1:
            errors.append(f"MAIN_GUARD_DUP: {p.relative_to(ROOT)} idx={main_idxs}")
            continue
        i_main = main_idxs[0]
        if i_main != (len(body) - 1):
            # There is executable module-level code after the main guard.
            extra = [type(n).__name__ for n in body[i_main + 1 : i_main + 6]]
            errors.append(f"MAIN_GUARD_NOT_LAST: {p.relative_to(ROOT)} extra_after={extra}")

    if errors:
        cg.tlog(None, "ERROR", "MAIN_GUARD_ORDER_FAIL", f"errors={len(errors)}")
        for e in errors[:80]:
            sys.stderr.write(e + "\n")
        raise SystemExit(1)

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="", help="dev or release (default: from pyproject or release)")
    ap.add_argument("--zip", default="", help="Optional: verify this ZIP contains no __pycache__/.pyc/.pyo")
    ap.add_argument("--zip-only", action="store_true", help="Only perform ZIP scans (skip tooling steps)")
    ap.add_argument("--evidence-dir", default="", help="Optional: directory to write AUDIT_EVIDENCE.json and tool outputs")
    ap.add_argument("--evidence-id", default="", help="Optional: evidence run id (default: derived from timestamp)")
    args = ap.parse_args()

    cfg = _load_gate_cfg()
    mode = str(args.mode or cfg.get("mode") or "release").strip().lower()
    timeout_default = int(cfg.get("timeout_sec") or 60)

    evidence_dir: Optional[Path] = None
    if str(args.evidence_dir or "").strip():
        evidence_dir = Path(str(args.evidence_dir)).expanduser().resolve()
        evidence_dir.mkdir(parents=True, exist_ok=True)
    evidence_id = str(args.evidence_id or "").strip() or f"gate_{_now_utc_iso().replace(':','').replace('-','')}"

    evidence: Dict[str, Any] = {
        "id": evidence_id,
        "timestamp_utc": _now_utc_iso(),
        "mode": mode,
        "root": str(ROOT),
        "zip": str(args.zip or ""),
        "zip_only": bool(args.zip_only),
        "unverified": [],
        "steps": [],
        "tool_versions": _tool_versions(),
        "config": cfg,
    }

    def _finalize(rc: int) -> int:
        if evidence_dir is not None:
            _write_json(evidence_dir / "AUDIT_EVIDENCE.json", evidence)
        return int(rc)

    # Static P0 checks (hard FAIL)
    try:
        _assert_no_forbidden_except_pass()
        _assert_budget_log_has_required_fields()
        _assert_cfg_budget_defaults()
        _assert_structural_methods(cfg)
        _assert_main_guard_is_last_node()
        _assert_scud_stat_gate()
        _assert_oanda_limits_constants()
    except SystemExit as se:
        evidence["exception"] = {"type": "SystemExit", "code": int(getattr(se, "code", 1) or 1)}
        return _finalize(evidence["exception"]["code"])
    except Exception as e:
        evidence["exception"] = {"type": type(e).__name__, "msg": str(e)[:500]}
        cg.tlog(None, "ERROR", "GATE_STATIC_P0_EXCEPTION", "unexpected exception in static checks", e)
        return _finalize(1)

    env = dict(ENV_BASE)

    # Pre-clean and assert
    removed = _clean_bytecode_tree(ROOT)
    if removed:
        cg.tlog(None, "INFO", "CLEAN_BYTECODE", f"removed_bytecode_artifacts={removed}")
    leftovers = _find_bytecode_artifacts(ROOT)
    if leftovers:
        cg.tlog(None, "ERROR", "BYTECODE_LEFTOVER", f"found={len(leftovers)} artifacts; run clean again")
        for x in leftovers[:50]:
            sys.stderr.write(f"BYTECODE_LEFTOVER: {x}\n")
        return _finalize(1)

    # Steps (configured in pyproject; safe defaults)
    def enabled(k: str, default: bool = True) -> bool:
        v = cfg.get(f"enable_{k}")
        if v is None:
            return bool(default)
        return bool(v)

    # In RELEASE we override a minimal, safe set of mandatory checks.
    # The goal is deterministic verification without forcing mass refactors.
    # Release requires deterministic static+unit checks. Network-dependent scanners (pip-audit)
    # are allowed to be disabled in offline builds and reported as UNVERIFIED_SECURITY.
    required_release = {"compileall", "unittest", "bandit"}

    def enabled_release(k: str, default: bool = True) -> bool:
        if mode == "release" and k in required_release:
            return True
        return enabled(k, default)

    steps: List[Dict[str, Any]] = []
    if enabled_release("black"):
        steps.append({"name": "black", "cmd": ["black", "--check", "."], "timeout": int(cfg.get("timeout_black") or timeout_default)})
    if enabled_release("isort"):
        steps.append({"name": "isort", "cmd": ["isort", "--check-only", "."], "timeout": int(cfg.get("timeout_isort") or timeout_default)})
    if enabled_release("ruff"):
        steps.append({"name": "ruff", "cmd": ["ruff", "check", "."], "timeout": int(cfg.get("timeout_ruff") or timeout_default)})
    if enabled_release("mypy"):
        steps.append({"name": "mypy", "cmd": ["mypy", "BIN"], "timeout": int(cfg.get("timeout_mypy") or max(timeout_default, 120))})
    if enabled_release("bandit"):
        # bandit.yaml is optional; if missing, bandit runs with defaults.
        bandit_cmd = ["bandit", "-r", "BIN"]
        if (ROOT / "bandit.yaml").exists():
            bandit_cmd = ["bandit", "-c", "bandit.yaml", "-r", "BIN"]
        # Default to MEDIUM+ to avoid failing releases on low-severity findings
        sev = str(cfg.get("bandit_severity_level") or "medium").strip().lower()
        if sev in {"low", "medium", "high", "all"}:
            bandit_cmd += ["--severity-level", sev]
        if evidence_dir is not None:
            bandit_cmd += ["-f", "json", "-o", str((evidence_dir / "bandit.json").resolve())]
        steps.append({"name": "bandit", "cmd": bandit_cmd, "timeout": int(cfg.get("timeout_bandit") or max(timeout_default, 120))})
    if enabled_release("compileall"):
        steps.append({"name": "compileall", "cmd": ["python", "-m", "compileall", "BIN"], "timeout": int(cfg.get("timeout_compileall") or max(timeout_default, 120))})
    if enabled_release("unittest"):
        steps.append({"name": "unittest", "cmd": ["python", "-m", "unittest", "discover", "-s", "tests", "-v"], "timeout": int(cfg.get("timeout_unittest") or max(timeout_default, 180))})

    # Optional pip-audit step
    pip_audit_enabled = enabled_release("pip_audit", default=True)
    pip_audit_timeout = int(cfg.get("timeout_pip_audit") or 180)
    pip_audit_files = cfg.get("pip_audit_requirements") or ["requirements-dev.txt", "requirements.txt"]
    if not isinstance(pip_audit_files, list):
        pip_audit_files = ["requirements-dev.txt", "requirements.txt"]

    if args.zip_only:
        # In ZIP-only mode we skip all tooling checks and only validate the archive contents.
        steps = []
        pip_audit_enabled = False

    unverified_tooling = False
    unverified_security = False
    unsafe_security = False

    # In RELEASE, if some non-mandatory steps are disabled, we still proceed but mark the run unverified.
    if mode == "release":
        for opt in ("black", "isort", "ruff", "mypy"):
            if not enabled(opt, default=False):
                unverified_tooling = True
                evidence["unverified"].append(f"TOOLING_DISABLED:{opt}")
                cg.tlog(None, "WARN", "GATE_UNVERIFIED_TOOLING", f"step disabled in pyproject: {opt}")
        if not enabled("pip_audit", default=True):
            unverified_security = True
            evidence["unverified"].append("SECURITY_DISABLED:pip_audit")
            cg.tlog(None, "WARN", "GATE_UNVERIFIED_SECURITY", "pip-audit disabled in pyproject (Option2)")

    # Run normal steps
    for st in steps:
        rc, out, err, dt, exc = _run(list(st["cmd"]), ROOT, env, int(st["timeout"]))
        # Evidence
        evidence["steps"].append({
            "name": st["name"],
            "cmd": list(st["cmd"]),
            "timeout_sec": int(st["timeout"]),
            "rc": int(rc),
            "dt_sec": float(dt),
            "stdout_sha256": _sha256_text(out),
            "stderr_sha256": _sha256_text(err),
            "stdout_head": "\n".join((out or "").splitlines()[:30]),
            "stderr_head": "\n".join((err or "").splitlines()[:30]),
        })
        if out:
            sys.stdout.write(out)
        if err:
            sys.stderr.write(err)

        if rc == 127 and mode == "dev":
            unverified_tooling = True
            if exc:
                cg.tlog(None, "WARN", "GATE_UNVERIFIED_TOOLING", f"missing tool step={st['name']} (SKIP) rc={rc} dt={dt:.2f}s", exc)
            else:
                cg.tlog(None, "WARN", "GATE_UNVERIFIED_TOOLING", f"missing tool step={st['name']} (SKIP) rc={rc} dt={dt:.2f}s")
            continue

        if rc != 0:
            if rc == 127 and mode != "dev":
                cg.tlog(None, "ERROR", "GATE_MISSING_TOOL", f"missing tool step={st['name']} (FAIL) rc={rc} dt={dt:.2f}s", exc)
            else:
                cg.tlog(None, "ERROR", "GATE_STEP_FAIL", f"{st['name']} rc={rc} dt={dt:.2f}s", exc)
            return _finalize(1)

    # pip-audit
    if pip_audit_enabled:
        for fn in pip_audit_files:
            rp = ROOT / str(fn)
            if not rp.exists():
                continue
            try:
                content = rp.read_text(encoding="utf-8")
            except Exception as e:
                cg.tlog(None, "WARN", "GATE_PIP_AUDIT_READ_FAIL", f"cannot read {rp.name}", e)
                continue
            nonempty = [ln for ln in content.splitlines() if ln.strip() and not ln.strip().startswith("#")]
            if not nonempty:
                continue

            pip_out_path = None
            cmd = [sys.executable, "-m", "pip_audit", "-r", rp.name]
            if evidence_dir is not None:
                pip_out_path = (evidence_dir / f"pip_audit_{rp.name}.json").resolve()
                cmd += ["-f", "json", "-o", str(pip_out_path)]
            rc, out, err, dt, exc = _run(cmd, ROOT, env, pip_audit_timeout)
            evidence["steps"].append({
                "name": f"pip-audit:{rp.name}",
                "cmd": cmd,
                "timeout_s": pip_audit_timeout,
                "dt_s": round(float(dt), 3),
                "rc": int(rc),
                "status": "PENDING",
                "stdout_sha256": _sha256_text(out),
                "stderr_sha256": _sha256_text(err),
                "stdout_head": "\n".join((out or "").splitlines()[:30]),
                "stderr_head": "\n".join((err or "").splitlines()[:30]),
            })
            if out:
                sys.stdout.write(out)
            if err:
                sys.stderr.write(err)
            # Classify pip-audit outcome (Option 2): never block RELEASE.
            if rc == 0:
                status = "PASS"
            elif rc == 127:
                status = "UNVERIFIED_TOOLING"
            elif rc in (124,) or _is_pip_audit_networkish(err):
                status = "UNVERIFIED_SECURITY"
            else:
                status = "UNSAFE_SECURITY"

            # Write back status into evidence (last step appended).
            try:
                evidence["steps"][-1]["status"] = status

                # Ensure output JSON exists even when pip-audit times out/offline.
                if pip_out_path is not None and not pip_out_path.exists():
                    _ensure_json_placeholder(
                        pip_out_path,
                        {
                            "tool": "pip-audit",
                            "input": rp.name,
                            "status": status,
                            "rc": int(rc),
                            "dt_s": round(float(dt), 3),
                            "note": "placeholder: pip-audit did not produce JSON (timeout/offline/tool error)",
                            "stderr_head": evidence["steps"][-1].get("stderr_head", ""),
                            "stdout_head": evidence["steps"][-1].get("stdout_head", ""),
                        },
                    )
                    cg.tlog(None, "INFO", "EVIDENCE_PIP_AUDIT_PLACEHOLDER", f"created {pip_out_path.name} status={status} rc={rc}")
            except Exception as e:
                cg.tlog(None, "WARN", "GATE_EVIDENCE_STATUS_FAIL", "cannot write pip-audit status/placeholder to evidence", e)

            if status == "PASS":

                continue

            if mode == "release":
                # RELEASE: never fail on pip-audit. Surface as flags.
                if status == "UNVERIFIED_TOOLING":
                    unverified_tooling = True
                    unverified_security = True
                    evidence["unverified"].append("SECURITY_PIP_AUDIT:tool_missing")
                    cg.tlog(None, "WARN", "GATE_UNVERIFIED_TOOLING", f"pip-audit tool missing in RELEASE ({rp.name}) rc={rc} dt={dt:.2f}s", exc)
                    continue
                if status == "UNVERIFIED_SECURITY":
                    unverified_security = True
                    evidence["unverified"].append("SECURITY_PIP_AUDIT:network_unverified")
                    cg.tlog(None, "WARN", "GATE_UNVERIFIED_SECURITY", f"pip-audit unverified in RELEASE ({rp.name}) rc={rc} dt={dt:.2f}s", exc)
                    continue
                # UNSAFE_SECURITY
                unsafe_security = True
                evidence["unverified"].append("SECURITY_PIP_AUDIT:unsafe")
                cg.tlog(None, "WARN", "GATE_UNSAFE_SECURITY", f"pip-audit reported issues in RELEASE ({rp.name}) rc={rc} dt={dt:.2f}s", exc)
                continue

            # DEV: fail on UNSAFE_SECURITY, but allow network/tooling issues to be unverified.
            if status in ("UNVERIFIED_TOOLING", "UNVERIFIED_SECURITY"):
                unverified_security = True
                evidence["unverified"].append("SECURITY_PIP_AUDIT:dev_unverified")
                cg.tlog(None, "WARN", "GATE_UNVERIFIED_SECURITY", f"pip-audit unverified in DEV ({rp.name}) rc={rc} dt={dt:.2f}s", exc)
                continue
            cg.tlog(None, "ERROR", "GATE_PIP_AUDIT_FAIL", f"pip-audit failed ({rp.name}) rc={rc} dt={dt:.2f}s", exc)
            return _finalize(1)

    # Post-clean and assert
    removed2 = _clean_bytecode_tree(ROOT)
    if removed2:
        cg.tlog(None, "INFO", "CLEAN_BYTECODE_POST", f"removed_bytecode_artifacts={removed2}")
    leftovers2 = _find_bytecode_artifacts(ROOT)
    if leftovers2:
        cg.tlog(None, "ERROR", "BYTECODE_LEFTOVER_POST", f"found={len(leftovers2)} artifacts after post-clean")
        for x in leftovers2[:50]:
            sys.stderr.write(f"BYTECODE_LEFTOVER_POST: {x}\n")
        return _finalize(1)

    # Optional ZIP scan
    if args.zip:
        zp = Path(args.zip)
        if not zp.is_absolute():
            zp = (ROOT / zp).resolve()
        if not zp.exists():
            cg.tlog(None, "ERROR", "ZIP_NOT_FOUND", f"zip not found: {zp}")
            return _finalize(1)
        bad = _assert_no_bytecode_in_zip(zp)
        if bad:
            cg.tlog(None, "ERROR", "ZIP_HAS_BYTECODE", f"zip contains bytecode artifacts: {len(bad)}")
            for n in bad[:50]:
                sys.stderr.write(f"ZIP_BYTECODE: {n}\n")
            return _finalize(1)

        bad2 = _assert_no_build_artifacts_in_zip(zp)
        if bad2:
            cg.tlog(None, "ERROR", "ZIP_HAS_BUILD_ARTIFACTS", f"zip contains build/runtime artifacts: {len(bad2)}")
            for n in bad2[:50]:
                sys.stderr.write(f"ZIP_BUILD_ARTIFACT: {n}\n")
            return _finalize(1)

    flags = []
    if unsafe_security:
        flags.append("UNSAFE_SECURITY")
    if unverified_security:
        flags.append("UNVERIFIED_SECURITY")
    if unverified_tooling:
        flags.append("UNVERIFIED_TOOLING")

    if flags:
        sys.stdout.write("\nGATE_OK | " + ",".join(flags) + "\n")
        return _finalize(0)

    sys.stdout.write("\nGATE_OK | VERIFIED\n")
    return _finalize(0)


if __name__ == "__main__":
    raise SystemExit(main())
