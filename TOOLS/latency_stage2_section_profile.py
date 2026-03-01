#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple


RUNTIME_METRICS_RE = re.compile(
    r"RUNTIME_METRICS_10M .*?"
    r"scan_p50_ms=(?P<scan_p50>\d+)\s+"
    r"scan_p95_ms=(?P<scan_p95>\d+)\s+"
    r"scan_max_ms=(?P<scan_max>\d+).*?"
    r"q_backpressure_drops=(?P<q_backpressure>\d+)\s+"
    r"q_timeouts=(?P<q_timeouts>\d+)\s+"
    r"q_full=(?P<q_full>\d+)"
)

ZMQ_RTT_RE = re.compile(r"ZMQ_RTT .*?rtt_ms=(?P<rtt>\d+)\s+action=(?P<action>[A-Z_0-9]+)")
ORDER_LAT_RE = re.compile(r"(?:ORDER_SEND|ORDER_CHECK).*?latency_ms=(?P<lat>\d+)")
LOG_TS_RE = re.compile(r"^(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3})")


def _parse_kv_tokens(line: str) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for token in str(line or "").split():
        if "=" not in token:
            continue
        k, v = token.split("=", 1)
        k = str(k or "").strip()
        v = str(v or "").strip().strip(",")
        if k:
            out[k] = v
    return out


def _utc_now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def _percentile(values: List[float], q: float) -> float:
    if not values:
        return 0.0
    if q <= 0:
        return float(min(values))
    if q >= 1:
        return float(max(values))
    arr = sorted(float(v) for v in values)
    idx = q * (len(arr) - 1)
    lo = int(idx)
    hi = min(lo + 1, len(arr) - 1)
    frac = idx - lo
    return float(arr[lo] * (1.0 - frac) + arr[hi] * frac)


def _stats(values: List[float]) -> Dict[str, Any]:
    if not values:
        return {"n": 0, "p50_ms": "UNKNOWN", "p95_ms": "UNKNOWN", "p99_ms": "UNKNOWN", "max_ms": "UNKNOWN"}
    return {
        "n": len(values),
        "p50_ms": round(_percentile(values, 0.50), 3),
        "p95_ms": round(_percentile(values, 0.95), 3),
        "p99_ms": round(_percentile(values, 0.99), 3),
        "max_ms": round(max(values), 3),
    }


def _last_n(items: List[Any], limit: int) -> List[Any]:
    if limit <= 0:
        return items
    if len(items) <= limit:
        return items
    return items[-limit:]


def _read_latest_stage1(root: Path) -> Tuple[str, Dict[str, Any]]:
    base = root / "EVIDENCE" / "latency_stage1"
    if not base.exists():
        return ("UNKNOWN", {})
    files = sorted(base.glob("latency_stage1_baseline_*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not files:
        return ("UNKNOWN", {})
    latest = files[0]
    try:
        data = json.loads(latest.read_text(encoding="utf-8-sig"))
    except Exception:
        data = {}
    return (str(latest), data)


def _scan_safetybot_log(path: Path) -> Dict[str, Any]:
    out: Dict[str, Any] = {
        "scan_p50_samples": [],
        "scan_p95_samples": [],
        "scan_max_samples": [],
        "q_backpressure_samples": [],
        "q_timeout_samples": [],
        "q_full_samples": [],
        "bridge_rtt_samples": [],
        "bridge_rtt_action_counts": {},
        "section_metrics_samples": {
            "tick_ingest": [],
            "bridge_send": [],
            "bridge_wait": [],
            "bridge_parse": [],
            "session_gate": [],
            "cost_gate": [],
            "decision_core": [],
            "execution_call": [],
            "io_log": [],
        },
        "execution_latency_samples": [],
        "matched_lines_runtime_metrics": 0,
        "matched_lines_section_metrics": 0,
        "matched_lines_zmq_rtt": 0,
        "matched_lines_execution": 0,
        "first_ts_local": "UNKNOWN",
        "last_ts_local": "UNKNOWN",
    }
    if not path.exists():
        out["status"] = "MISSING_LOG"
        return out

    first_ts: str | None = None
    last_ts: str | None = None
    rtt_action_counts: Dict[str, int] = {}
    with path.open("r", encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            line = line.rstrip("\n")
            ts_m = LOG_TS_RE.search(line)
            if ts_m:
                ts_raw = ts_m.group("ts")
                if first_ts is None:
                    first_ts = ts_raw
                last_ts = ts_raw
            m = RUNTIME_METRICS_RE.search(line)
            if m:
                out["matched_lines_runtime_metrics"] += 1
                out["scan_p50_samples"].append(float(m.group("scan_p50")))
                out["scan_p95_samples"].append(float(m.group("scan_p95")))
                out["scan_max_samples"].append(float(m.group("scan_max")))
                out["q_backpressure_samples"].append(float(m.group("q_backpressure")))
                out["q_timeout_samples"].append(float(m.group("q_timeouts")))
                out["q_full_samples"].append(float(m.group("q_full")))
            if "RUNTIME_SECTION_METRICS_10M" in line:
                kv = _parse_kv_tokens(line)
                section_map = out["section_metrics_samples"]
                if isinstance(section_map, dict):
                    for section in (
                        "tick_ingest",
                        "bridge_send",
                        "bridge_wait",
                        "bridge_parse",
                        "session_gate",
                        "cost_gate",
                        "decision_core",
                        "execution_call",
                        "io_log",
                    ):
                        p50 = kv.get(f"{section}_p50_ms")
                        p95 = kv.get(f"{section}_p95_ms")
                        p99 = kv.get(f"{section}_p99_ms")
                        if p50 is None and p95 is None and p99 is None:
                            continue
                        try:
                            p50_v = float(p50) if p50 is not None else None
                        except Exception:
                            p50_v = None
                        try:
                            p95_v = float(p95) if p95 is not None else None
                        except Exception:
                            p95_v = None
                        try:
                            p99_v = float(p99) if p99 is not None else None
                        except Exception:
                            p99_v = None
                        section_map.setdefault(section, []).append(
                            {"p50_ms": p50_v, "p95_ms": p95_v, "p99_ms": p99_v}
                        )
                        out["matched_lines_section_metrics"] += 1
            m = ZMQ_RTT_RE.search(line)
            if m:
                out["matched_lines_zmq_rtt"] += 1
                out["bridge_rtt_samples"].append(float(m.group("rtt")))
                action = str(m.group("action") or "UNKNOWN").upper()
                rtt_action_counts[action] = int(rtt_action_counts.get(action, 0)) + 1
            m = ORDER_LAT_RE.search(line)
            if m:
                out["matched_lines_execution"] += 1
                out["execution_latency_samples"].append(float(m.group("lat")))
    out["first_ts_local"] = first_ts or "UNKNOWN"
    out["last_ts_local"] = last_ts or "UNKNOWN"
    out["bridge_rtt_action_counts"] = rtt_action_counts
    out["status"] = "OK"
    return out


def _iter_jsonl(path: Path) -> Iterable[Dict[str, Any]]:
    with path.open("r", encoding="utf-8", errors="ignore") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            try:
                obj = json.loads(raw)
            except Exception:
                continue
            if isinstance(obj, dict):
                yield obj


def _scan_audit_trail(path: Path) -> Dict[str, Any]:
    out: Dict[str, Any] = {
        "reply_elapsed_samples_ms": [],
        "reply_wait_samples_ms": [],
        "reply_send_samples_ms": [],
        "reply_parse_samples_ms": [],
        "reply_elapsed_by_action_ms": {},
        "command_sent_count": 0,
        "command_timeout_count": 0,
        "reply_received_count": 0,
        "first_ts_utc": "UNKNOWN",
        "last_ts_utc": "UNKNOWN",
    }
    if not path.exists():
        out["status"] = "MISSING_LOG"
        return out

    first_ts: str | None = None
    last_ts: str | None = None
    by_action: Dict[str, List[float]] = {}

    for obj in _iter_jsonl(path):
        ts = str(obj.get("timestamp_utc") or "UNKNOWN")
        if ts != "UNKNOWN":
            if first_ts is None:
                first_ts = ts
            last_ts = ts
        event_type = str(obj.get("event_type") or obj.get("event_type_norm") or "").upper()
        data = obj.get("data")
        if not isinstance(data, dict):
            data = {}
        if event_type == "COMMAND_SENT":
            out["command_sent_count"] += 1
        elif event_type == "COMMAND_TIMEOUT":
            out["command_timeout_count"] += 1
        elif event_type == "REPLY_RECEIVED":
            out["reply_received_count"] += 1
            elapsed = data.get("elapsed_ms")
            wait_ms = data.get("wait_ms")
            send_ms = data.get("send_ms")
            parse_ms = data.get("parse_ms")
            try:
                elapsed_f = float(elapsed)
            except Exception:
                elapsed_f = None
            try:
                wait_f = float(wait_ms)
            except Exception:
                wait_f = None
            try:
                send_f = float(send_ms)
            except Exception:
                send_f = None
            try:
                parse_f = float(parse_ms)
            except Exception:
                parse_f = None
            if elapsed_f is not None:
                out["reply_elapsed_samples_ms"].append(elapsed_f)
                action = str(data.get("action") or "UNKNOWN").upper()
                by_action.setdefault(action, []).append(elapsed_f)
            if wait_f is not None:
                out["reply_wait_samples_ms"].append(wait_f)
            if send_f is not None:
                out["reply_send_samples_ms"].append(send_f)
            if parse_f is not None:
                out["reply_parse_samples_ms"].append(parse_f)

    out["reply_elapsed_by_action_ms"] = by_action
    out["first_ts_utc"] = first_ts or "UNKNOWN"
    out["last_ts_utc"] = last_ts or "UNKNOWN"
    out["status"] = "OK"
    return out


def _build_sections(log_scan: Dict[str, Any], audit_scan: Dict[str, Any], per_section_limit: int) -> Dict[str, Any]:
    # full_loop proxy from periodic runtime metrics snapshots.
    scan_p50 = _last_n(log_scan.get("scan_p50_samples", []), per_section_limit)
    scan_p95 = _last_n(log_scan.get("scan_p95_samples", []), per_section_limit)
    scan_max = _last_n(log_scan.get("scan_max_samples", []), per_section_limit)

    # bridge_wait from audit elapsed (REQ/REP roundtrip elapsed_ms).
    bridge_from_audit = _last_n(audit_scan.get("reply_elapsed_samples_ms", []), per_section_limit)
    bridge_wait_from_audit = _last_n(audit_scan.get("reply_wait_samples_ms", []), per_section_limit)
    bridge_send_from_audit = _last_n(audit_scan.get("reply_send_samples_ms", []), per_section_limit)
    bridge_parse_from_audit = _last_n(audit_scan.get("reply_parse_samples_ms", []), per_section_limit)
    bridge_from_log = _last_n(log_scan.get("bridge_rtt_samples", []), per_section_limit)

    execution_lat = _last_n(log_scan.get("execution_latency_samples", []), per_section_limit)
    sec_samples = log_scan.get("section_metrics_samples") if isinstance(log_scan.get("section_metrics_samples"), dict) else {}

    def _section_from_runtime_metrics(section: str) -> Dict[str, Any] | None:
        rows = sec_samples.get(section, []) if isinstance(sec_samples, dict) else []
        if not isinstance(rows, list) or not rows:
            return None
        rows = _last_n(rows, per_section_limit)
        p50_vals = [float(r.get("p50_ms")) for r in rows if isinstance(r, dict) and isinstance(r.get("p50_ms"), (int, float))]
        p95_vals = [float(r.get("p95_ms")) for r in rows if isinstance(r, dict) and isinstance(r.get("p95_ms"), (int, float))]
        p99_vals = [float(r.get("p99_ms")) for r in rows if isinstance(r, dict) and isinstance(r.get("p99_ms"), (int, float))]
        if not p50_vals and not p95_vals and not p99_vals:
            return None
        return {
            "status": "MEASURED",
            "source": f"LOGS/safetybot.log:RUNTIME_SECTION_METRICS_10M ({section})",
            "sample_window_count": len(rows),
            "proxy_from_logged_p50": _stats(p50_vals),
            "proxy_from_logged_p95": _stats(p95_vals),
            "proxy_from_logged_p99": _stats(p99_vals),
            "derived_summary_ms": {
                "p50_ms": round(_percentile(p50_vals, 0.50), 3) if p50_vals else "UNKNOWN",
                "p95_ms": round(_percentile(p95_vals, 0.50), 3) if p95_vals else "UNKNOWN",
                "p99_ms": round(_percentile(p99_vals, 0.50), 3) if p99_vals else "UNKNOWN",
            },
        }

    sections: Dict[str, Any] = {
        "tick_ingest": {
            "status": "UNKNOWN",
            "reason": "NO_SECTION_TIMER_IN_LOGS",
            "next_action": "Add explicit timer marker around tick ingest path in SafetyBot.",
        },
        "session_gate": {
            "status": "UNKNOWN",
            "reason": "NO_SECTION_TIMER_IN_LOGS",
            "next_action": "Add explicit timer marker around session_liquidity gate evaluation.",
        },
        "cost_gate": {
            "status": "UNKNOWN",
            "reason": "NO_SECTION_TIMER_IN_LOGS",
            "next_action": "Add explicit timer marker around cost_microstructure gate evaluation.",
        },
        "decision_core": {
            "status": "UNKNOWN",
            "reason": "NO_SECTION_TIMER_IN_LOGS",
            "next_action": "Add explicit timer marker around decision aggregation path.",
        },
        "bridge_send": {
            "status": "UNKNOWN",
            "reason": "ONLY_ROUNDTRIP_MEASURED",
            "next_action": "Split send vs wait timing in bridge telemetry.",
        },
        "bridge_parse": {
            "status": "UNKNOWN",
            "reason": "ONLY_ROUNDTRIP_MEASURED",
            "next_action": "Add parse_ms telemetry in bridge and collect active window.",
        },
        "io_log": {
            "status": "UNKNOWN",
            "reason": "NO_IO_LATENCY_MARKERS",
            "next_action": "Add async log queue flush timing counters.",
        },
    }

    for sec_name in (
        "tick_ingest",
        "bridge_send",
        "bridge_wait",
        "bridge_parse",
        "session_gate",
        "cost_gate",
        "decision_core",
        "io_log",
    ):
        sec_out = _section_from_runtime_metrics(sec_name)
        if sec_out is not None:
            sections[sec_name] = sec_out

    # full loop measured via scan metrics snapshots (windowed proxy).
    if scan_p50 and scan_p95 and scan_max:
        sections["full_loop"] = {
            "status": "MEASURED_PROXY_WINDOWED",
            "source": "LOGS/safetybot.log:RUNTIME_METRICS_10M scan_p50_ms/scan_p95_ms/scan_max_ms",
            "sample_window_count": len(scan_p50),
            "proxy_from_scan_p50": _stats(scan_p50),
            "proxy_from_scan_p95": _stats(scan_p95),
            "proxy_from_scan_max": _stats(scan_max),
            "derived_summary_ms": {
                "p50_ms": round(_percentile(scan_p50, 0.50), 3),
                "p95_ms": round(_percentile(scan_p95, 0.50), 3),
                "p99_ms": round(_percentile(scan_max, 0.50), 3),
            },
        }
    else:
        sections["full_loop"] = {
            "status": "UNKNOWN",
            "reason": "NO_RUNTIME_METRICS_10M_SAMPLES",
            "next_action": "Run runtime long enough to emit RUNTIME_METRICS_10M lines.",
        }

    if bridge_send_from_audit:
        sections["bridge_send"] = {
            "status": "MEASURED",
            "source": "LOGS/audit_trail.jsonl:REPLY_RECEIVED.data.send_ms",
            "stats_ms": _stats(bridge_send_from_audit),
        }
    elif bridge_from_audit:
        sections["bridge_send"] = {
            "status": "MEASURED_PROXY",
            "source": "LOGS/audit_trail.jsonl:REPLY_RECEIVED.data.elapsed_ms",
            "stats_ms": _stats(bridge_from_audit),
            "note": "Proxy fallback because send_ms is not present in this log window.",
        }
    else:
        sections["bridge_send"] = {
            "status": "UNKNOWN",
            "reason": "NO_BRIDGE_SEND_SAMPLES",
            "next_action": "Enable send_ms telemetry in bridge and collect active window.",
        }

    # bridge wait: dedicated wait_ms preferred, fallback to elapsed proxy.
    if bridge_wait_from_audit:
        sections["bridge_wait"] = {
            "status": "MEASURED",
            "source": "LOGS/audit_trail.jsonl:REPLY_RECEIVED.data.wait_ms",
            "stats_ms": _stats(bridge_wait_from_audit),
            "note": "Wait latency excludes send phase when wait_ms is available.",
        }
    elif bridge_from_audit:
        sections["bridge_wait"] = {
            "status": "MEASURED_PROXY",
            "source": "LOGS/audit_trail.jsonl:REPLY_RECEIVED.data.elapsed_ms",
            "stats_ms": _stats(bridge_from_audit),
            "note": "Elapsed covers REQ/REP roundtrip wait in bridge channel.",
        }
    elif bridge_from_log:
        sections["bridge_wait"] = {
            "status": "MEASURED_PROXY",
            "source": "LOGS/safetybot.log:ZMQ_RTT.rtt_ms",
            "stats_ms": _stats(bridge_from_log),
            "note": "Fallback proxy when audit elapsed_ms is missing.",
        }
    else:
        sections["bridge_wait"] = {
            "status": "UNKNOWN",
            "reason": "NO_BRIDGE_RTT_SAMPLES",
            "next_action": "Enable bridge heartbeat telemetry and audit trail elapsed_ms.",
        }

    if bridge_parse_from_audit:
        sections["bridge_parse"] = {
            "status": "MEASURED",
            "source": "LOGS/audit_trail.jsonl:REPLY_RECEIVED.data.parse_ms",
            "stats_ms": _stats(bridge_parse_from_audit),
        }
    elif bridge_from_audit:
        sections["bridge_parse"] = {
            "status": "MEASURED_PROXY",
            "source": "LOGS/audit_trail.jsonl:REPLY_RECEIVED.data.elapsed_ms",
            "stats_ms": _stats(bridge_from_audit),
            "note": "Proxy fallback because parse_ms is not present in this log window.",
        }
    else:
        sections["bridge_parse"] = {
            "status": "UNKNOWN",
            "reason": "NO_BRIDGE_PARSE_SAMPLES",
            "next_action": "Enable parse_ms telemetry in bridge and collect active window.",
        }

    if execution_lat:
        sections["execution_call"] = {
            "status": "MEASURED",
            "source": "LOGS/safetybot.log:ORDER_SEND/ORDER_CHECK latency_ms",
            "stats_ms": _stats(execution_lat),
        }
    else:
        sec_out = _section_from_runtime_metrics("execution_call")
        if sec_out is not None:
            sections["execution_call"] = sec_out
        else:
            sections["execution_call"] = {
                "status": "UNKNOWN",
                "reason": "NO_ORDER_EXECUTION_EVENTS_IN_WINDOW",
                "next_action": "Collect during market-open/order-flow window or run controlled smoke order simulation.",
            }

    return sections


def _summarize_health(log_scan: Dict[str, Any], audit_scan: Dict[str, Any]) -> Dict[str, Any]:
    sent = int(audit_scan.get("command_sent_count", 0) or 0)
    tout = int(audit_scan.get("command_timeout_count", 0) or 0)
    timeout_rate = (float(tout) / float(sent)) if sent > 0 else 0.0
    q_backpressure = log_scan.get("q_backpressure_samples", [])
    q_timeouts = log_scan.get("q_timeout_samples", [])
    q_full = log_scan.get("q_full_samples", [])
    bridge_rtt_samples = log_scan.get("bridge_rtt_samples", [])
    rtt_n = len(bridge_rtt_samples) if isinstance(bridge_rtt_samples, list) else 0
    reply_n = int(audit_scan.get("reply_received_count", 0) or 0)
    empty_expl = "NON_EMPTY"
    if rtt_n == 0:
        if reply_n == 0 and sent > 0:
            empty_expl = "NO_SUCCESSFUL_REPLIES_IN_WINDOW"
        elif reply_n == 0 and sent == 0:
            empty_expl = "NO_COMMAND_ACTIVITY_IN_WINDOW"
        elif reply_n > 0:
            empty_expl = "LOG_WINDOW_OR_PATTERN_MISMATCH"
        else:
            empty_expl = "UNKNOWN"
    return {
        "bridge_commands": {"sent": sent, "timeouts": tout, "timeout_rate": round(timeout_rate, 6)},
        "bridge_rtt_observability": {
            "bridge_rtt_sampling_scope": "ALL_ACTIONS_FROM_SAFETYBOT_LOG_ZMQ_RTT",
            "bridge_rtt_samples_count": int(rtt_n),
            "bridge_rtt_success_count": int(reply_n),
            "bridge_rtt_timeout_count": int(tout),
            "bridge_rtt_action_counts": dict(log_scan.get("bridge_rtt_action_counts") or {}),
            "bridge_rtt_empty_list_explanation": empty_expl,
        },
        "queue_counters_runtime_metrics": {
            "q_backpressure_drops_max": int(max(q_backpressure)) if q_backpressure else "UNKNOWN",
            "q_timeouts_max": int(max(q_timeouts)) if q_timeouts else "UNKNOWN",
            "q_full_max": int(max(q_full)) if q_full else "UNKNOWN",
        },
    }


def build_report(root: Path, per_section_limit: int) -> Dict[str, Any]:
    safety_log = root / "LOGS" / "safetybot.log"
    audit_log = root / "LOGS" / "audit_trail.jsonl"
    stage1_path, stage1 = _read_latest_stage1(root)
    log_scan = _scan_safetybot_log(safety_log)
    audit_scan = _scan_audit_trail(audit_log)
    sections = _build_sections(log_scan, audit_scan, per_section_limit)
    health = _summarize_health(log_scan, audit_scan)

    stage1_p95 = (
        (stage1.get("current_runtime_snapshot") or {}).get("scan_p95_ms")
        if isinstance(stage1, dict)
        else None
    )
    full_loop_now = None
    full_loop = sections.get("full_loop") or {}
    derived = full_loop.get("derived_summary_ms") if isinstance(full_loop, dict) else None
    if isinstance(derived, dict):
        full_loop_now = derived.get("p95_ms")
    regression: Dict[str, Any] = {"status": "UNKNOWN"}
    if isinstance(stage1_p95, (int, float)) and isinstance(full_loop_now, (int, float)):
        delta = float(full_loop_now) - float(stage1_p95)
        pct = (delta / float(stage1_p95) * 100.0) if float(stage1_p95) != 0 else 0.0
        regression = {
            "status": "OK",
            "stage1_scan_p95_ms": float(stage1_p95),
            "stage2_full_loop_p95_proxy_ms": float(full_loop_now),
            "delta_ms": round(delta, 3),
            "delta_pct": round(pct, 3),
        }

    return {
        "schema": "oanda_mt5.latency_stage2_section_profile.v1",
        "ts_utc": _utc_now(),
        "workspace_root_path": str(root),
        "step": "STAGE_2_SECTIONAL_PROFILING",
        "inputs": {
            "safetybot_log": str(safety_log),
            "audit_trail_log": str(audit_log),
            "stage1_baseline_report": stage1_path,
            "per_section_sample_limit": int(per_section_limit),
        },
        "observation_window": {
            "safetybot_log_local_time": {
                "start": log_scan.get("first_ts_local", "UNKNOWN"),
                "end": log_scan.get("last_ts_local", "UNKNOWN"),
                "semantics": "LOCAL_LOG_TIME_UNSPECIFIED_TZ",
            },
            "audit_trail_utc_time": {
                "start": audit_scan.get("first_ts_utc", "UNKNOWN"),
                "end": audit_scan.get("last_ts_utc", "UNKNOWN"),
                "semantics": "UTC",
            },
        },
        "section_latency_ms": sections,
        "runtime_health_signals": health,
        "baseline_regression_check": regression,
        "gaps_and_next_actions": [
            {
                "gap": "Section coverage depends on active runtime window and current telemetry cardinality.",
                "impact": "Low-N windows may overstate or understate tail latency.",
                "next_action": "Collect at least one full market-active window before final pass/fail gating.",
            },
            {
                "gap": "execution_call not observed in current window.",
                "impact": "No measured execution latency distribution for this stage.",
                "next_action": "Collect in market-open window with real order flow or controlled smoke execution.",
            },
        ],
        "notes": [
            "Stage-2 report is measurement-only (no strategy changes).",
            "Bridge wait is measured from elapsed_ms where available; this is currently the strongest hard signal.",
        ],
    }


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Build stage-2 sectional latency profile for OANDA_MT5_SYSTEM.")
    p.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    p.add_argument("--out", default="")
    p.add_argument(
        "--per-section-sample-limit",
        type=int,
        default=5000,
        help="Keep only last N samples per section (0 = no cap).",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    report = build_report(root=root, per_section_limit=max(0, int(args.per_section_sample_limit)))
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    out = (
        Path(args.out).resolve()
        if args.out
        else root / "EVIDENCE" / "latency_stage2" / f"latency_stage2_section_profile_{stamp}.json"
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"LATENCY_STAGE2_SECTION_PROFILE_OK out={out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
