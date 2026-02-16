#!/usr/bin/env python
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


# Keep repo clean when this tool is run from project root.
sys.dont_write_bytecode = True


UTC = dt.timezone.utc
DEFAULT_MT5_PATH = r"C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe"
GATE_RUN_ID_RE = re.compile(r"^.+_(\d{8}_\d{6})\.txt$")


def _now_utc_iso() -> str:
    return dt.datetime.now(tz=UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _run_id() -> str:
    return dt.datetime.now(tz=UTC).strftime("%Y%m%dT%H%M%SZ")


def _read_json(path: Path) -> Optional[Dict[str, Any]]:
    try:
        if not path.exists():
            return None
        obj = json.loads(path.read_text(encoding="utf-8", errors="ignore") or "{}")
        return obj if isinstance(obj, dict) else None
    except Exception:
        return None


def _tail_text(s: str, max_lines: int = 40, max_chars: int = 6000) -> str:
    txt = str(s or "")
    lines = txt.splitlines()[-max_lines:]
    out = "\n".join(lines)
    return out[-max_chars:]


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
        out = cp.stdout or ""
        err = cp.stderr or ""
    except subprocess.TimeoutExpired as e:
        rc = 124
        out = str(getattr(e, "stdout", "") or "")
        err = str(getattr(e, "stderr", "") or "")
    except Exception as e:
        rc = 125
        out = ""
        err = f"{type(e).__name__}: {e}"
    dt_sec = time.perf_counter() - t0
    return {
        "cmd": list(cmd),
        "rc": int(rc),
        "duration_sec": round(float(dt_sec), 3),
        "stdout_tail": _tail_text(out),
        "stderr_tail": _tail_text(err),
    }


def _list_gate_run_ids(gates_dir: Path) -> set[str]:
    ids: set[str] = set()
    if not gates_dir.exists():
        return ids
    for p in gates_dir.glob("*.txt"):
        m = GATE_RUN_ID_RE.match(p.name)
        if not m:
            continue
        ids.add(str(m.group(1)))
    return ids


def _pick_gate_run_id(before: set[str], after: set[str]) -> Optional[str]:
    new_ids = sorted(list(after - before))
    if new_ids:
        return new_ids[-1]
    if after:
        return sorted(list(after))[-1]
    return None


def _parse_gate_result_file(path: Path) -> Tuple[str, List[str]]:
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    result = "UNKNOWN"
    issues: List[str] = []
    for ln in lines:
        s = str(ln).strip()
        if s.upper().startswith("RESULT:"):
            result = s.split(":", 1)[1].strip()
            continue
        if not s:
            continue
        if s.upper().startswith("GATE:") or s.upper().startswith("MODE:") or s.upper().startswith("NOTE:"):
            continue
        issues.append(s)
    return result, issues


def collect_gate_summary(root: Path, run_id: Optional[str]) -> Dict[str, Any]:
    gates_dir = root / "EVIDENCE" / "gates"
    out: Dict[str, Any] = {
        "run_id": run_id,
        "gates": {},
        "failed_gates": [],
    }
    if not run_id or not gates_dir.exists():
        return out
    failed: List[str] = []
    gates: Dict[str, Any] = {}
    for p in sorted(gates_dir.glob(f"*_{run_id}.txt")):
        gate_name = p.name[: -(len(run_id) + 5)]  # strip "_<run_id>.txt"
        result, issues = _parse_gate_result_file(p)
        gates[gate_name] = {
            "result": result,
            "issues": issues[:10],
            "evidence": str(p),
        }
        if str(result).upper().startswith("FAIL"):
            failed.append(gate_name)
    out["gates"] = gates
    out["failed_gates"] = sorted(failed)
    return out


def find_latest_report(root: Path, pattern: str, *, started_at: float) -> Optional[Path]:
    cands: List[Path] = []
    for p in (root / "EVIDENCE").glob(pattern):
        try:
            if p.is_file() and p.stat().st_mtime >= (started_at - 2.0):
                cands.append(p)
        except Exception:
            continue
    if not cands:
        return None
    cands.sort(key=lambda x: (x.stat().st_mtime, x.name))
    return cands[-1]


def evaluate_overall_status(
    *,
    learner_rc: int,
    smoke_compile_rc: int,
    gate_rc: int,
    prelive_go: bool,
    gate_failed: List[str],
    prelive_failed_checks: List[str],
    online_result: str,
    symbols_result: str,
) -> Dict[str, Any]:
    blockers: List[str] = []
    if int(learner_rc) != 0:
        blockers.append("learner_offline_failed")
    if int(smoke_compile_rc) != 0:
        blockers.append("smoke_compile_failed")
    if int(gate_rc) != 0:
        if gate_failed:
            blockers.extend([f"gate:{x}" for x in sorted(set(gate_failed))])
        else:
            blockers.append("gate_v6_failed")
    if not bool(prelive_go):
        if prelive_failed_checks:
            blockers.extend([f"prelive:{x}" for x in sorted(set(prelive_failed_checks))])
        else:
            blockers.append("prelive_no_go")

    online = str(online_result or "UNKNOWN").upper()
    symbols = str(symbols_result or "UNKNOWN").upper()

    if online == "PASS" and symbols == "PASS":
        online_state = "ONLINE_VERIFIED"
    elif ("DO_WERYFIKACJI_ONLINE" in online) or ("DO_WERYFIKACJI_ONLINE" in symbols):
        online_state = "ONLINE_PENDING"
    elif symbols == "WARN_MISSING_TARGETS":
        online_state = "ONLINE_SYMBOLS_MISSING"
        blockers.append("online:symbols_missing_targets")
    else:
        online_state = "ONLINE_FAILED"
        blockers.append("online:smoke_or_symbols_failed")

    offline_ready = len(blockers) == 0 or all(
        b.startswith("online:") for b in blockers
    )
    if len([b for b in blockers if not b.startswith("online:")]) > 0:
        status = "NO_GO"
    else:
        if online_state == "ONLINE_VERIFIED":
            status = "GO"
        elif online_state == "ONLINE_PENDING":
            status = "GO_OFFLINE_PENDING_ONLINE"
        else:
            status = "NO_GO"

    return {
        "status": status,
        "offline_ready": bool(offline_ready and not any(not b.startswith("online:") for b in blockers)),
        "go_live_ready": bool(status == "GO"),
        "online_state": online_state,
        "blockers": sorted(set(blockers)),
    }


def run_one_click(
    *,
    root: Path,
    python_exe: str,
    mt5_path: str,
    offline_sim: bool,
    skip_learner: bool,
    skip_smoke_compile: bool,
    timeout_sec: int,
    out_path: Optional[Path],
) -> Tuple[Dict[str, Any], Path]:
    root = Path(root).resolve()
    run_id = _run_id()
    started_at = time.time()

    report: Dict[str, Any] = {
        "schema": "oanda_mt5.prelive_one_click.v1",
        "ts_utc": _now_utc_iso(),
        "run_id": run_id,
        "root": str(root),
        "settings": {
            "python_exe": str(python_exe),
            "mt5_path": str(mt5_path),
            "offline_sim": bool(offline_sim),
            "skip_learner": bool(skip_learner),
            "skip_smoke_compile": bool(skip_smoke_compile),
            "timeout_sec": int(timeout_sec),
        },
        "steps": {},
    }

    # 0) DIAG bundle first (helps gate_v6 diag_latest).
    cmd_diag = [str(python_exe), "-B", "TOOLS/diag_bundle_v6.py"]
    report["steps"]["diag_bundle"] = run_cmd(cmd_diag, cwd=root, timeout_sec=timeout_sec)

    # 1) Learner refresh.
    if not skip_learner:
        cmd_learner = [str(python_exe), "-B", "BIN/learner_offline.py", "once"]
        learner_step = run_cmd(cmd_learner, cwd=root, timeout_sec=timeout_sec)
    else:
        learner_step = {
            "cmd": [],
            "rc": 0,
            "duration_sec": 0.0,
            "stdout_tail": "SKIPPED",
            "stderr_tail": "",
        }
    report["steps"]["learner_once"] = learner_step

    # 2) Compile smoke.
    smoke_out = root / "EVIDENCE" / f"smoke_compile_{run_id}.json"
    if not skip_smoke_compile:
        cmd_smoke = [
            str(python_exe),
            "-B",
            "TOOLS/smoke_compile_v6_2.py",
            "--root",
            str(root),
            "--out",
            str(smoke_out),
        ]
        smoke_step = run_cmd(cmd_smoke, cwd=root, timeout_sec=timeout_sec)
    else:
        smoke_step = {
            "cmd": [],
            "rc": 0,
            "duration_sec": 0.0,
            "stdout_tail": "SKIPPED",
            "stderr_tail": "",
        }
    report["steps"]["smoke_compile"] = smoke_step
    report["steps"]["smoke_compile"]["report"] = str(smoke_out)

    # 3) gate_v6 offline.
    gates_dir = root / "EVIDENCE" / "gates"
    gate_ids_before = _list_gate_run_ids(gates_dir)
    cmd_gate = [str(python_exe), "-B", "TOOLS/gate_v6.py", "--mode", "offline"]
    gate_step = run_cmd(cmd_gate, cwd=root, timeout_sec=timeout_sec)
    gate_ids_after = _list_gate_run_ids(gates_dir)
    gate_run_id = _pick_gate_run_id(gate_ids_before, gate_ids_after)
    gate_summary = collect_gate_summary(root, gate_run_id)
    gate_step["gate_run_id"] = gate_run_id
    gate_step["failed_gates"] = list(gate_summary.get("failed_gates") or [])
    report["steps"]["gate_v6_offline"] = gate_step
    report["artifacts"] = {"gate_summary": gate_summary}

    # 4) prelive go/no-go.
    cmd_prelive = [str(python_exe), "-B", "TOOLS/prelive_go_nogo.py", "--root", str(root)]
    prelive_step = run_cmd(cmd_prelive, cwd=root, timeout_sec=timeout_sec)
    prelive_path = find_latest_report(root, "prelive_go_nogo_*.json", started_at=started_at)
    prelive_obj = _read_json(prelive_path) if prelive_path else None
    prelive_step["report"] = str(prelive_path) if prelive_path else None
    report["steps"]["prelive_go_nogo"] = prelive_step
    report["artifacts"]["prelive_report"] = prelive_obj

    # 5) ONLINE checks (offline-sim friendly).
    smoke_online_out = root / "EVIDENCE" / "online_smoke" / f"{run_id}_mt5_smoke.json"
    cmd_online = [
        str(python_exe),
        "-B",
        "TOOLS/online_smoke_mt5.py",
        "--mt5-path",
        str(mt5_path),
        "--out",
        str(smoke_online_out),
    ]
    if offline_sim:
        cmd_online.append("--offline-sim")
    online_step = run_cmd(cmd_online, cwd=root, timeout_sec=timeout_sec)
    online_obj = _read_json(smoke_online_out) or {}
    online_step["report"] = str(smoke_online_out)
    report["steps"]["online_smoke_mt5"] = online_step
    report["artifacts"]["online_smoke_report"] = online_obj

    symbols_out = root / "EVIDENCE" / "symbols_get_audit" / f"{run_id}_symbols_get_audit.json"
    cmd_symbols = [
        str(python_exe),
        "-B",
        "TOOLS/audit_symbols_get_mt5.py",
        "--mt5-path",
        str(mt5_path),
        "--strict",
        "--out",
        str(symbols_out),
    ]
    if offline_sim:
        cmd_symbols.append("--offline-sim")
    symbols_step = run_cmd(cmd_symbols, cwd=root, timeout_sec=timeout_sec)
    symbols_obj = _read_json(symbols_out) or {}
    symbols_step["report"] = str(symbols_out)
    report["steps"]["audit_symbols_get_mt5"] = symbols_step
    report["artifacts"]["symbols_audit_report"] = symbols_obj

    prelive_checks = []
    if isinstance(prelive_obj, dict):
        for c in (prelive_obj.get("checks") or []):
            try:
                if not bool(c.get("ok")):
                    prelive_checks.append(str(c.get("id") or "").strip())
            except Exception:
                continue

    verdict = evaluate_overall_status(
        learner_rc=int(learner_step.get("rc") or 0),
        smoke_compile_rc=int(smoke_step.get("rc") or 0),
        gate_rc=int(gate_step.get("rc") or 0),
        prelive_go=bool((prelive_obj or {}).get("go")),
        gate_failed=list(gate_summary.get("failed_gates") or []),
        prelive_failed_checks=prelive_checks,
        online_result=str((online_obj or {}).get("result") or "UNKNOWN"),
        symbols_result=str((symbols_obj or {}).get("result") or "UNKNOWN"),
    )
    report["verdict"] = verdict
    report["duration_sec"] = round(time.time() - started_at, 3)

    out = out_path or (root / "EVIDENCE" / f"prelive_one_click_{run_id}.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report, out


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description="One-click prelive flow: diag + learner + smoke + gate + prelive + online evidence."
    )
    ap.add_argument("--root", default=".", help="Runtime root path")
    ap.add_argument("--python", default=sys.executable, help="Python executable path")
    ap.add_argument("--mt5-path", default=DEFAULT_MT5_PATH, help="Path to OANDA TMS MT5 terminal64.exe")
    ap.add_argument("--offline-sim", dest="offline_sim", action="store_true", default=True)
    ap.add_argument("--no-offline-sim", dest="offline_sim", action="store_false")
    ap.add_argument("--skip-learner", action="store_true", help="Skip learner_offline once step")
    ap.add_argument("--skip-smoke-compile", action="store_true", help="Skip smoke_compile_v6_2 step")
    ap.add_argument("--timeout-sec", type=int, default=900, help="Per-step timeout in seconds")
    ap.add_argument("--out", default="", help="Optional explicit output report path")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    rep, out = run_one_click(
        root=Path(args.root),
        python_exe=str(args.python),
        mt5_path=str(args.mt5_path),
        offline_sim=bool(args.offline_sim),
        skip_learner=bool(args.skip_learner),
        skip_smoke_compile=bool(args.skip_smoke_compile),
        timeout_sec=int(args.timeout_sec),
        out_path=Path(args.out) if str(args.out or "").strip() else None,
    )
    verdict = dict(rep.get("verdict") or {})
    status = str(verdict.get("status") or "NO_GO")
    blockers = list(verdict.get("blockers") or [])
    print(f"PRELIVE_ONE_CLICK | status={status} | blockers={len(blockers)} | report={out}")
    return 0 if status in {"GO", "GO_OFFLINE_PENDING_ONLINE"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
