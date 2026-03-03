#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Optional


TS_RE = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})")


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def file_age_hours(path: Path) -> Optional[float]:
    try:
        mtime = datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
        return max(0.0, float((datetime.now(timezone.utc) - mtime).total_seconds() / 3600.0))
    except Exception:
        return None


def latest_file(path_glob_root: Path, pattern: str) -> Optional[Path]:
    files = [p for p in path_glob_root.glob(pattern) if p.is_file()]
    if not files:
        return None
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0]


def safe_read_json(path: Path) -> Dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="ignore") or "{}")
    except Exception:
        return {}


def parse_log_kpi(safety_log: Path, *, hours: int) -> Dict[str, Any]:
    # safetybot.log timestamps are local wall clock time without explicit timezone,
    # so compare using local naive datetimes to avoid UTC skew.
    start_local = datetime.now() - timedelta(hours=max(1, int(hours)))
    metrics = {
        "window_hours": int(max(1, int(hours))),
        "log_lines_in_window": 0,
        "heartbeat_failsafe_active_count": 0,
        "order_queue_timeout_count": 0,
        "order_queue_full_count": 0,
        "scan_slow_count": 0,
    }
    if not safety_log.exists():
        metrics["error"] = "missing_safety_log"
        return metrics

    try:
        lines = safety_log.read_text(encoding="utf-8", errors="ignore").splitlines()
    except Exception as exc:
        metrics["error"] = f"read_error:{type(exc).__name__}"
        return metrics

    for line in lines:
        m = TS_RE.match(line)
        if not m:
            continue
        try:
            ts_local = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
        except Exception:
            continue
        if ts_local < start_local:
            continue
        metrics["log_lines_in_window"] += 1
        if "HEARTBEAT_FAILSAFE_ACTIVE" in line:
            metrics["heartbeat_failsafe_active_count"] += 1
        if "ORDER_QUEUE_TIMEOUT" in line:
            metrics["order_queue_timeout_count"] += 1
        if "ORDER_QUEUE_FULL" in line:
            metrics["order_queue_full_count"] += 1
        if "SCAN_SLOW" in line:
            metrics["scan_slow_count"] += 1
    return metrics


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Collect runtime stability KPI snapshot.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--hours", type=int, default=24)
    ap.add_argument("--max-overlay-age-hours", type=float, default=24.0)
    ap.add_argument("--out", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    evidence = (root / "EVIDENCE").resolve()
    safety_log = (root / "LOGS" / "safetybot.log").resolve()
    strict_overlay_path = latest_file(evidence, "ranking_benchmark_strict_overlay_*.json")
    overlay_age_h = file_age_hours(strict_overlay_path) if strict_overlay_path else None
    max_overlay_age_h = max(1.0, float(args.max_overlay_age_hours))
    overlay_fresh = bool(strict_overlay_path) and (overlay_age_h is not None) and (overlay_age_h <= max_overlay_age_h)
    strict_overlay = safe_read_json(strict_overlay_path) if (strict_overlay_path and overlay_fresh) else {}
    strict_summary = dict(strict_overlay.get("summary") or {})
    strict_split = dict(strict_overlay.get("latency_split_diagnostics") or {})

    log_metrics = parse_log_kpi(safety_log, hours=max(1, int(args.hours)))

    latency_p50 = strict_summary.get("stress_latency_p50_sec", "UNKNOWN")
    latency_p95 = strict_summary.get("stress_latency_p95_sec", "UNKNOWN")
    timeout_count = strict_summary.get("stress_timeout_count", None)
    deadlock_count = strict_summary.get("stress_deadlock_suspect_count", None)

    if not isinstance(timeout_count, int):
        timeout_count = int(log_metrics.get("order_queue_timeout_count", 0))
    if not isinstance(deadlock_count, int):
        # Runtime proxy when stress-harness value is missing or stale.
        deadlock_count = int(log_metrics.get("heartbeat_failsafe_active_count", 0))

    report: Dict[str, Any] = {
        "schema": "oanda_mt5.runtime_kpi_snapshot.v1",
        "ts_utc": utc_now_iso(),
        "root": str(root),
        "inputs": {
            "strict_overlay_path": str(strict_overlay_path) if strict_overlay_path else "MISSING",
            "strict_overlay_age_hours": overlay_age_h if overlay_age_h is not None else "UNKNOWN",
            "strict_overlay_fresh_max_hours": max_overlay_age_h,
            "strict_overlay_used": bool(overlay_fresh),
            "safety_log_path": str(safety_log),
            "hours": int(max(1, int(args.hours))),
        },
        "kpi": {
            "latency_p50_sec": latency_p50,
            "latency_p95_sec": latency_p95,
            "timeout_count": timeout_count,
            "deadlock_or_crash_proxy_count": deadlock_count,
        },
        "latency_split_diagnostics": strict_split if strict_split else "UNKNOWN",
        "log_window_metrics": log_metrics,
        "notes": [],
        "status": "PASS",
    }
    if strict_overlay_path and not overlay_fresh:
        report["notes"].append(
            "strict overlay omitted from KPI due to stale age; runtime log window metrics used as primary proxy"
        )
    elif not strict_overlay_path:
        report["notes"].append("strict overlay missing; runtime log window metrics used as primary proxy")

    if isinstance(timeout_count, int) and timeout_count > 0:
        report["status"] = "WARN"
    if isinstance(deadlock_count, int) and deadlock_count > 0:
        report["status"] = "WARN"

    out_path: Path
    if str(args.out or "").strip():
        out_path = Path(str(args.out))
        if not out_path.is_absolute():
            out_path = (root / out_path).resolve()
    else:
        out_dir = (evidence / "runtime_kpi").resolve()
        out_dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        out_path = out_dir / f"runtime_kpi_snapshot_{stamp}.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        f"RUNTIME_KPI_SNAPSHOT_DONE status={report['status']} "
        f"timeout_count={report['kpi']['timeout_count']} "
        f"deadlock_or_crash_proxy_count={report['kpi']['deadlock_or_crash_proxy_count']} "
        f"out={out_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
