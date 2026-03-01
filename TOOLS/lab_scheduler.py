#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ctypes
import datetime as dt
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Optional

try:
    from TOOLS.lab_guardrails import ensure_write_parent, resolve_lab_data_root
    from TOOLS.runtime_stability_cycle import read_window_phase
except Exception:  # pragma: no cover
    from lab_guardrails import ensure_write_parent, resolve_lab_data_root
    from runtime_stability_cycle import read_window_phase

UTC = dt.timezone.utc


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def set_low_priority_best_effort() -> str:
    try:
        if os.name != "nt":
            return "UNSUPPORTED_NON_WINDOWS"
        process = ctypes.windll.kernel32.GetCurrentProcess()
        BELOW_NORMAL_PRIORITY_CLASS = 0x00004000
        ok = ctypes.windll.kernel32.SetPriorityClass(process, BELOW_NORMAL_PRIORITY_CLASS)
        return "OK" if ok else "FAILED"
    except Exception as exc:
        return f"ERROR:{type(exc).__name__}"


class FileLock:
    def __init__(self, lock_path: Path) -> None:
        self.lock_path = lock_path
        self.fd: Optional[int] = None

    def acquire(self) -> bool:
        self.lock_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            self.fd = os.open(str(self.lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(self.fd, str(os.getpid()).encode("ascii", errors="ignore"))
            return True
        except FileExistsError:
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
            except Exception:
                pass


def write_status(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Safe scheduler for LAB daily pipeline.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--python", default=sys.executable)
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--lookback-days", type=int, default=180)
    ap.add_argument("--horizon-minutes", type=int, default=60)
    ap.add_argument("--focus-group", default="FX")
    ap.add_argument("--timeout-sec", type=int, default=1800)
    ap.add_argument("--allow-active-window", action="store_true")
    ap.add_argument("--force", action="store_true")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    run_root = (lab_data_root / "run").resolve()
    run_root.mkdir(parents=True, exist_ok=True)

    lock = FileLock(run_root / "lab_scheduler.lock")
    status_path = run_root / "lab_scheduler_status.json"
    stamp = dt.datetime.now(tz=UTC).strftime("%Y%m%dT%H%M%SZ")

    status: Dict[str, Any] = {
        "schema": "oanda_mt5.lab_scheduler_status.v1",
        "generated_at_utc": iso_utc(dt.datetime.now(tz=UTC)),
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "status": "INIT",
    }

    if not lock.acquire():
        status.update(
            {
                "status": "SKIP_LOCK_HELD",
                "reason": "LOCK_HELD",
            }
        )
        write_status(status_path, status)
        print(f"LAB_SCHEDULER_SKIP reason=LOCK_HELD status_path={status_path}")
        return 0

    try:
        priority = set_low_priority_best_effort()
        phase = read_window_phase((root / "LOGS" / "safetybot.log").resolve())
        phase_name = str(phase.get("phase") or "UNKNOWN").upper()
        if (not bool(args.allow_active_window)) and phase_name == "ACTIVE":
            status.update(
                {
                    "status": "SKIP_ACTIVE_WINDOW",
                    "reason": "ACTIVE_WINDOW",
                    "window_phase": phase,
                    "priority_set": priority,
                }
            )
            write_status(status_path, status)
            print(f"LAB_SCHEDULER_SKIP reason=ACTIVE_WINDOW status_path={status_path}")
            return 0

        out_path = ensure_write_parent(
            lab_data_root / "reports" / "daily" / f"lab_daily_report_{stamp}.json",
            root=root,
            lab_data_root=lab_data_root,
        )
        cmd = [
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
            str(out_path),
        ]
        if bool(args.force):
            cmd.append("--force")

        cp = subprocess.run(
            cmd,
            cwd=str(root),
            capture_output=True,
            text=True,
            timeout=max(120, int(args.timeout_sec)),
            check=False,
        )
        status.update(
            {
                "status": "PASS" if int(cp.returncode) == 0 else "FAIL",
                "window_phase": phase,
                "priority_set": priority,
                "cmd": cmd,
                "rc": int(cp.returncode),
                "stdout_tail": (cp.stdout or "").splitlines()[-40:],
                "stderr_tail": (cp.stderr or "").splitlines()[-40:],
                "report_path": str(out_path),
            }
        )
        write_status(status_path, status)
        print(f"LAB_SCHEDULER_DONE status={status['status']} rc={status['rc']} status_path={status_path}")
        return 0 if int(cp.returncode) == 0 else int(cp.returncode)
    except subprocess.TimeoutExpired as exc:
        status.update(
            {
                "status": "TIMEOUT",
                "reason": "PIPELINE_TIMEOUT",
                "stdout_tail": str(getattr(exc, "stdout", "") or "").splitlines()[-40:],
                "stderr_tail": str(getattr(exc, "stderr", "") or "").splitlines()[-40:],
            }
        )
        write_status(status_path, status)
        print(f"LAB_SCHEDULER_FAIL status=TIMEOUT status_path={status_path}")
        return 124
    finally:
        lock.release()


if __name__ == "__main__":
    raise SystemExit(main())
