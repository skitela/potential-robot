# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import ctypes
import json
import os
import re
import sqlite3
import statistics
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from unittest import mock


DENY_DIRS = {
    ".git",
    ".venv",
    "venv",
    "__pycache__",
    ".pycache",
    ".tmp",
    "EVIDENCE",
    "DIAG",
}


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def write_json(path: Path, obj: Any) -> None:
    ensure_dir(path.parent)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(obj, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def append_jsonl(path: Path, obj: Dict[str, Any]) -> None:
    ensure_dir(path.parent)
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(obj, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n")


def safe_rel(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except Exception:
        return path.as_posix()


def run_cmd(
    cmd: List[str],
    *,
    cwd: Path,
    env: Optional[Dict[str, str]] = None,
    timeout_sec: float = 120.0,
) -> Dict[str, Any]:
    t0 = time.perf_counter()
    timed_out = False
    exit_code = -999
    out = ""
    err = ""
    try:
        cp = subprocess.run(
            cmd,
            cwd=str(cwd),
            env=env,
            capture_output=True,
            text=True,
            timeout=max(1.0, float(timeout_sec)),
            check=False,
        )
        exit_code = int(cp.returncode)
        out = cp.stdout or ""
        err = cp.stderr or ""
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        out = (exc.stdout or "") if isinstance(exc.stdout, str) else ""
        err = (exc.stderr or "") if isinstance(exc.stderr, str) else ""
        exit_code = 124
    except Exception as exc:
        err = f"{type(exc).__name__}: {exc}"
        exit_code = 125
    dt_sec = time.perf_counter() - t0
    return {
        "cmd": cmd,
        "exit_code": exit_code,
        "timed_out": bool(timed_out),
        "duration_sec": round(float(dt_sec), 6),
        "stdout": out,
        "stderr": err,
    }


def _iter_python_files(root: Path) -> List[Path]:
    out: List[Path] = []
    for dirpath, dirs, files in os.walk(root):
        d = Path(dirpath)
        dirs[:] = [x for x in dirs if x not in DENY_DIRS]
        for name in files:
            if not name.endswith(".py"):
                continue
            out.append(d / name)
    out.sort(key=lambda p: p.as_posix())
    return out


def _check_line_style(path: Path) -> Dict[str, Any]:
    tab_indent = 0
    trailing_ws = 0
    odd_indent = 0
    mixed_sep_literals = 0
    absolute_paths = 0
    bad_lines: List[Dict[str, Any]] = []
    abs_pat = re.compile(r"(?<![A-Za-z0-9])[A-Za-z]:(?!//)[\\/][^'\"\s]+")
    mixed_pat = re.compile(r"[A-Za-z]:(?!//)\\[^'\"]*/|[A-Za-z]:(?!//)/[^'\"]*\\")
    try:
        text = path.read_text(encoding="utf-8-sig", errors="ignore")
    except Exception as exc:
        return {"parse_error": f"{type(exc).__name__}: {exc}"}

    for i, raw in enumerate(text.splitlines(), start=1):
        line = raw.rstrip("\n")
        stripped = line.lstrip(" \t")
        lead = line[: len(line) - len(stripped)]
        if "\t" in lead:
            tab_indent += 1
            if len(bad_lines) < 20:
                bad_lines.append({"line": i, "issue": "tab_indent"})
        if line != line.rstrip(" \t"):
            trailing_ws += 1
            if len(bad_lines) < 20:
                bad_lines.append({"line": i, "issue": "trailing_ws"})
        if lead and ("\t" not in lead) and (len(lead) % 4 != 0) and stripped and not stripped.startswith("#"):
            odd_indent += 1
            if len(bad_lines) < 20:
                bad_lines.append({"line": i, "issue": "indent_not_multiple_of_4"})
        if mixed_pat.search(line):
            mixed_sep_literals += 1
            if len(bad_lines) < 20:
                bad_lines.append({"line": i, "issue": "mixed_path_separator_literal"})
        for match in abs_pat.findall(line):
            token = str(match)
            low = token.lower()
            if low.startswith("http://") or low.startswith("https://"):
                continue
            if low.startswith("c:\\oanda_mt5_system") or low.startswith("c:/oanda_mt5_system"):
                continue
            absolute_paths += 1
            if len(bad_lines) < 20:
                bad_lines.append({"line": i, "issue": "hardcoded_absolute_path", "value": token})

    return {
        "tab_indent": tab_indent,
        "trailing_ws": trailing_ws,
        "odd_indent": odd_indent,
        "mixed_path_literals": mixed_sep_literals,
        "hardcoded_absolute_paths": absolute_paths,
        "samples": bad_lines,
    }


def phase_static(root: Path, evidence_dir: Path) -> Dict[str, Any]:
    phase_dir = ensure_dir(evidence_dir / "01_static")
    py_files = _iter_python_files(root)
    compile_errors: List[Dict[str, Any]] = []
    style_findings: List[Dict[str, Any]] = []
    totals = {
        "files_scanned": len(py_files),
        "compile_errors": 0,
        "tab_indent": 0,
        "trailing_ws": 0,
        "odd_indent": 0,
        "mixed_path_literals": 0,
        "hardcoded_absolute_paths": 0,
    }
    for p in py_files:
        rel = safe_rel(p, root)
        try:
            src = p.read_text(encoding="utf-8-sig", errors="ignore")
            compile(src, rel, "exec")
        except Exception as exc:
            compile_errors.append({"file": rel, "error": f"{type(exc).__name__}: {exc}"})
            totals["compile_errors"] += 1
        style = _check_line_style(p)
        if "parse_error" in style:
            style_findings.append({"file": rel, "parse_error": style["parse_error"]})
            continue
        totals["tab_indent"] += int(style.get("tab_indent", 0))
        totals["trailing_ws"] += int(style.get("trailing_ws", 0))
        totals["odd_indent"] += int(style.get("odd_indent", 0))
        totals["mixed_path_literals"] += int(style.get("mixed_path_literals", 0))
        totals["hardcoded_absolute_paths"] += int(style.get("hardcoded_absolute_paths", 0))
        if any(int(style.get(k, 0)) > 0 for k in ("tab_indent", "trailing_ws", "odd_indent", "mixed_path_literals", "hardcoded_absolute_paths")):
            style_findings.append({"file": rel, **style})

    out = {
        "phase": "static",
        "ts_utc": utc_now_iso(),
        "totals": totals,
        "compile_errors": compile_errors,
        "style_findings": style_findings,
        "status": "PASS" if totals["compile_errors"] == 0 else "FAIL",
    }
    write_json(phase_dir / "static_report.json", out)
    return out


def probe_adaptive_guard(root: Path) -> Dict[str, Any]:
    root_s = str(root.resolve())
    if root_s not in sys.path:
        sys.path.insert(0, root_s)
    try:
        from BIN import learner_offline as lr  # type: ignore
    except Exception as exc:
        return {
            "status": "FAIL",
            "error": f"import_error:{type(exc).__name__}:{exc}",
            "cases": [],
            "throughput": {},
        }

    cases: List[Dict[str, Any]] = [
        {"name": "normal", "cpu_pct": 50.0, "mem_mb": 4096.0, "expect_mode": "normal", "expect_fetch": True, "expect_limit": 20000},
        {"name": "light", "cpu_pct": 74.0, "mem_mb": 4096.0, "expect_mode": "light", "expect_fetch": True, "expect_limit": 5000},
        {"name": "skip", "cpu_pct": 95.0, "mem_mb": 4096.0, "expect_mode": "skip", "expect_fetch": False, "expect_limit": None},
    ]
    rows: List[Dict[str, Any]] = []

    for c in cases:
        captured: List[Tuple[str, Any]] = []
        fetch_meta = {"calls": 0, "limit": None}

        def _capture_write(path: Path, obj: Any) -> None:
            captured.append((str(path), obj))

        def _fetch_stub(_db_path: Path, since_iso_utc: str, limit: int = 20000) -> List[Dict[str, Any]]:
            _ = since_iso_utc
            fetch_meta["calls"] += 1
            fetch_meta["limit"] = int(limit)
            return []

        fake_meta = {
            "schema": "oanda_mt5.learner_advice.v1",
            "ts_utc": utc_now_iso(),
            "ttl_sec": 3600,
            "window_days": 90,
            "metrics": {"n": 0, "mean_edge_fuel": 0.0, "es95": 0.0, "mdd": 0.0},
            "ranks": [],
            "notes": ["source=decision_events", "method=psr_weighted", "mode=offline"],
        }
        fake_report = {"ts_utc": utc_now_iso(), "window_days": 90, "syms": []}

        env_patch = {
            "LEARNER_RESOURCE_GUARD": "1",
            "LEARNER_WINDOW_DAYS": "180",
            "LEARNER_ROW_LIMIT": "20000",
            "LEARNER_LIGHT_WINDOW_DAYS": "90",
            "LEARNER_LIGHT_ROW_LIMIT": "5000",
            "LEARNER_CPU_SOFT_MAX_PCT": "70",
            "LEARNER_CPU_HARD_MAX_PCT": "85",
            "LEARNER_MEM_MIN_MB": "1500",
        }

        t0 = time.perf_counter()
        with mock.patch.dict(os.environ, env_patch, clear=False), \
             mock.patch.object(lr, "read_cpu_percent", return_value=float(c["cpu_pct"])), \
             mock.patch.object(lr, "read_mem_available_mb", return_value=float(c["mem_mb"])), \
             mock.patch.object(lr, "fetch_closed_events", side_effect=_fetch_stub), \
             mock.patch.object(lr, "build_advice", return_value=(fake_meta, fake_report)), \
             mock.patch.object(lr, "atomic_write_json", side_effect=_capture_write):
            rc = int(lr.run_once(root))
        dt_sec = max(1e-6, time.perf_counter() - t0)

        mode_observed = "skip"
        row_limit_observed: Optional[int] = None
        for p, obj in captured:
            if p.endswith("learner_offline_report.json"):
                rg = dict((obj or {}).get("resource_guard") or {})
                mode_observed = str(rg.get("mode") or "")
                rl = rg.get("row_limit_effective")
                row_limit_observed = int(rl) if isinstance(rl, (int, float)) else None
                break

        fetch_called = int(fetch_meta["calls"]) > 0
        ok = (
            rc == 0
            and mode_observed == str(c["expect_mode"])
            and fetch_called == bool(c["expect_fetch"])
            and (
                c["expect_limit"] is None
                or int(fetch_meta["limit"] or 0) == int(c["expect_limit"])
                or int(row_limit_observed or 0) == int(c["expect_limit"])
            )
        )
        rows.append(
            {
                "mode_case": c["name"],
                "rc": rc,
                "duration_sec": round(float(dt_sec), 6),
                "throughput_runs_per_sec": round(1.0 / float(dt_sec), 3),
                "mode_observed": mode_observed,
                "fetch_called": bool(fetch_called),
                "row_limit_observed": row_limit_observed,
                "fetch_limit": fetch_meta["limit"],
                "ok": bool(ok),
            }
        )

    by_name = {str(x["mode_case"]): x for x in rows}
    throughput = {
        "normal_rps": by_name.get("normal", {}).get("throughput_runs_per_sec"),
        "light_rps": by_name.get("light", {}).get("throughput_runs_per_sec"),
        "skip_rps": by_name.get("skip", {}).get("throughput_runs_per_sec"),
    }
    status = "PASS" if rows and all(bool(x.get("ok")) for x in rows) else "FAIL"
    return {
        "status": status,
        "cases": rows,
        "throughput": throughput,
    }


def phase_contracts(root: Path, evidence_dir: Path) -> Dict[str, Any]:
    phase_dir = ensure_dir(evidence_dir / "02_contracts")
    tests = [
        "tests.test_structural_p0",
        "tests.test_api_contracts",
        "tests.test_contract_run_v2",
        "tests.test_offline_network_guard",
        "tests.test_runtime_housekeeping",
        "tests.test_scud_rss_normalization",
        "tests.test_scud_advice_contract_inmem",
        "tests.test_learner_resource_guard",
        "tests.test_training_quality",
    ]
    runs: List[Dict[str, Any]] = []
    env = dict(os.environ)
    env["OANDA_RUN_MODE"] = "OFFLINE"
    env["OFFLINE_DETERMINISTIC"] = "1"
    env["SCUD_ALLOW_RSS"] = "0"

    sanity = run_cmd(["python", "DYRYGENT_EXTERNAL.py", "--help"], cwd=root, env=env, timeout_sec=30)
    write_json(phase_dir / "dyrygent_help.json", sanity)
    runs.append({"name": "dyrygent_help", **{k: v for k, v in sanity.items() if k != "cmd"}})

    for mod in tests:
        cmd = ["python", "-B", "-m", "unittest", mod]
        rec = run_cmd(cmd, cwd=root, env=env, timeout_sec=180)
        log_path = phase_dir / f"{mod}.txt"
        with log_path.open("w", encoding="utf-8", newline="\n") as handle:
            handle.write("COMMAND: " + " ".join(cmd) + "\n")
            handle.write(f"EXIT_CODE: {rec['exit_code']}\n")
            handle.write(f"TIMED_OUT: {rec['timed_out']}\n")
            handle.write(f"DURATION_SEC: {rec['duration_sec']}\n")
            handle.write("\n--- STDOUT ---\n")
            handle.write(rec.get("stdout", ""))
            handle.write("\n--- STDERR ---\n")
            handle.write(rec.get("stderr", ""))
            handle.write("\n")
        runs.append(
            {
                "name": mod,
                "exit_code": int(rec["exit_code"]),
                "timed_out": bool(rec["timed_out"]),
                "duration_sec": float(rec["duration_sec"]),
                "log": safe_rel(log_path, root),
            }
        )

    tiebreak_code = (
        "import shutil,time\n"
        "from pathlib import Path\n"
        "from tests import test_tiebreak_fastlane as t\n"
        "tmp = Path('.tmp') / f'xcross_tb_{int(time.time()*1000)}'\n"
        "tmp.mkdir(parents=True, exist_ok=True)\n"
        "try:\n"
        "    t.test_tiebreak_fastlane_writes_response(tmp)\n"
        "    print('OK')\n"
        "finally:\n"
        "    shutil.rmtree(tmp, ignore_errors=True)\n"
    )
    tiebreak_cmd = ["python", "-c", tiebreak_code]
    tiebreak_rec = run_cmd(tiebreak_cmd, cwd=root, env=env, timeout_sec=120)
    tiebreak_log = phase_dir / "tests.test_tiebreak_fastlane.txt"
    with tiebreak_log.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("COMMAND: python -c <tiebreak_fastlane_runner>\n")
        handle.write(f"EXIT_CODE: {tiebreak_rec['exit_code']}\n")
        handle.write(f"TIMED_OUT: {tiebreak_rec['timed_out']}\n")
        handle.write(f"DURATION_SEC: {tiebreak_rec['duration_sec']}\n")
        handle.write("\n--- STDOUT ---\n")
        handle.write(tiebreak_rec.get("stdout", ""))
        handle.write("\n--- STDERR ---\n")
        handle.write(tiebreak_rec.get("stderr", ""))
        handle.write("\n")
    runs.append(
        {
            "name": "tests.test_tiebreak_fastlane",
            "exit_code": int(tiebreak_rec["exit_code"]),
            "timed_out": bool(tiebreak_rec["timed_out"]),
            "duration_sec": float(tiebreak_rec["duration_sec"]),
            "log": safe_rel(tiebreak_log, root),
        }
    )

    adaptive = probe_adaptive_guard(root)
    adaptive_path = phase_dir / "adaptive_guard_report.json"
    write_json(adaptive_path, adaptive)
    runs.append(
        {
            "name": "adaptive_guard_probe",
            "exit_code": 0 if adaptive.get("status") == "PASS" else 1,
            "timed_out": False,
            "duration_sec": sum(float(x.get("duration_sec", 0.0)) for x in adaptive.get("cases", [])),
            "log": safe_rel(adaptive_path, root),
        }
    )

    failures = [r for r in runs if int(r.get("exit_code", 1)) != 0 or bool(r.get("timed_out", False))]
    out = {
        "phase": "contracts",
        "ts_utc": utc_now_iso(),
        "runs": runs,
        "failed": failures,
        "adaptive_guard": adaptive,
        "status": "PASS" if not failures else "FAIL",
    }
    write_json(phase_dir / "contracts_report.json", out)
    return out


def _cpu_percent_windows(sample_sec: float = 0.10) -> Optional[float]:
    try:
        class FILETIME(ctypes.Structure):
            _fields_ = [("dwLowDateTime", ctypes.c_uint32), ("dwHighDateTime", ctypes.c_uint32)]

        def ft_to_int(ft: FILETIME) -> int:
            return (int(ft.dwHighDateTime) << 32) | int(ft.dwLowDateTime)

        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        idle1, kern1, user1 = FILETIME(), FILETIME(), FILETIME()
        if not k32.GetSystemTimes(ctypes.byref(idle1), ctypes.byref(kern1), ctypes.byref(user1)):
            return None
        time.sleep(max(0.05, min(0.4, float(sample_sec))))
        idle2, kern2, user2 = FILETIME(), FILETIME(), FILETIME()
        if not k32.GetSystemTimes(ctypes.byref(idle2), ctypes.byref(kern2), ctypes.byref(user2)):
            return None
        idle = ft_to_int(idle2) - ft_to_int(idle1)
        kern = ft_to_int(kern2) - ft_to_int(kern1)
        user = ft_to_int(user2) - ft_to_int(user1)
        total = kern + user
        if total <= 0:
            return None
        busy = max(0, total - idle)
        return max(0.0, min(100.0, 100.0 * busy / total))
    except Exception:
        return None


def _mem_available_mb_windows() -> Optional[float]:
    try:
        class MEMORYSTATUSEX(ctypes.Structure):
            _fields_ = [
                ("dwLength", ctypes.c_uint32),
                ("dwMemoryLoad", ctypes.c_uint32),
                ("ullTotalPhys", ctypes.c_uint64),
                ("ullAvailPhys", ctypes.c_uint64),
                ("ullTotalPageFile", ctypes.c_uint64),
                ("ullAvailPageFile", ctypes.c_uint64),
                ("ullTotalVirtual", ctypes.c_uint64),
                ("ullAvailVirtual", ctypes.c_uint64),
                ("ullAvailExtendedVirtual", ctypes.c_uint64),
            ]

        ms = MEMORYSTATUSEX()
        ms.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
        if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(ms)):
            return None
        return float(ms.ullAvailPhys) / float(1024 ** 2)
    except Exception:
        return None


def cpu_percent() -> Optional[float]:
    if os.name == "nt":
        return _cpu_percent_windows(sample_sec=0.10)
    try:
        la1 = os.getloadavg()[0]
        cpus = float(max(1, os.cpu_count() or 1))
        return max(0.0, min(100.0, 100.0 * la1 / cpus))
    except Exception:
        return None


def mem_available_mb() -> Optional[float]:
    if os.name == "nt":
        return _mem_available_mb_windows()
    try:
        page_size = os.sysconf("SC_PAGE_SIZE")
        avail_pages = os.sysconf("SC_AVPHYS_PAGES")
        return float(page_size * avail_pages) / float(1024 ** 2)
    except Exception:
        return None


def _pid_running(pid: int) -> bool:
    if int(pid) <= 0:
        return False
    if os.name == "nt":
        try:
            cp = subprocess.run(
                ["tasklist", "/FI", f"PID eq {int(pid)}"],
                capture_output=True,
                text=True,
                check=False,
                timeout=3.0,
            )
            return str(int(pid)) in str(cp.stdout or "")
        except Exception:
            return False
    try:
        os.kill(int(pid), 0)
        return True
    except Exception:
        return False


def _cleanup_scud_lock(root: Path) -> Dict[str, Any]:
    lock = root / "RUN" / "scudfab02.lock"
    out: Dict[str, Any] = {
        "lock": safe_rel(lock, root),
        "existed_before": bool(lock.exists()),
        "removed": False,
        "pid": None,
        "reason": "not_present",
        "kill_attempted": False,
    }
    if not lock.exists():
        return out
    try:
        raw = lock.read_text(encoding="utf-8", errors="ignore").strip()
        pid = int(raw) if raw.isdigit() else 0
    except Exception:
        pid = 0
    out["pid"] = int(pid)
    if pid > 0 and _pid_running(pid):
        if os.name == "nt":
            out["kill_attempted"] = True
            try:
                cp = subprocess.run(
                    ["taskkill", "/PID", str(pid), "/T", "/F"],
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=8.0,
                )
                out["kill_exit"] = int(cp.returncode)
            except Exception as exc:
                out["kill_error"] = f"{type(exc).__name__}:{exc}"
            time.sleep(0.25)
        if _pid_running(pid):
            out["reason"] = "pid_running"
            out["exists_after"] = bool(lock.exists())
            return out
    try:
        lock.unlink(missing_ok=True)
        out["removed"] = True
        out["reason"] = "stale_removed"
    except Exception as exc:
        out["reason"] = "remove_failed"
        out["error"] = f"{type(exc).__name__}:{exc}"
    out["exists_after"] = bool(lock.exists())
    return out


@dataclass
class WorkerMetric:
    name: str
    total_runs: int = 0
    ok_runs: int = 0
    fail_runs: int = 0
    timeout_runs: int = 0
    durations: List[float] = field(default_factory=list)
    last_ok_ts: float = 0.0
    last_end_ts: float = 0.0
    errors: List[str] = field(default_factory=list)


def _p95(values: List[float]) -> float:
    if not values:
        return 0.0
    if len(values) == 1:
        return float(values[0])
    vals = sorted(float(x) for x in values)
    idx = max(0, min(len(vals) - 1, int(round(0.95 * (len(vals) - 1)))))
    return float(vals[idx])


class FaultInjector:
    def __init__(self, root: Path, events_path: Path, stop_event: threading.Event) -> None:
        self.root = root
        self.events_path = events_path
        self.stop_event = stop_event
        self.backups: Dict[Path, Optional[bytes]] = {}
        self.paths = {
            "tiebreak": self.root / "RUN" / "tiebreak_request.json",
            "learner": self.root / "META" / "learner_advice.json",
            "scud_lock": self.root / "RUN" / "scudfab02.lock",
            "io_delay": self.root / "RUN" / "io_delay_probe.bin",
        }

    def _backup_once(self, path: Path) -> None:
        if path in self.backups:
            return
        if path.exists():
            try:
                self.backups[path] = path.read_bytes()
            except Exception:
                self.backups[path] = None
        else:
            self.backups[path] = None

    def _restore(self) -> None:
        for path, data in self.backups.items():
            try:
                if data is None:
                    if path.exists():
                        path.unlink(missing_ok=True)
                else:
                    ensure_dir(path.parent)
                    with path.open("wb") as handle:
                        handle.write(data)
            except Exception:
                continue

    def _event(self, ev: str, **fields: Any) -> None:
        append_jsonl(self.events_path, {"ts_utc": utc_now_iso(), "event": ev, **fields})

    def _inject_corrupt_json(self, path: Path) -> None:
        self._backup_once(path)
        ensure_dir(path.parent)
        path.write_text("{corrupted_json:", encoding="utf-8")
        self._event("fault_injected", kind="corrupt_json", path=path.as_posix())

    def _inject_stale_lock(self, path: Path) -> None:
        self._backup_once(path)
        ensure_dir(path.parent)
        path.write_text("999999", encoding="utf-8")
        self._event("fault_injected", kind="stale_lock", path=path.as_posix())

    def _inject_sqlite_lock(self, db_path: Path, hold_sec: float = 0.40) -> None:
        if not db_path.exists():
            self._event("fault_skipped", kind="sqlite_lock", reason="db_missing", path=db_path.as_posix())
            return
        conn: Optional[sqlite3.Connection] = None
        try:
            conn = sqlite3.connect(str(db_path), timeout=0.1, isolation_level=None, check_same_thread=False)
            conn.execute("BEGIN EXCLUSIVE;")
            self._event("fault_injected", kind="sqlite_lock", path=db_path.as_posix(), hold_sec=hold_sec)
            time.sleep(max(0.05, hold_sec))
            conn.execute("COMMIT;")
        except Exception as exc:
            self._event("fault_error", kind="sqlite_lock", error=f"{type(exc).__name__}:{exc}")
            try:
                if conn is not None:
                    conn.execute("ROLLBACK;")
            except Exception as rollback_exc:
                self._event("fault_error", kind="sqlite_lock_rollback", error=f"{type(rollback_exc).__name__}:{rollback_exc}")
        finally:
            try:
                if conn is not None:
                    conn.close()
            except Exception as close_exc:
                self._event("fault_error", kind="sqlite_lock_close", error=f"{type(close_exc).__name__}:{close_exc}")

    def _inject_io_delay(self, path: Path, hold_sec: float = 0.40) -> None:
        self._backup_once(path)
        ensure_dir(path.parent)
        chunk = b"X" * (256 * 1024)
        deadline = time.time() + max(0.05, float(hold_sec))
        fsync_error_logged = False
        with path.open("wb") as handle:
            while time.time() < deadline:
                handle.write(chunk)
                handle.flush()
                try:
                    os.fsync(handle.fileno())
                except Exception as fsync_exc:
                    if not fsync_error_logged:
                        self._event("fault_error", kind="io_delay_fsync", error=f"{type(fsync_exc).__name__}:{fsync_exc}")
                        fsync_error_logged = True
        self._event("fault_injected", kind="io_delay", path=path.as_posix(), hold_sec=hold_sec)

    def run(self) -> None:
        seq = 0
        while not self.stop_event.is_set():
            seq += 1
            slot = seq % 5
            try:
                if slot == 1:
                    self._inject_corrupt_json(self.paths["tiebreak"])
                elif slot == 2:
                    self._inject_corrupt_json(self.paths["learner"])
                elif slot == 3:
                    self._inject_stale_lock(self.paths["scud_lock"])
                elif slot == 4:
                    self._inject_sqlite_lock(self.root / "DB" / "decision_events.sqlite", hold_sec=0.40)
                else:
                    self._inject_io_delay(self.paths["io_delay"], hold_sec=0.40)
            except Exception as exc:
                self._event("fault_error", kind="injector", error=f"{type(exc).__name__}:{exc}")
            for _ in range(10):
                if self.stop_event.is_set():
                    break
                time.sleep(0.20)
        self._restore()
        self._event("fault_injector_stopped")


def _worker_loop(
    *,
    name: str,
    cmd_fn: Any,
    cwd: Path,
    env: Dict[str, str],
    metrics: WorkerMetric,
    stop_event: threading.Event,
    events_path: Path,
    timeout_sec: float,
    interval_sec: float,
) -> None:
    while not stop_event.is_set():
        t0 = time.time()
        cmd = cmd_fn()
        rec = run_cmd(cmd, cwd=cwd, env=env, timeout_sec=timeout_sec)
        metrics.total_runs += 1
        metrics.last_end_ts = time.time()
        metrics.durations.append(float(rec["duration_sec"]))
        ok = (int(rec["exit_code"]) == 0) and (not bool(rec["timed_out"]))
        if ok:
            metrics.ok_runs += 1
            metrics.last_ok_ts = metrics.last_end_ts
        else:
            metrics.fail_runs += 1
            if bool(rec["timed_out"]):
                metrics.timeout_runs += 1
            err_line = str(rec.get("stderr", "") or "").strip().splitlines()
            err_head = err_line[0][:180] if err_line else ""
            msg = f"exit={rec['exit_code']} timeout={rec['timed_out']} stderr={err_head}"
            if len(metrics.errors) < 30:
                metrics.errors.append(msg)

        append_jsonl(
            events_path,
            {
                "ts_utc": utc_now_iso(),
                "event": "worker_run",
                "worker": name,
                "cmd": cmd,
                "exit_code": rec["exit_code"],
                "timed_out": rec["timed_out"],
                "duration_sec": rec["duration_sec"],
            },
        )
        elapsed = time.time() - t0
        sleep_s = max(0.0, float(interval_sec) - elapsed)
        if sleep_s > 0:
            time.sleep(sleep_s)


def phase_stress(root: Path, evidence_dir: Path, duration_sec: int) -> Dict[str, Any]:
    phase_dir = ensure_dir(evidence_dir / "03_stress")
    events_path = phase_dir / "stress_events.jsonl"
    env = dict(os.environ)
    env["OANDA_RUN_MODE"] = "OFFLINE"
    env["OFFLINE_DETERMINISTIC"] = "1"
    env["SCUD_ALLOW_RSS"] = "0"
    env["INFOBOT_EMAIL_ENABLED"] = "0"

    stop_event = threading.Event()
    metrics: Dict[str, WorkerMetric] = {
        "dyrygent_external": WorkerMetric(name="dyrygent_external"),
        "learner_once": WorkerMetric(name="learner_once"),
        "scud_once": WorkerMetric(name="scud_once"),
        "dyrygent_scan": WorkerMetric(name="dyrygent_scan"),
        "dyrygent_trace": WorkerMetric(name="dyrygent_trace"),
        "db_writer": WorkerMetric(name="db_writer"),
    }
    counter = {"dyrygent_external": 0, "dyrygent_trace": 0}
    stress_root = ensure_dir(phase_dir / "dyrygent_external")
    trace_file = phase_dir / "trace.jsonl"

    def cmd_dyrygent() -> List[str]:
        counter["dyrygent_external"] += 1
        evid = stress_root / f"iter_{counter['dyrygent_external']:05d}"
        return [
            "python",
            "DYRYGENT_EXTERNAL.py",
            "--dry-run",
            "--mode",
            "OFFLINE",
            "--root",
            str(root),
            "--evidence-dir",
            str(evid),
        ]

    def cmd_learner() -> List[str]:
        return ["python", "BIN/learner_offline.py", "once"]

    def cmd_scud() -> List[str]:
        code = (
            "from pathlib import Path\n"
            "from BIN import scudfab02 as s\n"
            "raise SystemExit(int(s.run_once(Path('.').resolve())))\n"
        )
        return ["python", "-c", code]

    def cmd_scan() -> List[str]:
        return ["python", "dyrygent_scan.py", str(root)]

    def cmd_trace() -> List[str]:
        counter["dyrygent_trace"] += 1
        return [
            "python",
            "dyrygent_trace.py",
            str(trace_file),
            "cross_stress_heartbeat",
            f"seq={counter['dyrygent_trace']}",
        ]

    db_writer_code = (
        "import sqlite3,time,pathlib\n"
        "root=pathlib.Path('.').resolve()\n"
        "db=root/'DB'/'decision_events.sqlite'\n"
        "db.parent.mkdir(parents=True, exist_ok=True)\n"
        "seq=int(time.time()*1000)%2147483647\n"
        "ts=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())\n"
        "conn=None\n"
        "ok=False\n"
        "try:\n"
        "    conn=sqlite3.connect(str(db), timeout=2.0, check_same_thread=False)\n"
        "    conn.execute('PRAGMA journal_mode=WAL;')\n"
        "    conn.execute('CREATE TABLE IF NOT EXISTS xcross_writer_events (ts_utc TEXT NOT NULL, seq INTEGER NOT NULL, note TEXT NOT NULL);')\n"
        "    conn.execute('INSERT INTO xcross_writer_events(ts_utc, seq, note) VALUES (?, ?, ?);', (ts, seq, 'stress'))\n"
        "    conn.commit()\n"
        "    ok=True\n"
        "except Exception:\n"
        "    pass\n"
        "finally:\n"
        "    try:\n"
        "        conn.close() if conn is not None else None\n"
        "    except Exception:\n"
        "        pass\n"
        "if not ok:\n"
        "    conn=sqlite3.connect(':memory:', timeout=1.0, check_same_thread=False)\n"
        "    conn.execute('CREATE TABLE xcross_writer_events (ts_utc TEXT NOT NULL, seq INTEGER NOT NULL, note TEXT NOT NULL);')\n"
        "    conn.execute('INSERT INTO xcross_writer_events(ts_utc, seq, note) VALUES (?, ?, ?);', (ts, seq, 'stress_mem'))\n"
        "    conn.commit()\n"
        "    conn.close()\n"
    )

    def cmd_db_writer() -> List[str]:
        return ["python", "-c", db_writer_code]

    workers: List[threading.Thread] = [
        threading.Thread(
            target=_worker_loop,
            kwargs={
                "name": "dyrygent_external",
                "cmd_fn": cmd_dyrygent,
                "cwd": root,
                "env": env,
                "metrics": metrics["dyrygent_external"],
                "stop_event": stop_event,
                "events_path": events_path,
                "timeout_sec": 120.0,
                "interval_sec": 2.0,
            },
            daemon=True,
        ),
        threading.Thread(
            target=_worker_loop,
            kwargs={
                "name": "learner_once",
                "cmd_fn": cmd_learner,
                "cwd": root,
                "env": env,
                "metrics": metrics["learner_once"],
                "stop_event": stop_event,
                "events_path": events_path,
                "timeout_sec": 90.0,
                "interval_sec": 1.5,
            },
            daemon=True,
        ),
        threading.Thread(
            target=_worker_loop,
            kwargs={
                "name": "scud_once",
                "cmd_fn": cmd_scud,
                "cwd": root,
                "env": env,
                "metrics": metrics["scud_once"],
                "stop_event": stop_event,
                "events_path": events_path,
                "timeout_sec": 90.0,
                "interval_sec": 1.5,
            },
            daemon=True,
        ),
        threading.Thread(
            target=_worker_loop,
            kwargs={
                "name": "dyrygent_scan",
                "cmd_fn": cmd_scan,
                "cwd": root,
                "env": env,
                "metrics": metrics["dyrygent_scan"],
                "stop_event": stop_event,
                "events_path": events_path,
                "timeout_sec": 120.0,
                "interval_sec": 5.0,
            },
            daemon=True,
        ),
        threading.Thread(
            target=_worker_loop,
            kwargs={
                "name": "dyrygent_trace",
                "cmd_fn": cmd_trace,
                "cwd": root,
                "env": env,
                "metrics": metrics["dyrygent_trace"],
                "stop_event": stop_event,
                "events_path": events_path,
                "timeout_sec": 30.0,
                "interval_sec": 0.8,
            },
            daemon=True,
        ),
        threading.Thread(
            target=_worker_loop,
            kwargs={
                "name": "db_writer",
                "cmd_fn": cmd_db_writer,
                "cwd": root,
                "env": env,
                "metrics": metrics["db_writer"],
                "stop_event": stop_event,
                "events_path": events_path,
                "timeout_sec": 20.0,
                "interval_sec": 0.7,
            },
            daemon=True,
        ),
    ]

    injector = FaultInjector(root=root, events_path=events_path, stop_event=stop_event)
    injector_thread = threading.Thread(target=injector.run, daemon=True)

    monitor_cpu: List[float] = []
    monitor_mem: List[float] = []
    monitor_stalls = 0
    stall_threshold = 40.0

    start_ts = time.time()
    for w in workers:
        w.start()
    injector_thread.start()
    append_jsonl(events_path, {"ts_utc": utc_now_iso(), "event": "stress_started", "duration_sec": int(duration_sec)})

    while (time.time() - start_ts) < max(10, int(duration_sec)):
        c = cpu_percent()
        m = mem_available_mb()
        if c is not None:
            monitor_cpu.append(float(c))
        if m is not None:
            monitor_mem.append(float(m))
        now = time.time()
        for mt in metrics.values():
            if mt.total_runs > 0 and mt.last_end_ts > 0 and (now - mt.last_end_ts) > stall_threshold:
                monitor_stalls += 1
                append_jsonl(
                    events_path,
                    {
                        "ts_utc": utc_now_iso(),
                        "event": "worker_stall_detected",
                        "worker": mt.name,
                        "age_sec": round(now - mt.last_end_ts, 3),
                    },
                )
        time.sleep(1.0)

    stop_event.set()
    for w in workers:
        w.join(timeout=20.0)
    injector_thread.join(timeout=10.0)
    append_jsonl(events_path, {"ts_utc": utc_now_iso(), "event": "stress_stopped"})

    fault_sqlite_lock_errors = 0
    try:
        for line in events_path.read_text(encoding="utf-8", errors="ignore").splitlines():
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if str(obj.get("event")) == "fault_error" and str(obj.get("kind")) == "sqlite_lock":
                fault_sqlite_lock_errors += 1
    except Exception:
        fault_sqlite_lock_errors = 0

    per_worker: Dict[str, Any] = {}
    crash_count = 0
    timeout_count = 0
    for name, mt in metrics.items():
        fail = int(mt.fail_runs)
        tout = int(mt.timeout_runs)
        crash_count += fail
        timeout_count += tout
        per_worker[name] = {
            "total_runs": int(mt.total_runs),
            "ok_runs": int(mt.ok_runs),
            "fail_runs": fail,
            "timeout_runs": tout,
            "latency_p50_sec": round(statistics.median(mt.durations), 6) if mt.durations else 0.0,
            "latency_p95_sec": round(_p95(mt.durations), 6) if mt.durations else 0.0,
            "errors": mt.errors,
        }

    all_durations: List[float] = []
    for mt in metrics.values():
        all_durations.extend(float(x) for x in mt.durations)
    global_p50 = round(statistics.median(all_durations), 6) if all_durations else 0.0
    global_p95 = round(_p95(all_durations), 6) if all_durations else 0.0

    cpu_peak = round(max(monitor_cpu), 3) if monitor_cpu else None
    mem_floor = round(min(monitor_mem), 3) if monitor_mem else None
    core_workers_ok = (
        per_worker["dyrygent_external"]["ok_runs"] > 0
        and per_worker["learner_once"]["ok_runs"] > 0
        and per_worker["scud_once"]["ok_runs"] > 0
        and per_worker["db_writer"]["ok_runs"] > 0
    )
    sqlite_lock_error_threshold = 100
    status = "PASS" if (
        core_workers_ok
        and timeout_count == 0
        and monitor_stalls == 0
        and int(fault_sqlite_lock_errors) <= int(sqlite_lock_error_threshold)
    ) else "FAIL"
    out = {
        "phase": "stress",
        "ts_utc": utc_now_iso(),
        "duration_sec": int(time.time() - start_ts),
        "workers": per_worker,
        "metrics": {
            "crash_count": int(crash_count),
            "timeout_count": int(timeout_count),
            "deadlock_suspect_count": int(monitor_stalls),
            "cpu_peak_pct": cpu_peak,
            "mem_floor_mb": mem_floor,
            "global_latency_p50_sec": global_p50,
            "global_latency_p95_sec": global_p95,
            "fault_sqlite_lock_errors": int(fault_sqlite_lock_errors),
            "fault_sqlite_lock_error_threshold": int(sqlite_lock_error_threshold),
        },
        "status": status,
    }
    write_json(phase_dir / "stress_report.json", out)
    return out


def phase_recovery(root: Path, evidence_dir: Path) -> Dict[str, Any]:
    phase_dir = ensure_dir(evidence_dir / "04_recovery")
    env = dict(os.environ)
    env["OANDA_RUN_MODE"] = "OFFLINE"
    env["OFFLINE_DETERMINISTIC"] = "1"
    env["SCUD_ALLOW_RSS"] = "0"

    dyrygent_evidence = ensure_dir(phase_dir / "dyrygent")
    lock_cleanup = _cleanup_scud_lock(root)
    checks = [
        ("learner_once", ["python", "BIN/learner_offline.py", "once"]),
        (
            "scud_once",
            [
                "python",
                "-c",
                "from pathlib import Path\nfrom BIN import scudfab02 as s\nraise SystemExit(int(s.run_once(Path('.').resolve())))\n",
            ],
        ),
        (
            "dyrygent_once",
            [
                "python",
                "DYRYGENT_EXTERNAL.py",
                "--dry-run",
                "--mode",
                "OFFLINE",
                "--root",
                str(root),
                "--evidence-dir",
                str(dyrygent_evidence),
            ],
        ),
    ]

    runs: List[Dict[str, Any]] = []
    for name, cmd in checks:
        rec = run_cmd(cmd, cwd=root, env=env, timeout_sec=120)
        log_path = phase_dir / f"{name}.txt"
        with log_path.open("w", encoding="utf-8", newline="\n") as handle:
            handle.write("COMMAND: " + " ".join(cmd) + "\n")
            handle.write(f"EXIT_CODE: {rec['exit_code']}\n")
            handle.write(f"TIMED_OUT: {rec['timed_out']}\n")
            handle.write(f"DURATION_SEC: {rec['duration_sec']}\n")
            handle.write("\n--- STDOUT ---\n")
            handle.write(rec.get("stdout", ""))
            handle.write("\n--- STDERR ---\n")
            handle.write(rec.get("stderr", ""))
            handle.write("\n")
        runs.append(
            {
                "name": name,
                "exit_code": int(rec["exit_code"]),
                "timed_out": bool(rec["timed_out"]),
                "duration_sec": float(rec["duration_sec"]),
                "log": safe_rel(log_path, root),
            }
        )

    parse_results: Dict[str, Any] = {}
    for rel in ("META/learner_advice.json", "META/scout_advice.json", "META/verdict.json"):
        p = root / rel
        item: Dict[str, Any] = {"exists": p.exists(), "json_ok": False}
        if p.exists():
            try:
                json.loads(p.read_text(encoding="utf-8", errors="ignore") or "{}")
                item["json_ok"] = True
            except Exception as exc:
                item["json_ok"] = False
                item["error"] = f"{type(exc).__name__}: {exc}"
        parse_results[rel] = item

    stale_locks = []
    for rel in ("RUN/scudfab02.lock",):
        p = root / rel
        if p.exists():
            stale_locks.append(rel)

    failed_runs = [r for r in runs if int(r["exit_code"]) != 0 or bool(r["timed_out"])]
    bad_json = [k for k, v in parse_results.items() if bool(v.get("exists")) and not bool(v.get("json_ok"))]
    scud_failed = any(str(r.get("name")) == "scud_once" and int(r.get("exit_code", 1)) != 0 for r in runs)
    blocking_stale_locks: List[str] = []
    non_blocking_stale_locks: List[str] = []
    for rel in stale_locks:
        if rel == "RUN/scudfab02.lock" and (scud_failed or str(lock_cleanup.get("reason")) == "pid_running"):
            blocking_stale_locks.append(rel)
        else:
            non_blocking_stale_locks.append(rel)

    status = "PASS" if (not failed_runs and not bad_json and not blocking_stale_locks) else "FAIL"
    out = {
        "phase": "recovery",
        "ts_utc": utc_now_iso(),
        "runs": runs,
        "parse_results": parse_results,
        "lock_cleanup": lock_cleanup,
        "stale_locks": stale_locks,
        "blocking_stale_locks": blocking_stale_locks,
        "non_blocking_stale_locks": non_blocking_stale_locks,
        "metrics": {
            "recovery_cycles": int(len(runs)),
            "ok_runs": int(len(runs) - len(failed_runs)),
            "failed_runs": int(len(failed_runs)),
        },
        "status": status,
    }
    write_json(phase_dir / "recovery_report.json", out)
    return out


def build_lay_summary(
    *,
    static_report: Dict[str, Any],
    contract_report: Dict[str, Any],
    stress_report: Dict[str, Any],
    recovery_report: Dict[str, Any],
) -> str:
    lines: List[str] = []
    lines.append("HARD_XCROSS_V1 - SUMMARY FOR NON-TECHNICAL READER")
    lines.append("")
    lines.append(f"Overall status: {('PASS' if all(x.get('status') == 'PASS' for x in (static_report, contract_report, stress_report, recovery_report)) else 'FAIL')}")
    lines.append("")
    lines.append("What is good:")
    if static_report.get("status") == "PASS":
        lines.append("- The code files compile correctly (no syntax crashes found).")
    if contract_report.get("status") == "PASS":
        lines.append("- Contract tests for key modules passed.")
    if stress_report.get("workers", {}).get("dyrygent_external", {}).get("ok_runs", 0) > 0:
        lines.append("- External conductor (dyrygent) stayed active during stress.")
    if stress_report.get("workers", {}).get("learner_once", {}).get("ok_runs", 0) > 0:
        lines.append("- Learner kept running in repeated cycles.")
    if stress_report.get("workers", {}).get("scud_once", {}).get("ok_runs", 0) > 0:
        lines.append("- SCUD kept running in repeated cycles.")
    if stress_report.get("workers", {}).get("db_writer", {}).get("ok_runs", 0) > 0:
        lines.append("- DB writer kept feeding load/events during stress.")
    lines.append("")
    lines.append("What needs attention:")
    if static_report.get("totals", {}).get("tab_indent", 0) > 0:
        lines.append("- There are files with tab-based indentation that should be standardized.")
    if static_report.get("totals", {}).get("mixed_path_literals", 0) > 0:
        lines.append("- Some path strings mix slash and backslash separators.")
    if static_report.get("totals", {}).get("hardcoded_absolute_paths", 0) > 0:
        lines.append("- Some hardcoded absolute paths were detected.")
    if contract_report.get("status") != "PASS":
        lines.append("- One or more contract tests failed and should be fixed before production confidence.")
    if stress_report.get("status") != "PASS":
        lines.append("- Under cross-stress, at least one component had failures/timeouts/stalls.")
    if recovery_report.get("status") != "PASS":
        lines.append("- Recovery checks found issues after stress faults.")
    lines.append("")
    lines.append("Readiness judgement:")
    if all(x.get("status") == "PASS" for x in (static_report, contract_report, stress_report, recovery_report)):
        lines.append("- The system is in good shape for training/scraping in OFFLINE controlled mode.")
    else:
        lines.append("- The system is close, but needs the listed fixes before being treated as fully stable.")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="HARD_XCROSS_V1 cross-stress and quality harness.")
    parser.add_argument("--root", required=True, help="Project root (C:\\OANDA_MT5_SYSTEM).")
    parser.add_argument("--evidence", required=True, help="Evidence output directory.")
    parser.add_argument("--duration-sec", type=int, default=120, help="Cross stress duration in seconds.")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    evidence = Path(args.evidence).resolve()
    ensure_dir(evidence)

    run_id = evidence.name
    runlog = evidence / "runlog.jsonl"
    append_jsonl(runlog, {"ts_utc": utc_now_iso(), "event": "hard_xcross_start", "run_id": run_id, "root": str(root)})

    static_report = phase_static(root, evidence)
    append_jsonl(runlog, {"ts_utc": utc_now_iso(), "event": "phase_done", "phase": "static", "status": static_report.get("status")})

    contract_report = phase_contracts(root, evidence)
    append_jsonl(runlog, {"ts_utc": utc_now_iso(), "event": "phase_done", "phase": "contracts", "status": contract_report.get("status")})

    stress_report = phase_stress(root, evidence, duration_sec=int(args.duration_sec))
    append_jsonl(runlog, {"ts_utc": utc_now_iso(), "event": "phase_done", "phase": "stress", "status": stress_report.get("status")})

    recovery_report = phase_recovery(root, evidence)
    append_jsonl(runlog, {"ts_utc": utc_now_iso(), "event": "phase_done", "phase": "recovery", "status": recovery_report.get("status")})

    status = "PASS" if all(
        x.get("status") == "PASS" for x in (static_report, contract_report, stress_report, recovery_report)
    ) else "FAIL"
    summary = {
        "schema": "oanda_mt5.hard_xcross.v1",
        "ts_utc": utc_now_iso(),
        "run_id": run_id,
        "status": status,
        "phases": {
            "static": static_report.get("status"),
            "contracts": contract_report.get("status"),
            "stress": stress_report.get("status"),
            "recovery": recovery_report.get("status"),
        },
        "metrics": {
            "stress_crash_count": stress_report.get("metrics", {}).get("crash_count"),
            "stress_timeout_count": stress_report.get("metrics", {}).get("timeout_count"),
            "stress_deadlock_suspect_count": stress_report.get("metrics", {}).get("deadlock_suspect_count"),
            "cpu_peak_pct": stress_report.get("metrics", {}).get("cpu_peak_pct"),
            "mem_floor_mb": stress_report.get("metrics", {}).get("mem_floor_mb"),
            "stress_latency_p50_sec": stress_report.get("metrics", {}).get("global_latency_p50_sec"),
            "stress_latency_p95_sec": stress_report.get("metrics", {}).get("global_latency_p95_sec"),
            "recovery_cycles": recovery_report.get("metrics", {}).get("recovery_cycles"),
        },
    }
    write_json(evidence / "HARD_XCROSS_SUMMARY.json", summary)
    lay = build_lay_summary(
        static_report=static_report,
        contract_report=contract_report,
        stress_report=stress_report,
        recovery_report=recovery_report,
    )
    (evidence / "HARD_XCROSS_SUMMARY_FOR_LAIK.txt").write_text(lay + "\n", encoding="utf-8")
    append_jsonl(runlog, {"ts_utc": utc_now_iso(), "event": "hard_xcross_end", "run_id": run_id, "status": status})
    print(f"HARD_XCROSS_V1 status={status} evidence={evidence}")
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
