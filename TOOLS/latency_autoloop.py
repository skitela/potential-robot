#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Dict, List, Optional


def utc_iso() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def run_cmd(cmd: List[str], cwd: Path, timeout_sec: int) -> Dict[str, Any]:
    started = utc_iso()
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
            "cmd": cmd,
            "started_utc": started,
            "ended_utc": utc_iso(),
            "exit_code": int(cp.returncode),
            "stdout": str(cp.stdout or "").strip(),
            "stderr": str(cp.stderr or "").strip(),
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "cmd": cmd,
            "started_utc": started,
            "ended_utc": utc_iso(),
            "exit_code": 124,
            "stdout": str(exc.stdout or "").strip(),
            "stderr": f"TIMEOUT after {timeout_sec}s",
        }


def latest_compare_report(root: Path) -> Optional[Path]:
    p = root / "EVIDENCE" / "bridge_audit"
    files = sorted(
        [x for x in p.glob("bridge_soak_compare_*.json") if x.is_file()],
        key=lambda x: x.stat().st_mtime,
        reverse=True,
    )
    return files[0] if files else None


def load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Autonomous latency improvement loop with 20-minute soak cycles.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--max-attempts", type=int, default=15)
    ap.add_argument("--soak-sec", type=int, default=1200)
    ap.add_argument("--target-p95-ms", type=float, default=700.0)
    ap.add_argument("--target-p99-ms", type=float, default=850.0)
    ap.add_argument("--trade-min-samples", type=int, default=10)
    ap.add_argument("--retention-before-loop", action="store_true")
    ap.add_argument("--retention-every", type=int, default=0)
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    max_attempts = max(1, int(args.max_attempts))
    soak_sec = max(300, int(args.soak_sec))
    trade_min = max(1, int(args.trade_min_samples))
    target_p95 = float(args.target_p95_ms)
    target_p99 = float(args.target_p99_ms)

    out_dir = root / "EVIDENCE" / "latency_loops"
    out_dir.mkdir(parents=True, exist_ok=True)
    rid = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    run_json = out_dir / f"latency_autoloop_{rid}.json"
    run_txt = out_dir / f"latency_autoloop_{rid}.txt"
    status_path = root / "RUN" / "latency_autoloop_last.json"

    report: Dict[str, Any] = {
        "schema": "oanda_mt5.latency_autoloop.v1",
        "ts_utc": utc_iso(),
        "root": str(root),
        "config": {
            "max_attempts": max_attempts,
            "soak_sec": soak_sec,
            "target_p95_ms": target_p95,
            "target_p99_ms": target_p99,
            "trade_min_samples": trade_min,
            "retention_before_loop": bool(args.retention_before_loop),
            "retention_every": int(max(0, int(args.retention_every))),
        },
        "attempts": [],
        "result": {"status": "RUNNING", "reason": "LOOP_STARTED"},
    }

    def persist() -> None:
        payload = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
        run_json.write_text(payload, encoding="utf-8")
        status_path.parent.mkdir(parents=True, exist_ok=True)
        status_path.write_text(payload, encoding="utf-8")

    def add_note(line: str) -> None:
        with run_txt.open("a", encoding="utf-8") as fh:
            fh.write(line.rstrip() + "\n")

    persist()
    add_note(f"[{utc_iso()}] LATENCY_AUTOLOOP_START root={root} max_attempts={max_attempts} soak_sec={soak_sec}")

    def run_retention_cycle(tag: str) -> Dict[str, Any]:
        steps: List[Dict[str, Any]] = []
        steps.append(
            run_cmd(
                ["powershell", "-ExecutionPolicy", "Bypass", "-File", "TOOLS/SYSTEM_CONTROL.ps1", "stop"],
                root,
                timeout_sec=300,
            )
        )
        steps.append(
            run_cmd(
                ["python", "TOOLS/data_retention_cycle.py", "--root", str(root), "--apply", "--daily-guard"],
                root,
                timeout_sec=300,
            )
        )
        steps.append(
            run_cmd(
                ["powershell", "-ExecutionPolicy", "Bypass", "-File", "TOOLS/SYSTEM_CONTROL.ps1", "start"],
                root,
                timeout_sec=300,
            )
        )
        return {"tag": tag, "steps": steps}

    if bool(args.retention_before_loop):
        ret = run_retention_cycle("before_loop")
        report["retention_before_loop"] = ret
        persist()
        add_note(f"[{utc_iso()}] RETENTION_BEFORE_LOOP done")

    for attempt_idx in range(1, max_attempts + 1):
        attempt: Dict[str, Any] = {
            "attempt": attempt_idx,
            "ts_start_utc": utc_iso(),
            "actions": [],
        }
        add_note(f"[{utc_iso()}] ATTEMPT {attempt_idx}/{max_attempts} start")

        if int(args.retention_every) > 0 and attempt_idx > 1 and (attempt_idx % int(args.retention_every) == 0):
            ret = run_retention_cycle(f"attempt_{attempt_idx}")
            attempt["retention_cycle"] = ret
            add_note(f"[{utc_iso()}] ATTEMPT {attempt_idx} retention cycle done")

        st = run_cmd(
            ["powershell", "-ExecutionPolicy", "Bypass", "-File", "TOOLS/SYSTEM_CONTROL.ps1", "status"],
            root,
            timeout_sec=180,
        )
        attempt["actions"].append({"status_check": st})
        if int(st.get("exit_code", 1)) != 0 or "status=PASS" not in str(st.get("stdout", "")):
            start = run_cmd(
                ["powershell", "-ExecutionPolicy", "Bypass", "-File", "TOOLS/SYSTEM_CONTROL.ps1", "start"],
                root,
                timeout_sec=300,
            )
            attempt["actions"].append({"start_runtime": start})

        soak = run_cmd(
            [
                "powershell",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                "TOOLS/run_bridge_soak_audit.ps1",
                "-DurationSec",
                str(soak_sec),
                "-Root",
                str(root),
            ],
            root,
            timeout_sec=(soak_sec + 600),
        )
        attempt["actions"].append({"soak": soak})

        latest = latest_compare_report(root)
        if latest is None:
            attempt["analysis"] = {"status": "ERROR", "reason": "NO_SOAK_REPORT"}
            report["attempts"].append(attempt)
            report["result"] = {"status": "ERROR", "reason": "NO_SOAK_REPORT", "attempt": attempt_idx}
            persist()
            add_note(f"[{utc_iso()}] ATTEMPT {attempt_idx} ERROR no soak report")
            break

        rep = load_json(latest)
        m = ((rep.get("after_soak_window") or {}).get("metrics") or {})
        bw_trade = m.get("bridge_wait_trade_path") or {}
        bw_hb = m.get("bridge_wait_heartbeat") or {}
        trade_n = int(bw_trade.get("n") or 0)
        trade_p95 = bw_trade.get("p95_ms")
        trade_p99 = bw_trade.get("p99_ms")
        hb_p95 = bw_hb.get("p95_ms")
        timeout_rate = m.get("timeout_rate")
        analysis = {
            "report_path": str(latest),
            "report_status": (rep.get("verdict") or {}).get("status"),
            "trade_wait_n": trade_n,
            "trade_wait_p95_ms": trade_p95,
            "trade_wait_p99_ms": trade_p99,
            "hb_wait_p95_ms": hb_p95,
            "timeout_rate_all": timeout_rate,
            "goals": {
                "trade_p95_lt_target": bool(isinstance(trade_p95, (int, float)) and float(trade_p95) < target_p95),
                "trade_p99_lt_target": bool(isinstance(trade_p99, (int, float)) and float(trade_p99) < target_p99),
            },
        }
        attempt["analysis"] = analysis
        attempt["ts_end_utc"] = utc_iso()
        report["attempts"].append(attempt)
        persist()

        add_note(
            f"[{utc_iso()}] ATTEMPT {attempt_idx} trade_n={trade_n} trade_p95={trade_p95} "
            f"trade_p99={trade_p99} hb_p95={hb_p95} timeout_rate={timeout_rate}"
        )

        if trade_n >= trade_min and analysis["goals"]["trade_p95_lt_target"] and analysis["goals"]["trade_p99_lt_target"]:
            report["result"] = {
                "status": "TARGET_MET",
                "reason": "TRADE_PATH_P95_P99_BELOW_TARGET",
                "attempt": attempt_idx,
                "report_path": str(latest),
            }
            persist()
            add_note(f"[{utc_iso()}] TARGET_MET at attempt={attempt_idx}")
            break
        if attempt_idx >= max_attempts:
            report["result"] = {
                "status": "STOP_MAX_ATTEMPTS",
                "reason": "TARGET_NOT_REACHED_WITHIN_LIMIT",
                "attempt": attempt_idx,
                "report_path": str(latest),
            }
            persist()
            add_note(f"[{utc_iso()}] STOP_MAX_ATTEMPTS")
            break

    if report.get("result", {}).get("status") == "RUNNING":
        report["result"] = {"status": "STOPPED", "reason": "LOOP_FINISHED_WITHOUT_EXPLICIT_RESULT"}
        persist()

    print(f"LATENCY_AUTOLOOP_DONE status={report['result']['status']} out={run_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

