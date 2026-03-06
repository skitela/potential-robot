#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ctypes
import datetime as dt
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    from TOOLS.lab_guardrails import ensure_write_parent, resolve_lab_data_root
    from TOOLS.lab_registry import connect_registry, init_registry_schema, insert_job_run
    from TOOLS.runtime_stability_cycle import read_window_phase
except Exception:  # pragma: no cover
    from lab_guardrails import ensure_write_parent, resolve_lab_data_root
    from lab_registry import connect_registry, init_registry_schema, insert_job_run
    from runtime_stability_cycle import read_window_phase

UTC = dt.timezone.utc


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def set_low_priority_best_effort() -> str:
    # Preferred path: psutil on Windows (clear error surfaces, no raw WinAPI handling).
    try:
        if os.name == "nt":
            import psutil  # type: ignore

            proc = psutil.Process(os.getpid())
            proc.nice(psutil.BELOW_NORMAL_PRIORITY_CLASS)
            return "OK_PSUTIL"
    except Exception:
        # Fallback to WinAPI path below.
        pass
    try:
        if os.name != "nt":
            return "UNSUPPORTED_NON_WINDOWS"
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        from ctypes import wintypes

        get_current_process = kernel32.GetCurrentProcess
        get_current_process.argtypes = []
        get_current_process.restype = wintypes.HANDLE
        set_priority_class = kernel32.SetPriorityClass
        set_priority_class.argtypes = [wintypes.HANDLE, wintypes.DWORD]
        set_priority_class.restype = wintypes.BOOL

        process = get_current_process()
        BELOW_NORMAL_PRIORITY_CLASS = 0x00004000
        ok = bool(set_priority_class(process, BELOW_NORMAL_PRIORITY_CLASS))
        if ok:
            return "OK_WINAPI"
        err = int(ctypes.get_last_error())
        return f"FAILED_WINAPI:{err}"
    except Exception as exc:
        return f"ERROR:{type(exc).__name__}"


def _cpu_pct_windows(sample_sec: float = 0.15) -> Optional[float]:
    try:
        class FILETIME(ctypes.Structure):
            _fields_ = [("dwLowDateTime", ctypes.c_uint32), ("dwHighDateTime", ctypes.c_uint32)]

        def _ft_to_int(ft: FILETIME) -> int:
            return (int(ft.dwHighDateTime) << 32) | int(ft.dwLowDateTime)

        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        idle1, kern1, user1 = FILETIME(), FILETIME(), FILETIME()
        ok1 = kernel32.GetSystemTimes(ctypes.byref(idle1), ctypes.byref(kern1), ctypes.byref(user1))
        if not ok1:
            return None
        time.sleep(max(0.05, min(0.5, float(sample_sec))))
        idle2, kern2, user2 = FILETIME(), FILETIME(), FILETIME()
        ok2 = kernel32.GetSystemTimes(ctypes.byref(idle2), ctypes.byref(kern2), ctypes.byref(user2))
        if not ok2:
            return None
        idle_delta = _ft_to_int(idle2) - _ft_to_int(idle1)
        kern_delta = _ft_to_int(kern2) - _ft_to_int(kern1)
        user_delta = _ft_to_int(user2) - _ft_to_int(user1)
        total = kern_delta + user_delta
        if total <= 0:
            return None
        busy = max(0, total - idle_delta)
        return float(max(0.0, min(100.0, 100.0 * (float(busy) / float(total)))))
    except Exception:
        return None


def read_mem_available_mb() -> Optional[float]:
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
        ok = ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(ms))
        if not ok:
            return None
        return float(ms.ullAvailPhys) / float(1024**2)
    except Exception:
        return None


class FileLock:
    def __init__(self, lock_path: Path, *, stale_after_sec: int = 0) -> None:
        self.lock_path = lock_path
        self.fd: Optional[int] = None
        self.stale_after_sec = max(0, int(stale_after_sec))

    def _is_stale(self) -> bool:
        if self.stale_after_sec <= 0:
            return False
        try:
            mtime = self.lock_path.stat().st_mtime
            age = max(0.0, time.time() - float(mtime))
            return age >= float(self.stale_after_sec)
        except Exception:
            return False

    def acquire(self) -> bool:
        self.lock_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            self.fd = os.open(str(self.lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(self.fd, str(os.getpid()).encode("ascii", errors="ignore"))
            return True
        except FileExistsError:
            if self._is_stale():
                try:
                    self.lock_path.unlink()
                    self.fd = os.open(str(self.lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                    os.write(self.fd, str(os.getpid()).encode("ascii", errors="ignore"))
                    return True
                except Exception:
                    return False
            return False

    def release(self) -> None:
        try:
            if self.fd is not None:
                os.close(self.fd)
                self.fd = None
        finally:
            try:
                if self.lock_path.exists():
                    self.lock_path.unlink()
            except Exception as exc:
                _ = exc
def write_status(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run_cmd(cmd: List[str], *, cwd: Path, timeout_sec: int) -> Dict[str, Any]:
    t0 = time.perf_counter()
    try:
        cp = subprocess.run(
            cmd,
            cwd=str(cwd),
            capture_output=True,
            text=True,
            timeout=max(30, int(timeout_sec)),
            check=False,
        )
        return {
            "rc": int(cp.returncode),
            "duration_sec": round(float(time.perf_counter() - t0), 3),
            "stdout_tail": (cp.stdout or "").splitlines()[-40:],
            "stderr_tail": (cp.stderr or "").splitlines()[-40:],
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "rc": 124,
            "duration_sec": round(float(time.perf_counter() - t0), 3),
            "stdout_tail": str(getattr(exc, "stdout", "") or "").splitlines()[-40:],
            "stderr_tail": str(getattr(exc, "stderr", "") or "").splitlines()[-40:],
        }


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Safe scheduler for LAB daily ingest + pipeline.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--python", default=sys.executable)
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--lookback-days", type=int, default=180)
    ap.add_argument("--horizon-minutes", type=int, default=60)
    ap.add_argument("--focus-group", default="FX")
    ap.add_argument("--timeframes", default="M1")
    ap.add_argument("--timeout-sec", type=int, default=1800)
    ap.add_argument("--snapshot-retention-days", type=int, default=14)
    ap.add_argument("--skip-snapshot-retention", action="store_true")
    ap.add_argument("--max-cpu-pct", type=float, default=85.0)
    ap.add_argument("--min-mem-mb", type=float, default=1024.0)
    ap.add_argument("--lock-stale-minutes", type=int, default=240)
    ap.add_argument("--allow-active-window", action="store_true")
    ap.add_argument("--force", action="store_true")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    run_root = (lab_data_root / "run").resolve()
    run_root.mkdir(parents=True, exist_ok=True)
    registry_path = (lab_data_root / "registry" / "lab_registry.sqlite").resolve()

    stale_after_sec = max(0, int(args.lock_stale_minutes)) * 60
    lock = FileLock(run_root / "lab_scheduler.lock", stale_after_sec=stale_after_sec)
    status_path = run_root / "lab_scheduler_status.json"
    stamp = dt.datetime.now(tz=UTC).strftime("%Y%m%dT%H%M%SZ")
    started = dt.datetime.now(tz=UTC)
    run_id = f"SCHED_{stamp}"

    status: Dict[str, Any] = {
        "schema": "oanda_mt5.lab_scheduler_status.v1",
        "generated_at_utc": iso_utc(started),
        "run_id": run_id,
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "status": "INIT",
    }

    if not lock.acquire():
        status.update({"status": "SKIP", "reason": "LOCK_HELD"})
        write_status(status_path, status)
        print(f"LAB_SCHEDULER_SKIP reason=LOCK_HELD status_path={status_path}")
        return 0

    conn_reg = connect_registry(registry_path)
    init_registry_schema(conn_reg)
    try:
        priority = set_low_priority_best_effort()
        phase = read_window_phase((root / "LOGS" / "safetybot.log").resolve())
        phase_name = str(phase.get("phase") or "UNKNOWN").upper()
        cpu_pct = _cpu_pct_windows(0.15) if os.name == "nt" else None
        mem_mb = read_mem_available_mb() if os.name == "nt" else None

        if (not bool(args.allow_active_window)) and phase_name == "ACTIVE":
            finished = dt.datetime.now(tz=UTC)
            status.update(
                {
                    "status": "SKIP",
                    "reason": "ACTIVE_WINDOW",
                    "window_phase": phase,
                    "priority_set": priority,
                    "finished_at_utc": iso_utc(finished),
                }
            )
            write_status(status_path, status)
            insert_job_run(
                conn_reg,
                {
                    "run_id": run_id,
                    "run_type": "SCHEDULER_DAILY",
                    "started_at_utc": iso_utc(started),
                    "finished_at_utc": iso_utc(finished),
                    "status": "SKIP",
                    "source_type": "MT5_LOCAL",
                    "dataset_hash": "",
                    "config_hash": "",
                    "readiness": "N/A",
                    "reason": "ACTIVE_WINDOW",
                    "evidence_path": str(status_path),
                    "details_json": json.dumps({"window_phase": phase, "priority_set": priority}, ensure_ascii=False),
                },
            )
            print(f"LAB_SCHEDULER_SKIP reason=ACTIVE_WINDOW status_path={status_path}")
            return 0

        if cpu_pct is not None and float(cpu_pct) >= float(args.max_cpu_pct):
            finished = dt.datetime.now(tz=UTC)
            status.update(
                {
                    "status": "SKIP",
                    "reason": "CPU_HIGH",
                    "resource_governor": {"cpu_pct": cpu_pct, "mem_available_mb": mem_mb},
                    "finished_at_utc": iso_utc(finished),
                }
            )
            write_status(status_path, status)
            insert_job_run(
                conn_reg,
                {
                    "run_id": run_id,
                    "run_type": "SCHEDULER_DAILY",
                    "started_at_utc": iso_utc(started),
                    "finished_at_utc": iso_utc(finished),
                    "status": "SKIP",
                    "source_type": "MT5_LOCAL",
                    "dataset_hash": "",
                    "config_hash": "",
                    "readiness": "N/A",
                    "reason": "CPU_HIGH",
                    "evidence_path": str(status_path),
                    "details_json": json.dumps(
                        {"resource_governor": {"cpu_pct": cpu_pct, "mem_available_mb": mem_mb}},
                        ensure_ascii=False,
                    ),
                },
            )
            print(f"LAB_SCHEDULER_SKIP reason=CPU_HIGH status_path={status_path}")
            return 0
        if mem_mb is not None and float(mem_mb) < float(args.min_mem_mb):
            finished = dt.datetime.now(tz=UTC)
            status.update(
                {
                    "status": "SKIP",
                    "reason": "MEM_LOW",
                    "resource_governor": {"cpu_pct": cpu_pct, "mem_available_mb": mem_mb},
                    "finished_at_utc": iso_utc(finished),
                }
            )
            write_status(status_path, status)
            insert_job_run(
                conn_reg,
                {
                    "run_id": run_id,
                    "run_type": "SCHEDULER_DAILY",
                    "started_at_utc": iso_utc(started),
                    "finished_at_utc": iso_utc(finished),
                    "status": "SKIP",
                    "source_type": "MT5_LOCAL",
                    "dataset_hash": "",
                    "config_hash": "",
                    "readiness": "N/A",
                    "reason": "MEM_LOW",
                    "evidence_path": str(status_path),
                    "details_json": json.dumps(
                        {"resource_governor": {"cpu_pct": cpu_pct, "mem_available_mb": mem_mb}},
                        ensure_ascii=False,
                    ),
                },
            )
            print(f"LAB_SCHEDULER_SKIP reason=MEM_LOW status_path={status_path}")
            return 0

        ingest_out = ensure_write_parent(
            lab_data_root / "reports" / "ingest" / f"lab_mt5_ingest_{stamp}.json",
            root=root,
            lab_data_root=lab_data_root,
        )
        ingest_cmd = [
            str(args.python),
            "-B",
            str((root / "TOOLS" / "lab_mt5_history_ingest.py").resolve()),
            "--root",
            str(root),
            "--lab-data-root",
            str(lab_data_root),
            "--focus-group",
            str(args.focus_group),
            "--timeframes",
            str(args.timeframes),
            "--lookback-days",
            str(max(1, int(args.lookback_days))),
            "--out",
            str(ingest_out),
        ]
        ingest_res = run_cmd(ingest_cmd, cwd=root, timeout_sec=max(120, int(args.timeout_sec)))
        ingest_payload: Dict[str, Any] = {}
        if ingest_out.exists():
            try:
                ingest_payload = json.loads(ingest_out.read_text(encoding="utf-8"))
            except Exception:
                ingest_payload = {}
        ingest_status = str(ingest_payload.get("status") or ("PASS" if ingest_res["rc"] == 0 else "FAIL")).upper()

        pipeline_res: Dict[str, Any] = {"rc": None, "stdout_tail": [], "stderr_tail": []}
        pipeline_out = ensure_write_parent(
            lab_data_root / "reports" / "daily" / f"lab_daily_report_{stamp}.json",
            root=root,
            lab_data_root=lab_data_root,
        )
        if ingest_status == "PASS":
            pipeline_cmd = [
                str(args.python),
                "-B",
                str((root / "TOOLS" / "lab_daily_pipeline.py").resolve()),
                "--root",
                str(root),
                "--lab-data-root",
                str(lab_data_root),
                "--focus-group",
                str(args.focus_group),
                "--lookback-days",
                str(max(1, int(args.lookback_days))),
                "--horizon-minutes",
                str(max(1, int(args.horizon_minutes))),
                "--daily-guard",
                "--out",
                str(pipeline_out),
            ]
            if bool(args.force):
                pipeline_cmd.append("--force")
            pipeline_res = run_cmd(pipeline_cmd, cwd=root, timeout_sec=max(120, int(args.timeout_sec)))
            final_status = "PASS" if int(pipeline_res["rc"]) == 0 else "FAIL"
            reason = "INGEST_PASS_PIPELINE_PASS" if final_status == "PASS" else "PIPELINE_FAIL"
        elif ingest_status == "SKIP":
            final_status = "SKIP"
            reason = "INGEST_SKIP"
        else:
            final_status = "FAIL"
            reason = "INGEST_FAIL"

        retention_res: Dict[str, Any] = {"rc": None, "stdout_tail": [], "stderr_tail": []}
        retention_out = ensure_write_parent(
            lab_data_root / "reports" / "retention" / f"lab_snapshot_retention_{stamp}.json",
            root=root,
            lab_data_root=lab_data_root,
        )
        if not bool(args.skip_snapshot_retention):
            retention_cmd = [
                str(args.python),
                "-B",
                str((root / "TOOLS" / "lab_snapshot_retention.py").resolve()),
                "--root",
                str(root),
                "--lab-data-root",
                str(lab_data_root),
                "--keep-days",
                str(max(1, int(args.snapshot_retention_days))),
                "--apply",
                "--out",
                str(retention_out),
            ]
            retention_res = run_cmd(retention_cmd, cwd=root, timeout_sec=max(120, int(args.timeout_sec)))

        finished = dt.datetime.now(tz=UTC)
        status.update(
            {
                "status": final_status,
                "reason": reason,
                "python_executable": str(args.python),
                "window_phase": phase,
                "priority_set": priority,
                "resource_governor": {"cpu_pct": cpu_pct, "mem_available_mb": mem_mb},
                "ingest": {
                    "cmd": ingest_cmd,
                    "rc": ingest_res["rc"],
                    "stdout_tail": ingest_res["stdout_tail"],
                    "stderr_tail": ingest_res["stderr_tail"],
                    "report_path": str(ingest_out),
                    "status_from_report": ingest_status,
                },
                "pipeline": {
                    "rc": pipeline_res["rc"],
                    "stdout_tail": pipeline_res["stdout_tail"],
                    "stderr_tail": pipeline_res["stderr_tail"],
                    "report_path": str(pipeline_out),
                },
                "snapshot_retention": {
                    "enabled": not bool(args.skip_snapshot_retention),
                    "keep_days": int(args.snapshot_retention_days),
                    "rc": retention_res["rc"],
                    "stdout_tail": retention_res["stdout_tail"],
                    "stderr_tail": retention_res["stderr_tail"],
                    "report_path": str(retention_out),
                },
                "finished_at_utc": iso_utc(finished),
            }
        )
        write_status(status_path, status)

        insert_job_run(
            conn_reg,
            {
                "run_id": run_id,
                "run_type": "SCHEDULER_DAILY",
                "started_at_utc": iso_utc(started),
                "finished_at_utc": iso_utc(finished),
                "status": final_status,
                "source_type": "MT5_LOCAL",
                "dataset_hash": str((ingest_payload or {}).get("dataset_hash") or ""),
                "config_hash": str((ingest_payload or {}).get("config_hash") or ""),
                "readiness": "N/A",
                "reason": reason,
                "evidence_path": str(status_path),
                "details_json": json.dumps(
                    {
                        "window_phase": phase,
                        "priority_set": priority,
                        "resource_governor": {"cpu_pct": cpu_pct, "mem_available_mb": mem_mb},
                        "ingest_rc": ingest_res["rc"],
                        "pipeline_rc": pipeline_res["rc"],
                        "snapshot_retention_rc": retention_res["rc"],
                    },
                    ensure_ascii=False,
                ),
            },
        )

        print(f"LAB_SCHEDULER_DONE status={final_status} reason={reason} status_path={status_path}")
        if final_status == "PASS":
            return 0
        if final_status == "SKIP":
            return 0
        return 1
    finally:
        conn_reg.close()
        lock.release()


if __name__ == "__main__":
    raise SystemExit(main())
