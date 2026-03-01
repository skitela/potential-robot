#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List


WINDOW_PHASE_RE = re.compile(r"WINDOW_PHASE\s+phase=([A-Z_]+)\s+window=([A-Z0-9_]+|NONE)")


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def resolve_python_exe(raw: str) -> str:
    cand = str(raw or "").strip()
    if cand:
        p = Path(cand)
        if p.is_file():
            return str(p)
    return str(sys.executable)


def read_window_phase(safety_log: Path, *, tail_lines: int = 4000) -> Dict[str, str]:
    if not safety_log.exists():
        return {"phase": "UNKNOWN", "window": "NONE", "source": "missing_log"}
    try:
        lines = safety_log.read_text(encoding="utf-8", errors="ignore").splitlines()[-max(50, int(tail_lines)) :]
    except Exception:
        return {"phase": "UNKNOWN", "window": "NONE", "source": "read_error"}
    for line in reversed(lines):
        m = WINDOW_PHASE_RE.search(str(line))
        if m:
            return {"phase": str(m.group(1)).upper(), "window": str(m.group(2)).upper(), "source": "safetybot.log"}
    return {"phase": "UNKNOWN", "window": "NONE", "source": "not_found"}


def run_cmd(cmd: List[str], *, cwd: Path, timeout_sec: int) -> Dict[str, Any]:
    t0 = time.perf_counter()
    try:
        cp = subprocess.run(
            cmd,
            cwd=str(cwd),
            capture_output=True,
            text=True,
            timeout=max(5, int(timeout_sec)),
            check=False,
        )
        rc = int(cp.returncode)
        out = (cp.stdout or "").splitlines()[-40:]
        err = (cp.stderr or "").splitlines()[-40:]
        status = "PASS" if rc == 0 else "FAIL"
    except subprocess.TimeoutExpired as exc:
        rc = 124
        out = str(getattr(exc, "stdout", "") or "").splitlines()[-40:]
        err = str(getattr(exc, "stderr", "") or "").splitlines()[-40:]
        status = "TIMEOUT"
    except Exception as exc:
        rc = 125
        out = []
        err = [f"{type(exc).__name__}: {exc}"]
        status = "ERROR"
    return {
        "cmd": cmd,
        "rc": rc,
        "status": status,
        "duration_sec": round(float(time.perf_counter() - t0), 3),
        "stdout_tail": out,
        "stderr_tail": err,
    }


def cycle_once(
    *,
    root: Path,
    python_exe: str,
    run_benchmark_outside_active: bool,
    timeout_sec: int,
) -> Dict[str, Any]:
    phase = read_window_phase((root / "LOGS" / "safetybot.log").resolve())
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    evidence_dir = (root / "EVIDENCE" / "runtime_stability_cycle").resolve()
    evidence_dir.mkdir(parents=True, exist_ok=True)
    hk_dir = (root / "EVIDENCE" / "housekeeping").resolve()
    hk_dir.mkdir(parents=True, exist_ok=True)

    tasks: List[Dict[str, Any]] = []
    phase_name = str(phase.get("phase") or "UNKNOWN").upper()

    # Lightweight tasks always allowed.
    tasks.append(
        run_cmd(
            [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str((root / "TOOLS" / "SYSTEM_CONTROL.ps1").resolve()),
                "-Action",
                "status",
                "-Profile",
                "safety_only",
            ],
            cwd=root,
            timeout_sec=timeout_sec,
        )
    )
    tasks[-1]["task"] = "system_control_status"

    tasks.append(
        run_cmd(
            [
                python_exe,
                "-B",
                str((root / "TOOLS" / "runtime_kpi_snapshot.py").resolve()),
                "--root",
                str(root),
                "--hours",
                "24",
                "--out",
                str((root / "EVIDENCE" / "runtime_kpi" / f"runtime_kpi_snapshot_{stamp}.json").resolve()),
            ],
            cwd=root,
            timeout_sec=timeout_sec,
        )
    )
    tasks[-1]["task"] = "runtime_kpi_snapshot"

    outside_active = phase_name != "ACTIVE"
    if outside_active:
        tasks.append(
            run_cmd(
                [
                    python_exe,
                    "-B",
                    str((root / "TOOLS" / "data_retention_cycle.py").resolve()),
                    "--root",
                    str(root),
                    "--policy",
                    str((root / "CONFIG" / "data_retention_policy.json").resolve()),
                    "--daily-guard",
                    "--apply",
                    "--out",
                    str((hk_dir / f"data_retention_cycle_{stamp}.json").resolve()),
                ],
                cwd=root,
                timeout_sec=max(60, int(timeout_sec)),
            )
        )
        tasks[-1]["task"] = "data_retention_cycle_daily"

        tasks.append(
            run_cmd(
                [
                    python_exe,
                    "-B",
                    str((root / "TOOLS" / "runtime_housekeeping.py").resolve()),
                    "--root",
                    str(root),
                    "--apply",
                    "--evidence",
                    str((hk_dir / f"runtime_housekeeping_{stamp}.json").resolve()),
                ],
                cwd=root,
                timeout_sec=timeout_sec,
            )
        )
        tasks[-1]["task"] = "runtime_housekeeping_apply"

        tasks.append(
            run_cmd(
                [
                    python_exe,
                    "-B",
                    str((root / "TOOLS" / "run_tmp_janitor.py").resolve()),
                    "--root",
                    str(root),
                    "--apply",
                    "--evidence",
                    str((hk_dir / f"run_tmp_janitor_{stamp}.json").resolve()),
                ],
                cwd=root,
                timeout_sec=timeout_sec,
            )
        )
        tasks[-1]["task"] = "run_tmp_janitor_apply"

        tasks.append(
            run_cmd(
                [
                    python_exe,
                    "-B",
                    str((root / "TOOLS" / "sqlite_maintenance.py").resolve()),
                    "--root",
                    str(root),
                    "--checkpoint-mode",
                    "PASSIVE",
                    "--out",
                    str((hk_dir / f"sqlite_maintenance_{stamp}.json").resolve()),
                ],
                cwd=root,
                timeout_sec=timeout_sec,
            )
        )
        tasks[-1]["task"] = "sqlite_maintenance_passive"

        tasks.append(
            run_cmd(
                [
                    python_exe,
                    "-B",
                    str((root / "TOOLS" / "shadow_policy_daily_report.py").resolve()),
                    "--root",
                    str(root),
                    "--lookback-days",
                    "3",
                    "--horizon-minutes",
                    "60",
                    "--daily-guard",
                    "--out",
                    str((root / "EVIDENCE" / "offline_replay" / "daily" / f"shadow_policy_daily_report_{stamp}.json").resolve()),
                ],
                cwd=root,
                timeout_sec=max(60, int(timeout_sec)),
            )
        )
        tasks[-1]["task"] = "shadow_policy_daily_report"

        if bool(run_benchmark_outside_active):
            tasks.append(
                run_cmd(
                    [
                        python_exe,
                        "-B",
                        str((root / "TOOLS" / "ranking_benchmark_strict_overlay.py").resolve()),
                        "--root",
                        str(root),
                    ],
                    cwd=root,
                    timeout_sec=max(30, int(timeout_sec) * 2),
                )
            )
            tasks[-1]["task"] = "ranking_benchmark_strict_overlay"

    report: Dict[str, Any] = {
        "schema": "oanda_mt5.runtime_stability_cycle.v1",
        "ts_utc": utc_now_iso(),
        "root": str(root),
        "window_phase": phase,
        "outside_active": bool(outside_active),
        "tasks": tasks,
        "status": "PASS",
    }
    if any(str(t.get("status")) in {"FAIL", "ERROR", "TIMEOUT"} for t in tasks):
        report["status"] = "PARTIAL_FAIL"

    out_path = evidence_dir / f"runtime_stability_cycle_{stamp}.json"
    out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    report["out"] = str(out_path)
    return report


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Run runtime stability cycle (light in ACTIVE, heavy outside ACTIVE).")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--python", default=sys.executable)
    ap.add_argument("--loop", action="store_true")
    ap.add_argument("--interval-sec", type=int, default=300)
    ap.add_argument("--timeout-sec", type=int, default=180)
    ap.add_argument("--run-benchmark-outside-active", action="store_true")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    python_exe = resolve_python_exe(str(args.python))
    interval = max(30, int(args.interval_sec))
    timeout_sec = max(30, int(args.timeout_sec))

    if not bool(args.loop):
        rep = cycle_once(
            root=root,
            python_exe=python_exe,
            run_benchmark_outside_active=bool(args.run_benchmark_outside_active),
            timeout_sec=timeout_sec,
        )
        print(
            f"RUNTIME_STABILITY_CYCLE_DONE status={rep['status']} phase={rep['window_phase'].get('phase')} out={rep.get('out')}"
        )
        return 0 if str(rep.get("status")) == "PASS" else 1

    while True:
        rep = cycle_once(
            root=root,
            python_exe=python_exe,
            run_benchmark_outside_active=bool(args.run_benchmark_outside_active),
            timeout_sec=timeout_sec,
        )
        print(
            f"RUNTIME_STABILITY_CYCLE_TICK status={rep['status']} phase={rep['window_phase'].get('phase')} out={rep.get('out')}"
        )
        time.sleep(float(interval))


if __name__ == "__main__":
    raise SystemExit(main())
