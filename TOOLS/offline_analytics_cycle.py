#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import datetime as dt
from pathlib import Path
from typing import Any, Dict, List

UTC = dt.timezone.utc


def now_utc() -> dt.datetime:
    return dt.datetime.now(tz=UTC)


def now_utc_iso() -> str:
    return now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z")


def atomic_write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    data = json.dumps(obj, ensure_ascii=False, indent=2) + "\n"
    try:
        tmp.write_text(data, encoding="utf-8")
        tmp.replace(path)
        return
    except Exception:
        path.write_text(data, encoding="utf-8")
        try:
            if tmp.exists():
                tmp.unlink()
        except Exception:
            pass


def run_cmd(cmd: List[str], *, cwd: Path, env: Dict[str, str], timeout_sec: int) -> Dict[str, Any]:
    t0 = time.time()
    try:
        p = subprocess.run(
            cmd,
            cwd=str(cwd),
            env=env,
            capture_output=True,
            text=True,
            timeout=max(10, int(timeout_sec)),
            check=False,
        )
        dur = time.time() - t0
        out_tail = (p.stdout or "").splitlines()[-40:]
        err_tail = (p.stderr or "").splitlines()[-40:]
        return {
            "ok": bool(p.returncode == 0),
            "rc": int(p.returncode),
            "duration_sec": round(float(dur), 3),
            "cmd": cmd,
            "stdout_tail": out_tail,
            "stderr_tail": err_tail,
        }
    except subprocess.TimeoutExpired as e:
        dur = time.time() - t0
        out_tail = (e.stdout or "").splitlines()[-40:] if isinstance(e.stdout, str) else []
        err_tail = (e.stderr or "").splitlines()[-40:] if isinstance(e.stderr, str) else []
        return {
            "ok": False,
            "rc": 124,
            "duration_sec": round(float(dur), 3),
            "cmd": cmd,
            "stdout_tail": out_tail,
            "stderr_tail": err_tail + [f"TIMEOUT after {int(timeout_sec)}s"],
        }


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Offline analytics cycle: housekeeping + deterministic replay + learner_offline."
    )
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--housekeeping", choices=["off", "plan", "apply"], default="plan")
    ap.add_argument("--window-days", type=int, default=180)
    ap.add_argument("--row-limit", type=int, default=20000)
    ap.add_argument("--learner-ext-replay-weight", type=float, default=0.0)
    ap.add_argument("--timeout-sec", type=int, default=600)
    args = ap.parse_args()

    root = Path(args.root).resolve()
    evid_dir = root / "EVIDENCE" / "offline_cycle"
    evid_dir.mkdir(parents=True, exist_ok=True)
    run_id = now_utc().strftime("%Y%m%dT%H%M%SZ")
    report_path = evid_dir / f"{run_id}_offline_cycle_report.json"
    hk_evidence = evid_dir / f"{run_id}_housekeeping.json"

    env = dict(os.environ)
    env["OANDA_RUN_MODE"] = "OFFLINE"
    env["OFFLINE_DETERMINISTIC"] = "1"
    env["LEARNER_EXT_REPLAY_WEIGHT"] = str(float(max(0.0, min(1.0, args.learner_ext_replay_weight))))

    steps: List[Dict[str, Any]] = []

    if args.housekeeping != "off":
        hk_cmd = [
            sys.executable,
            "-B",
            "TOOLS/runtime_housekeeping.py",
            "--root",
            str(root),
            "--evidence",
            str(hk_evidence),
        ]
        if args.housekeeping == "apply":
            hk_cmd.append("--apply")
        steps.append(
            {
                "name": f"housekeeping_{args.housekeeping}",
                "result": run_cmd(hk_cmd, cwd=root, env=env, timeout_sec=args.timeout_sec),
            }
        )

    replay_cmd = [
        sys.executable,
        "-B",
        "TOOLS/offline_replay_analytics.py",
        "--root",
        str(root),
        "--window-days",
        str(max(1, int(args.window_days))),
        "--row-limit",
        str(max(1, int(args.row_limit))),
    ]
    steps.append({"name": "offline_replay_analytics", "result": run_cmd(replay_cmd, cwd=root, env=env, timeout_sec=args.timeout_sec)})

    learner_cmd = [sys.executable, "-B", "BIN/learner_offline.py", "once"]
    steps.append({"name": "learner_offline_once", "result": run_cmd(learner_cmd, cwd=root, env=env, timeout_sec=args.timeout_sec)})

    ok_all = all(bool((st.get("result") or {}).get("ok")) for st in steps)
    report = {
        "schema": "oanda_mt5.offline_cycle.v1",
        "ts_utc": now_utc_iso(),
        "run_id": run_id,
        "root": str(root),
        "housekeeping_mode": str(args.housekeeping),
        "window_days": int(max(1, int(args.window_days))),
        "row_limit": int(max(1, int(args.row_limit))),
        "learner_ext_replay_weight": float(env["LEARNER_EXT_REPLAY_WEIGHT"]),
        "steps": steps,
        "status": "PASS" if ok_all else "FAIL",
    }
    atomic_write_json(report_path, report)
    print(f"OFFLINE_CYCLE_{report['status']} report={report_path}")
    return 0 if ok_all else 1


if __name__ == "__main__":
    raise SystemExit(main())
