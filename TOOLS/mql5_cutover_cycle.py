from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional


SCHEMA = "oanda.mt5.cutover_cycle.v1"


def _utc_iso_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _read_json(path: Path) -> Dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _run_tool(args: List[str], root: Path) -> Dict[str, Any]:
    proc = subprocess.run(
        args,
        cwd=str(root),
        capture_output=True,
        text=True,
        check=False,
    )
    return {
        "cmd": args,
        "returncode": int(proc.returncode),
        "stdout": str(proc.stdout or "").strip(),
        "stderr": str(proc.stderr or "").strip(),
    }


def _latest_json(path: Path, fallback_glob: str) -> Optional[Path]:
    if path.exists():
        return path
    parent = path.parent
    if not parent.exists():
        return None
    files = sorted(parent.glob(fallback_glob))
    if not files:
        return None
    return files[-1]


def evaluate_cycle_status(
    *,
    probe_status: str,
    readiness_status: str,
    parity_rows: int,
) -> str:
    probe_u = str(probe_status or "").upper()
    ready_u = str(readiness_status or "").upper()
    if ready_u == "PASS":
        return "PASS"
    if probe_u == "NO_ACTIVE_PEER":
        return "REVIEW_REQUIRED"
    if parity_rows <= 0:
        return "REVIEW_REQUIRED"
    return "REVIEW_REQUIRED"


def should_ignore_probe_failure(probe_status: str, allow_no_peer: bool) -> bool:
    status_u = str(probe_status or "").upper()
    return bool(allow_no_peer and status_u == "NO_ACTIVE_PEER")


def main(argv: Optional[Iterable[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Run parity probe + report + cutover readiness in one cycle.")
    ap.add_argument("--root", default="C:/OANDA_MT5_SYSTEM")
    ap.add_argument("--hours", type=int, default=6)
    ap.add_argument("--timeout-ms", type=int, default=800)
    ap.add_argument("--allow-no-peer", action="store_true")
    ap.add_argument("--skip-probe", action="store_true")
    ap.add_argument("--min-parity-rows", type=int, default=200)
    ap.add_argument("--max-mismatch-ratio", type=float, default=0.02)
    ap.add_argument("--min-active-windows", type=int, default=1)
    ap.add_argument("--min-window-parity-rows", type=int, default=20)
    ap.add_argument("--max-window-mismatch-ratio", type=float, default=0.05)
    ap.add_argument("--out-json", default="")
    args = ap.parse_args(list(argv) if argv is not None else None)

    root = Path(args.root).resolve()
    py = sys.executable

    cycle: Dict[str, Any] = {
        "schema": SCHEMA,
        "generated_at_utc": _utc_iso_now(),
        "root": str(root),
        "steps": {},
    }

    probe_rc = 0
    if not bool(args.skip_probe):
        probe_cmd: List[str] = [
            py,
            str(root / "TOOLS" / "kernel_shadow_parity_probe.py"),
            "--root",
            str(root),
            "--timeout-ms",
            str(int(args.timeout_ms)),
        ]
        if bool(args.allow_no_peer):
            probe_cmd.append("--allow-no-peer")
        probe_step = _run_tool(probe_cmd, root)
        cycle["steps"]["probe"] = probe_step
        probe_rc = int(probe_step.get("returncode", 0))
    else:
        cycle["steps"]["probe"] = {"skipped": True}

    report_cmd = [
        py,
        str(root / "TOOLS" / "kernel_shadow_parity_report.py"),
        "--root",
        str(root),
        "--hours",
        str(int(args.hours)),
    ]
    report_step = _run_tool(report_cmd, root)
    cycle["steps"]["report"] = report_step

    readiness_cmd = [
        py,
        str(root / "TOOLS" / "mql5_cutover_readiness.py"),
        "--root",
        str(root),
        "--min-parity-rows",
        str(int(args.min_parity_rows)),
        "--max-mismatch-ratio",
        str(float(args.max_mismatch_ratio)),
        "--min-active-windows",
        str(int(args.min_active_windows)),
        "--min-window-parity-rows",
        str(int(args.min_window_parity_rows)),
        "--max-window-mismatch-ratio",
        str(float(args.max_window_mismatch_ratio)),
    ]
    readiness_step = _run_tool(readiness_cmd, root)
    cycle["steps"]["readiness"] = readiness_step

    probe_json = _latest_json(
        root / "EVIDENCE" / "kernel_shadow" / "kernel_shadow_parity_probe_latest.json",
        "kernel_shadow_parity_probe_*.json",
    )
    report_json = _latest_json(
        root / "EVIDENCE" / "kernel_shadow" / "kernel_shadow_parity_report_latest.json",
        "kernel_shadow_parity_report_*.json",
    )
    readiness_json = _latest_json(
        root / "EVIDENCE" / "cutover" / "mql5_cutover_readiness_latest.json",
        "mql5_cutover_readiness_*.json",
    )

    probe_obj = _read_json(probe_json) if probe_json else {}
    report_obj = _read_json(report_json) if report_json else {}
    readiness_obj = _read_json(readiness_json) if readiness_json else {}

    probe_status = str(((probe_obj.get("result") or {}).get("status")) or "")
    parity_rows = int(((report_obj.get("summary") or {}).get("parity_rows")) or 0)
    mismatch_ratio = (report_obj.get("summary") or {}).get("parity_mismatch_ratio")
    readiness_status = str(readiness_obj.get("status") or readiness_obj.get("readiness") or "")

    cycle["artifacts"] = {
        "probe_json": str(probe_json) if probe_json else "",
        "report_json": str(report_json) if report_json else "",
        "readiness_json": str(readiness_json) if readiness_json else "",
    }
    cycle["summary"] = {
        "probe_status": probe_status,
        "parity_rows": parity_rows,
        "parity_mismatch_ratio": mismatch_ratio,
        "readiness_status": readiness_status,
    }
    cycle["status"] = evaluate_cycle_status(
        probe_status=probe_status,
        readiness_status=readiness_status,
        parity_rows=parity_rows,
    )

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_json = (
        Path(args.out_json).resolve()
        if str(args.out_json or "").strip()
        else root / "EVIDENCE" / "cutover" / f"mql5_cutover_cycle_{stamp}.json"
    )
    _write_json(out_json, cycle)
    _write_json(out_json.parent / "mql5_cutover_cycle_latest.json", cycle)

    print(
        "MQL5_CUTOVER_CYCLE_DONE "
        f"status={cycle.get('status')} probe={probe_status or 'UNKNOWN'} "
        f"parity_rows={parity_rows} readiness={readiness_status or 'UNKNOWN'} out={out_json}"
    )

    if int(readiness_step.get("returncode", 0)) != 0:
        return 2
    if int(report_step.get("returncode", 0)) != 0:
        return 2
    if not bool(args.skip_probe):
        if str(probe_status or "").upper() == "NO_ZMQ":
            return 3
        if probe_rc != 0 and not should_ignore_probe_failure(probe_status, bool(args.allow_no_peer)):
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
