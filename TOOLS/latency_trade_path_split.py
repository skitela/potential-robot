from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple


SCHEMA = "oanda_mt5.latency_trade_path_split.v1"


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _parse_iso(value: str) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).astimezone(timezone.utc)
    except Exception:
        return None


def _stats(values: List[float]) -> Dict[str, Any]:
    if not values:
        return {"n": 0, "p50_ms": "UNKNOWN", "p95_ms": "UNKNOWN", "p99_ms": "UNKNOWN", "max_ms": "UNKNOWN"}
    vals = sorted(values)
    n = len(vals)

    def q(p: float) -> float:
        idx = min(n - 1, int((n - 1) * p))
        return float(vals[idx])

    return {
        "n": n,
        "p50_ms": round(q(0.50), 3),
        "p95_ms": round(q(0.95), 3),
        "p99_ms": round(q(0.99), 3),
        "max_ms": round(float(vals[-1]), 3),
    }


def _latest_file(dir_path: Path, pattern: str) -> Optional[Path]:
    items = sorted(dir_path.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
    return items[0] if items else None


def _read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _load_window_from_soak(soak_json: Dict[str, Any]) -> Optional[Tuple[datetime, datetime]]:
    try:
        w = (((soak_json.get("after_soak_window") or {}).get("audit_window") or {}).get("audit_trail_utc") or {})
        s = _parse_iso(str(w.get("start") or ""))
        e = _parse_iso(str(w.get("end") or ""))
        if s and e and e >= s:
            return (s, e)
    except Exception:
        return None
    return None


def _iter_jsonl(path: Path) -> Iterable[Dict[str, Any]]:
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if isinstance(obj, dict):
                yield obj


@dataclass
class SplitMetrics:
    send_ms: List[float]
    wait_ms: List[float]
    parse_ms: List[float]
    elapsed_ms: List[float]
    queue_wait_ms: List[float]
    agent_process_ms: List[float]
    order_send_ms: List[float]
    bridge_overhead_ms: List[float]


def _new_metrics() -> SplitMetrics:
    return SplitMetrics(
        send_ms=[],
        wait_ms=[],
        parse_ms=[],
        elapsed_ms=[],
        queue_wait_ms=[],
        agent_process_ms=[],
        order_send_ms=[],
        bridge_overhead_ms=[],
    )


def _to_float(value: Any) -> Optional[float]:
    try:
        if value is None:
            return None
        return float(value)
    except Exception:
        return None


def _append_if(arr: List[float], value: Any) -> None:
    fv = _to_float(value)
    if fv is None:
        return
    arr.append(float(fv))


def build_report(
    root: Path,
    audit_path: Path,
    window_start: datetime,
    window_end: datetime,
    soak_path: Optional[Path],
) -> Dict[str, Any]:
    all_trade_reply = _new_metrics()
    trade_retcodes: Dict[str, int] = {}
    trade_timeout_reasons: Dict[str, int] = {}
    sent_trade = 0
    timeout_trade = 0
    trade_reply_count = 0

    for obj in _iter_jsonl(audit_path):
        ts = _parse_iso(str(obj.get("timestamp_utc") or ""))
        if ts is None or ts < window_start or ts > window_end:
            continue

        event_type = str(obj.get("event_type") or "").upper()
        data = obj.get("data") if isinstance(obj.get("data"), dict) else {}
        cmd_type = str(data.get("command_type") or "").upper()
        if cmd_type != "TRADE":
            continue

        if event_type == "COMMAND_SENT":
            sent_trade += 1
            continue

        if event_type == "COMMAND_TIMEOUT":
            timeout_trade += 1
            reason = f"{data.get('bridge_timeout_reason') or 'UNKNOWN'}:{data.get('bridge_timeout_subreason') or 'UNKNOWN'}"
            trade_timeout_reasons[reason] = int(trade_timeout_reasons.get(reason, 0) + 1)
            continue

        if event_type != "REPLY_RECEIVED":
            continue

        trade_reply_count += 1
        _append_if(all_trade_reply.send_ms, data.get("send_ms"))
        _append_if(all_trade_reply.wait_ms, data.get("wait_ms"))
        _append_if(all_trade_reply.parse_ms, data.get("parse_ms"))
        _append_if(all_trade_reply.elapsed_ms, data.get("elapsed_ms"))
        _append_if(all_trade_reply.queue_wait_ms, data.get("command_queue_wait_ms"))

        details = data.get("details") if isinstance(data.get("details"), dict) else {}
        _append_if(all_trade_reply.agent_process_ms, details.get("agent_process_ms"))
        _append_if(all_trade_reply.order_send_ms, details.get("order_send_ms"))

        elapsed = _to_float(data.get("elapsed_ms"))
        agent_ms = _to_float(details.get("agent_process_ms"))
        if elapsed is not None and agent_ms is not None and agent_ms >= 0:
            all_trade_reply.bridge_overhead_ms.append(float(max(0.0, elapsed - agent_ms)))

        retcode_str = str(details.get("retcode_str") or "UNKNOWN")
        trade_retcodes[retcode_str] = int(trade_retcodes.get(retcode_str, 0) + 1)

    split = {
        "python_bridge_send": _stats(all_trade_reply.send_ms),
        "python_bridge_wait": _stats(all_trade_reply.wait_ms),
        "python_bridge_parse": _stats(all_trade_reply.parse_ms),
        "python_elapsed_total": _stats(all_trade_reply.elapsed_ms),
        "python_command_queue_wait": _stats(all_trade_reply.queue_wait_ms),
        "mql_agent_process": _stats(all_trade_reply.agent_process_ms),
        "mql_order_send": _stats(all_trade_reply.order_send_ms),
        "bridge_overhead_derived": _stats(all_trade_reply.bridge_overhead_ms),
    }

    unknown_agent_split = split["mql_agent_process"]["n"] == 0
    verdict_status = "PASS"
    review_required: List[str] = []
    notes: List[str] = []

    if trade_reply_count < 10:
        verdict_status = "REVIEW_REQUIRED"
        review_required.append(f"TRADE_REPLY_SAMPLES_LOW:{trade_reply_count}")
    if timeout_trade > 0 and sent_trade > 0 and (timeout_trade / float(sent_trade)) > 0.05:
        verdict_status = "REVIEW_REQUIRED"
        review_required.append(f"TRADE_TIMEOUT_RATE_HIGH:{round(timeout_trade/float(sent_trade), 6)}")
    wait_p95 = split["python_bridge_wait"].get("p95_ms")
    if isinstance(wait_p95, (int, float)) and float(wait_p95) > 700.0:
        verdict_status = "REVIEW_REQUIRED"
        review_required.append(f"TRADE_WAIT_P95_HIGH:{wait_p95}")
    if unknown_agent_split:
        verdict_status = "REVIEW_REQUIRED"
        review_required.append("MQL_AGENT_SPLIT_UNKNOWN:no agent_process_ms in replies")
        notes.append("Agent-side split fields not present in reply.details (compile/deploy HybridAgent update required).")

    if not review_required:
        notes.append("Trade-path split metrics are complete for this window.")

    report = {
        "schema": SCHEMA,
        "ts_utc": _iso(_utc_now()),
        "workspace_root_path": str(root),
        "inputs": {
            "audit_trail_jsonl": str(audit_path),
            "bridge_soak_compare_json": str(soak_path) if soak_path else "NONE",
        },
        "window_utc": {
            "start": _iso(window_start),
            "end": _iso(window_end),
        },
        "trade_counts": {
            "command_sent": sent_trade,
            "command_timeout": timeout_trade,
            "reply_received": trade_reply_count,
            "timeout_rate": round((timeout_trade / float(sent_trade)), 6) if sent_trade > 0 else "UNKNOWN",
        },
        "retcode_breakdown": dict(sorted(trade_retcodes.items(), key=lambda kv: kv[1], reverse=True)),
        "timeout_reason_breakdown": dict(sorted(trade_timeout_reasons.items(), key=lambda kv: kv[1], reverse=True)),
        "latency_split_ms": split,
        "verdict": {
            "status": verdict_status,
            "review_required": review_required,
            "notes": notes,
        },
    }
    return report


def _build_txt(report: Dict[str, Any]) -> str:
    lines: List[str] = []
    lines.append("LATENCY_TRADE_PATH_SPLIT")
    lines.append(f"TS_UTC: {report.get('ts_utc')}")
    lines.append(f"WORKSPACE_ROOT_PATH: {report.get('workspace_root_path')}")
    w = report.get("window_utc") or {}
    lines.append(f"WINDOW_UTC: {w.get('start')} -> {w.get('end')}")
    lines.append("")
    lines.append("COUNTS")
    c = report.get("trade_counts") or {}
    lines.append(f"- command_sent: {c.get('command_sent')}")
    lines.append(f"- command_timeout: {c.get('command_timeout')}")
    lines.append(f"- reply_received: {c.get('reply_received')}")
    lines.append(f"- timeout_rate: {c.get('timeout_rate')}")
    lines.append("")
    lines.append("LATENCY_SPLIT_MS")
    s = report.get("latency_split_ms") or {}
    for k in (
        "python_bridge_send",
        "python_bridge_wait",
        "python_bridge_parse",
        "python_elapsed_total",
        "python_command_queue_wait",
        "mql_agent_process",
        "mql_order_send",
        "bridge_overhead_derived",
    ):
        lines.append(f"- {k}: {s.get(k)}")
    lines.append("")
    lines.append("RETCODE_BREAKDOWN")
    rb = report.get("retcode_breakdown") or {}
    if rb:
        for k, v in rb.items():
            lines.append(f"- {k}: {v}")
    else:
        lines.append("- NONE")
    lines.append("")
    lines.append("TIMEOUT_REASON_BREAKDOWN")
    tb = report.get("timeout_reason_breakdown") or {}
    if tb:
        for k, v in tb.items():
            lines.append(f"- {k}: {v}")
    else:
        lines.append("- NONE")
    lines.append("")
    lines.append("VERDICT")
    v = report.get("verdict") or {}
    lines.append(str(v))
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Trade-path latency split (bridge vs MQL agent) from audit logs.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--audit", default=None, help="Path to LOGS/audit_trail.jsonl")
    ap.add_argument("--soak-json", default=None, help="Path to bridge_soak_compare_*.json (default: latest)")
    ap.add_argument("--fallback-lookback-min", type=int, default=30, help="Used when soak window is unavailable.")
    ap.add_argument("--out-json", default=None)
    ap.add_argument("--out-txt", default=None)
    args = ap.parse_args()

    root = Path(args.root).resolve()
    audit_path = Path(args.audit).resolve() if args.audit else (root / "LOGS" / "audit_trail.jsonl").resolve()
    if not audit_path.exists():
        raise FileNotFoundError(f"Missing audit log: {audit_path}")

    soak_path: Optional[Path] = Path(args.soak_json).resolve() if args.soak_json else None
    if soak_path is None:
        soak_dir = (root / "EVIDENCE" / "bridge_audit").resolve()
        soak_path = _latest_file(soak_dir, "bridge_soak_compare_*.json")

    window: Optional[Tuple[datetime, datetime]] = None
    soak_json: Optional[Dict[str, Any]] = None
    if soak_path and soak_path.exists():
        soak_json = _read_json(soak_path)
        window = _load_window_from_soak(soak_json)

    if window is None:
        end = _utc_now()
        start = end - timedelta(minutes=max(1, int(args.fallback_lookback_min)))
        window = (start, end)

    out_dir = (root / "EVIDENCE" / "latency_trade_split").resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    run_id = _utc_now().strftime("%Y%m%dT%H%M%SZ")
    out_json = Path(args.out_json).resolve() if args.out_json else (out_dir / f"latency_trade_path_split_{run_id}.json")
    out_txt = Path(args.out_txt).resolve() if args.out_txt else (out_dir / f"latency_trade_path_split_{run_id}.txt")

    report = build_report(
        root=root,
        audit_path=audit_path,
        window_start=window[0],
        window_end=window[1],
        soak_path=soak_path if soak_path and soak_path.exists() else None,
    )

    out_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    out_txt.write_text(_build_txt(report), encoding="utf-8")
    print(f"LATENCY_TRADE_PATH_SPLIT_OK json={out_json} txt={out_txt}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

