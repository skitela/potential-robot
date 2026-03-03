#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List


RUNTIME_METRICS_RE = re.compile(
    r"RUNTIME_METRICS_10M .*?"
    r"scan_p50_ms=(?P<scan_p50>\d+)\s+"
    r"scan_p95_ms=(?P<scan_p95>\d+)\s+"
    r"scan_max_ms=(?P<scan_max>\d+)"
)

RUNTIME_SECTION_RE = re.compile(r"RUNTIME_SECTION_METRICS_10M\b")


def _utc_now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def _read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


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


def _iter_lines_from_offset(path: Path, offset_bytes: int) -> Iterable[str]:
    with path.open("rb") as fh:
        try:
            size = int(path.stat().st_size)
        except Exception:
            size = 0
        seek_pos = max(0, int(offset_bytes))
        if seek_pos > size:
            seek_pos = 0
        fh.seek(seek_pos)
        while True:
            raw = fh.readline()
            if not raw:
                break
            yield raw.decode("utf-8", errors="ignore").rstrip("\r\n")


def _iter_jsonl_from_offset(path: Path, offset_bytes: int) -> Iterable[Dict[str, Any]]:
    for line in _iter_lines_from_offset(path, offset_bytes):
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if isinstance(obj, dict):
            yield obj


def _parse_kv_tokens(line: str) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for token in str(line or "").split():
        if "=" not in token:
            continue
        k, v = token.split("=", 1)
        out[str(k).strip()] = str(v).strip().strip(",")
    return out


def _latest_start_marker(root: Path) -> Path:
    files = sorted(
        (root / "EVIDENCE" / "bridge_audit").glob("bridge_soak_window_start_*.json"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    if not files:
        raise FileNotFoundError("No bridge_soak_window_start_*.json found in EVIDENCE/bridge_audit.")
    return files[0]


def _baseline_decision_core_n(before_report: Dict[str, Any]) -> int:
    rr = ((before_report.get("pass_fail") or {}).get("review_required") or [])
    if not isinstance(rr, list):
        return 0
    for item in rr:
        text = str(item)
        if text.startswith("DECISION_CORE_LOW_N:"):
            try:
                return int(text.split(":", 1)[1])
            except Exception:
                return 0
    return 0


def _extract_timeout_reason(obj: Dict[str, Any]) -> str:
    data = obj.get("data")
    if not isinstance(data, dict):
        data = {}
    reason = str(data.get("bridge_timeout_reason") or data.get("reason") or "").upper()
    subreason = str(data.get("bridge_timeout_subreason") or "").upper()
    if reason and subreason and subreason != "NONE":
        return f"{reason}:{subreason}"
    if reason:
        return reason
    for key in ("phase", "error"):
        value = data.get(key)
        if value:
            return str(value).upper()
    return "UNKNOWN"


def _extract_command_type(obj: Dict[str, Any]) -> str:
    data = obj.get("data")
    if not isinstance(data, dict):
        data = {}
    cmd_type = str(data.get("command_type") or "").strip().upper()
    if cmd_type:
        return cmd_type
    action = str(data.get("action") or data.get("command_action") or "").strip().upper()
    if action == "HEARTBEAT":
        return "HEARTBEAT"
    if action == "TRADE":
        return "TRADE"
    return "OTHER"


def _extract_timeout_budget(obj: Dict[str, Any]) -> str:
    data = obj.get("data")
    if not isinstance(data, dict):
        data = {}
    budget = data.get("timeout_budget_ms")
    try:
        return str(int(budget))
    except Exception:
        return "UNKNOWN"


def _parse_window(
    safetybot_log: Path,
    audit_log: Path,
    safety_offset: int,
    audit_offset: int,
) -> Dict[str, Any]:
    reply_send: List[float] = []
    reply_wait: List[float] = []
    reply_parse: List[float] = []
    event_counts: Counter[str] = Counter()
    timeout_reason_counts: Counter[str] = Counter()
    timeout_reason_by_command_type: Counter[str] = Counter()
    timeout_reason_by_timeout_budget: Counter[str] = Counter()
    audit_reason_counts: Counter[str] = Counter()
    late_response_by_command_type: Counter[str] = Counter()
    late_response_by_timeout_budget: Counter[str] = Counter()
    late_response_count = 0
    command_sent_count = 0
    command_timeout_count = 0
    command_sent_by_type: Counter[str] = Counter()
    command_timeout_by_type: Counter[str] = Counter()

    first_audit_ts = "UNKNOWN"
    last_audit_ts = "UNKNOWN"
    for obj in _iter_jsonl_from_offset(audit_log, audit_offset):
        ts = str(obj.get("timestamp_utc") or "UNKNOWN")
        if first_audit_ts == "UNKNOWN":
            first_audit_ts = ts
        last_audit_ts = ts
        event_type = str(obj.get("event_type") or obj.get("event_type_norm") or "UNKNOWN").upper()
        event_counts[event_type] += 1
        if event_type == "COMMAND_SENT":
            command_sent_count += 1
            command_sent_by_type[_extract_command_type(obj)] += 1
        elif event_type == "COMMAND_TIMEOUT":
            command_timeout_count += 1
            reason = _extract_timeout_reason(obj)
            cmd_type = _extract_command_type(obj)
            budget = _extract_timeout_budget(obj)
            timeout_reason_counts[reason] += 1
            command_timeout_by_type[cmd_type] += 1
            timeout_reason_by_command_type[f"{cmd_type}|{reason}"] += 1
            timeout_reason_by_timeout_budget[f"{budget}|{reason}"] += 1
        elif event_type == "COMMAND_FAILED":
            audit_reason_counts[_extract_timeout_reason(obj)] += 1
        elif event_type == "REPLY_RECEIVED":
            data = obj.get("data")
            if not isinstance(data, dict):
                data = {}
            for src_key, sink in (("send_ms", reply_send), ("wait_ms", reply_wait), ("parse_ms", reply_parse)):
                try:
                    sink.append(float(data.get(src_key)))
                except Exception:
                    pass
            response_over_budget = bool(data.get("response_over_budget"))
            if not response_over_budget:
                state = str(data.get("response_budget_state") or "").upper()
                response_over_budget = state == "OVER_BUDGET"
            if response_over_budget:
                late_response_count += 1
                cmd_type = _extract_command_type(obj)
                budget = _extract_timeout_budget(obj)
                late_response_by_command_type[cmd_type] += 1
                late_response_by_timeout_budget[budget] += 1

    runtime_scan_p50: List[float] = []
    runtime_scan_p95: List[float] = []
    runtime_scan_max: List[float] = []
    section_samples: Dict[str, List[Dict[str, float]]] = {
        "tick_ingest": [],
        "bridge_send": [],
        "bridge_wait": [],
        "bridge_parse": [],
        "decision_core": [],
        "full_loop": [],
    }
    bridge_diag_status: Counter[str] = Counter()
    bridge_diag_reason: Counter[str] = Counter()
    heartbeat_failsafe_window = 0
    first_log_ts = "UNKNOWN"
    last_log_ts = "UNKNOWN"

    for line in _iter_lines_from_offset(safetybot_log, safety_offset):
        if not line:
            continue
        ts = line.split(" | ", 1)[0] if " | " in line else "UNKNOWN"
        if first_log_ts == "UNKNOWN":
            first_log_ts = ts
        last_log_ts = ts

        if "HEARTBEAT_FAILSAFE_ACTIVE" in line:
            heartbeat_failsafe_window += 1

        m = RUNTIME_METRICS_RE.search(line)
        if m:
            try:
                scan_p50 = float(m.group("scan_p50"))
                scan_p95 = float(m.group("scan_p95"))
                scan_max = float(m.group("scan_max"))
                runtime_scan_p50.append(scan_p50)
                runtime_scan_p95.append(scan_p95)
                runtime_scan_max.append(scan_max)
                section_samples["full_loop"].append(
                    {"p50_ms": scan_p50, "p95_ms": scan_p95, "p99_ms": scan_max}
                )
            except Exception:
                pass

        if RUNTIME_SECTION_RE.search(line):
            kv = _parse_kv_tokens(line)
            for section in ("tick_ingest", "bridge_send", "bridge_wait", "bridge_parse", "decision_core"):
                try:
                    p50 = float(kv.get(f"{section}_p50_ms", "nan"))
                    p95 = float(kv.get(f"{section}_p95_ms", "nan"))
                    p99 = float(kv.get(f"{section}_p99_ms", "nan"))
                except Exception:
                    continue
                if p50 != p50 or p95 != p95 or p99 != p99:  # NaN guard
                    continue
                section_samples[section].append({"p50_ms": p50, "p95_ms": p95, "p99_ms": p99})

        if "BRIDGE_DIAG " in line:
            kv = _parse_kv_tokens(line)
            action = str(kv.get("action", "UNKNOWN")).upper()
            status = str(kv.get("status", "UNKNOWN")).upper()
            reason = str(kv.get("reason", "UNKNOWN")).upper()
            bridge_diag_status[f"{action}|{status}"] += 1
            bridge_diag_reason[f"{action}|{reason}"] += 1

    heartbeat_failsafe_historical = 0
    if safetybot_log.exists():
        with safetybot_log.open("r", encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                if "HEARTBEAT_FAILSAFE_ACTIVE" in line:
                    heartbeat_failsafe_historical += 1

    timeout_rate = (float(command_timeout_count) / float(command_sent_count)) if command_sent_count > 0 else 0.0
    timeout_rates_by_type: Dict[str, Any] = {}
    for cmd_type in sorted(set(list(command_sent_by_type.keys()) + list(command_timeout_by_type.keys()))):
        sent_n = int(command_sent_by_type.get(cmd_type, 0))
        tout_n = int(command_timeout_by_type.get(cmd_type, 0))
        timeout_rates_by_type[cmd_type] = {
            "sent": sent_n,
            "timeouts": tout_n,
            "timeout_rate": round((float(tout_n) / float(sent_n)) if sent_n > 0 else 0.0, 6),
        }
    timeout_rate_trade = (timeout_rates_by_type.get("TRADE") or {}).get("timeout_rate", 0.0)
    timeout_rate_hb = (timeout_rates_by_type.get("HEARTBEAT") or {}).get("timeout_rate", 0.0)
    timeout_rate_other = (timeout_rates_by_type.get("OTHER") or {}).get("timeout_rate", 0.0)

    def _section_summary(section: str) -> Dict[str, Any]:
        rows = section_samples.get(section, [])
        p50_vals = [r["p50_ms"] for r in rows]
        p95_vals = [r["p95_ms"] for r in rows]
        p99_vals = [r["p99_ms"] for r in rows]
        return {
            "n": len(rows),
            "p50_ms": round(_percentile(p50_vals, 0.50), 3) if p50_vals else "UNKNOWN",
            "p95_ms": round(_percentile(p95_vals, 0.50), 3) if p95_vals else "UNKNOWN",
            "p99_ms": round(_percentile(p99_vals, 0.50), 3) if p99_vals else "UNKNOWN",
            "worst_p99_ms": round(max(p99_vals), 3) if p99_vals else "UNKNOWN",
        }

    top_timeout_reasons = [
        {"reason": reason, "count": count}
        for reason, count in timeout_reason_counts.most_common(10)
    ]
    if not top_timeout_reasons and bridge_diag_reason:
        top_timeout_reasons = [
            {"reason": reason, "count": count}
            for reason, count in bridge_diag_reason.most_common(10)
            if "TIMEOUT" in reason or "FAILED" in reason
        ]

    return {
        "audit_window": {
            "safetybot_log_local_time": {"start": first_log_ts, "end": last_log_ts},
            "audit_trail_utc": {"start": first_audit_ts, "end": last_audit_ts},
        },
        "metrics": {
            "bridge_send": _stats(reply_send),
            "bridge_wait": _stats(reply_wait),
            "bridge_parse": _stats(reply_parse),
            "timeout_rate": round(timeout_rate, 6),
            "timeout_rate_all": round(timeout_rate, 6),
            "timeout_rate_heartbeat": timeout_rate_hb,
            "timeout_rate_trade_path": timeout_rate_trade,
            "timeout_rate_other": timeout_rate_other,
            "command_sent": command_sent_count,
            "command_timeout": command_timeout_count,
            "decision_core": _section_summary("decision_core"),
            "full_loop": _section_summary("full_loop"),
            "tick_ingest": _section_summary("tick_ingest"),
            "bridge_wait_runtime_snapshots": _section_summary("bridge_wait"),
        },
        "reasons": {
            "bridge_timeout_reason_top": top_timeout_reasons,
            "bridge_timeout_reason_by_command_type": [
                {"key": key, "count": count}
                for key, count in timeout_reason_by_command_type.most_common(20)
            ],
            "bridge_timeout_reason_by_timeout_budget_ms": [
                {"key": key, "count": count}
                for key, count in timeout_reason_by_timeout_budget.most_common(20)
            ],
            "bridge_diag_status_counts": dict(bridge_diag_status),
            "bridge_diag_reason_counts": dict(bridge_diag_reason),
            "audit_event_counts": dict(event_counts),
            "audit_reason_counts": dict(audit_reason_counts),
            "command_counts_by_type": dict(command_sent_by_type),
            "timeout_counts_by_type": dict(command_timeout_by_type),
            "timeout_rates_by_type": timeout_rates_by_type,
            "late_response_over_budget": {
                "count": int(late_response_count),
                "by_command_type": dict(late_response_by_command_type),
                "by_timeout_budget_ms": dict(late_response_by_timeout_budget),
            },
        },
        "heartbeat_failsafe_events": {
            "current_window": heartbeat_failsafe_window,
            "historical_total": heartbeat_failsafe_historical,
        },
        "incidents": {
            "bridge_failed_events": int(sum(v for k, v in bridge_diag_status.items() if k.endswith("|FAILED"))),
            "heartbeat_failsafe_current_window": heartbeat_failsafe_window,
            "top_reason_codes": [
                {"reason_code": reason, "count": count}
                for reason, count in bridge_diag_reason.most_common(10)
            ],
        },
    }


def _cmp(before_val: Any, after_val: Any) -> Any:
    if not isinstance(before_val, (int, float)) or not isinstance(after_val, (int, float)):
        return "UNKNOWN"
    return round(float(after_val) - float(before_val), 3)


def _build_report(
    root: Path,
    marker_path: Path,
    stage2_report_path: Path,
) -> Dict[str, Any]:
    marker = _read_json(marker_path)
    markers = marker.get("markers") or {}
    audit_offset = int(markers.get("audit_trail_jsonl_offset_bytes") or 0)
    safety_offset = int(markers.get("safetybot_log_offset_bytes") or 0)

    baseline_inputs = marker.get("baseline_inputs") or {}
    before_path = Path(str(baseline_inputs.get("latest_bridge_audit") or "")).resolve()
    before = _read_json(before_path) if before_path.exists() else {}
    before_metrics = before.get("metrics") or {}

    safetybot_log = root / "LOGS" / "safetybot.log"
    audit_log = root / "LOGS" / "audit_trail.jsonl"
    after = _parse_window(
        safetybot_log=safetybot_log,
        audit_log=audit_log,
        safety_offset=safety_offset,
        audit_offset=audit_offset,
    )
    after_metrics = after.get("metrics") or {}

    before_timeout_reasons = []
    before_log_audit = before.get("log_audit") or {}
    before_reason_counts = before_log_audit.get("bridge_diag_reason_counts") or {}
    if isinstance(before_reason_counts, dict):
        for key, value in before_reason_counts.items():
            try:
                count = int(value)
            except Exception:
                continue
            before_timeout_reasons.append({"reason": str(key), "count": count})
    before_timeout_reasons = sorted(before_timeout_reasons, key=lambda x: x["count"], reverse=True)[:10]

    before_decision_n = _baseline_decision_core_n(before)
    comparison = {
        "bridge_send_p95_delta_ms": _cmp(
            (before_metrics.get("bridge_send") or {}).get("p95_ms"),
            (after_metrics.get("bridge_send") or {}).get("p95_ms"),
        ),
        "bridge_wait_p95_delta_ms": _cmp(
            (before_metrics.get("bridge_wait") or {}).get("p95_ms"),
            (after_metrics.get("bridge_wait") or {}).get("p95_ms"),
        ),
        "bridge_wait_p99_delta_ms": _cmp(
            (before_metrics.get("bridge_wait") or {}).get("p99_ms"),
            (after_metrics.get("bridge_wait") or {}).get("p99_ms"),
        ),
        "bridge_parse_p95_delta_ms": _cmp(
            (before_metrics.get("bridge_parse") or {}).get("p95_ms"),
            (after_metrics.get("bridge_parse") or {}).get("p95_ms"),
        ),
        "timeout_rate_delta": _cmp(
            before_metrics.get("bridge_timeout_rate"),
            after_metrics.get("timeout_rate"),
        ),
        "full_loop_p95_delta_ms": _cmp(
            (before_metrics.get("full_loop") or {}).get("p95_ms"),
            (after_metrics.get("full_loop") or {}).get("p95_ms"),
        ),
        "decision_core_p95_delta_ms": _cmp(
            (before_metrics.get("decision_core") or {}).get("p95_ms"),
            (after_metrics.get("decision_core") or {}).get("p95_ms"),
        ),
    }

    after_bridge_wait_p95 = (after_metrics.get("bridge_wait") or {}).get("p95_ms")
    after_bridge_wait_p99 = (after_metrics.get("bridge_wait") or {}).get("p99_ms")
    after_timeout_rate = after_metrics.get("timeout_rate")
    verdict = "PASS"
    review_required: List[str] = []
    if isinstance(after_bridge_wait_p95, (int, float)) and after_bridge_wait_p95 > 800:
        verdict = "REVIEW_REQUIRED"
        review_required.append(f"BRIDGE_WAIT_P95_AUDIT_THRESHOLD_EXCEEDED:{after_bridge_wait_p95}")
    if isinstance(after_timeout_rate, (int, float)) and after_timeout_rate > 0.02:
        verdict = "REVIEW_REQUIRED"
        review_required.append(f"TIMEOUT_RATE_HIGH:{after_timeout_rate}")
    decision_n = int((after_metrics.get("decision_core") or {}).get("n") or 0)
    if decision_n < 3:
        verdict = "REVIEW_REQUIRED"
        review_required.append(f"DECISION_CORE_LOW_N:{decision_n}")

    goal_tracking = {
        "bridge_wait_p95_goal_lt_700_ms": (
            "PASS" if isinstance(after_bridge_wait_p95, (int, float)) and after_bridge_wait_p95 < 700 else "NOT_MET"
        ),
        "bridge_wait_p99_goal_lt_850_ms": (
            "PASS" if isinstance(after_bridge_wait_p99, (int, float)) and after_bridge_wait_p99 < 850 else "NOT_MET"
        ),
    }

    used_inputs = [
        str(marker_path),
        str(before_path) if before_path.exists() else "UNKNOWN",
        str(stage2_report_path),
        str(safetybot_log),
        str(audit_log),
    ]
    input_timestamps: Dict[str, str] = {}
    for p in used_inputs:
        pp = Path(p)
        if pp.exists():
            input_timestamps[p] = datetime.fromtimestamp(pp.stat().st_mtime, UTC).isoformat().replace("+00:00", "Z")

    return {
        "schema": "oanda_mt5.bridge_soak_comparison.v1",
        "ts_utc": _utc_now(),
        "WORKSPACE_ROOT_PATH": str(root),
        "CURRENT_WORKING_DIRECTORY": str(Path.cwd()),
        "INPUT_REPORT_PATHS_USED": used_inputs,
        "INPUT_REPORT_TIMESTAMPS": input_timestamps,
        "context": {
            "runtime_profile": str(marker.get("runtime_profile") or "UNKNOWN"),
            "marker_ts_utc": marker.get("ts_utc", "UNKNOWN"),
        },
        "before_snapshot": {
            "bridge_report_path": str(before_path) if before_path.exists() else "UNKNOWN",
            "metrics": {
                "bridge_send": before_metrics.get("bridge_send", {}),
                "bridge_wait": before_metrics.get("bridge_wait", {}),
                "bridge_parse": before_metrics.get("bridge_parse", {}),
                "timeout_rate": before_metrics.get("bridge_timeout_rate", "UNKNOWN"),
                "full_loop": before_metrics.get("full_loop", {}),
                "decision_core": {
                    **(before_metrics.get("decision_core", {}) if isinstance(before_metrics.get("decision_core"), dict) else {}),
                    "n": before_decision_n,
                },
            },
            "top_bridge_timeout_reasons": before_timeout_reasons,
        },
        "after_soak_window": after,
        "comparison": comparison,
        "goal_tracking": goal_tracking,
        "verdict": {
            "status": verdict,
            "review_required": review_required,
            "notes": [
                "A7 soak window compared against previous bridge audit snapshot.",
                "No strategy changes; measurement/audit only.",
            ],
        },
        "stage2_profile_used": str(stage2_report_path),
    }


def _render_txt(report: Dict[str, Any]) -> str:
    before = report.get("before_snapshot") or {}
    after = report.get("after_soak_window") or {}
    am = after.get("metrics") or {}
    reasons = after.get("reasons") or {}
    lines = []
    lines.append("META_BRIDGE_SOAK_COMPARE")
    lines.append(f"TS_UTC: {report.get('ts_utc')}")
    lines.append(f"WORKSPACE_ROOT_PATH: {report.get('WORKSPACE_ROOT_PATH')}")
    lines.append(f"CURRENT_WORKING_DIRECTORY: {report.get('CURRENT_WORKING_DIRECTORY')}")
    lines.append("")
    lines.append("BEFORE_AFTER")
    lines.append(f"BEFORE_BRIDGE_REPORT: {before.get('bridge_report_path')}")
    lines.append(f"AFTER_WINDOW_LOG_TIME: {(after.get('audit_window') or {}).get('safetybot_log_local_time')}")
    lines.append(f"AFTER_WINDOW_AUDIT_UTC: {(after.get('audit_window') or {}).get('audit_trail_utc')}")
    lines.append("")
    lines.append("METRICS_AFTER")
    for key in ("bridge_send", "bridge_wait", "bridge_parse", "full_loop", "decision_core", "tick_ingest"):
        lines.append(f"- {key}: {am.get(key)}")
    lines.append(f"- timeout_rate: {am.get('timeout_rate')}")
    lines.append(f"- timeout_rate_all: {am.get('timeout_rate_all')}")
    lines.append(f"- timeout_rate_heartbeat: {am.get('timeout_rate_heartbeat')}")
    lines.append(f"- timeout_rate_trade_path: {am.get('timeout_rate_trade_path')}")
    lines.append(f"- timeout_rate_other: {am.get('timeout_rate_other')}")
    lines.append(f"- command_sent: {am.get('command_sent')}")
    lines.append(f"- command_timeout: {am.get('command_timeout')}")
    lines.append("")
    lines.append("TOP_BRIDGE_TIMEOUT_REASON")
    for item in (reasons.get("bridge_timeout_reason_top") or []):
        lines.append(f"- {item.get('reason')}: {item.get('count')}")
    lines.append("")
    lines.append("TIMEOUT_REASON_BY_COMMAND_TYPE")
    for item in (reasons.get("bridge_timeout_reason_by_command_type") or []):
        lines.append(f"- {item.get('key')}: {item.get('count')}")
    lines.append("")
    lines.append("TIMEOUT_REASON_BY_TIMEOUT_BUDGET_MS")
    for item in (reasons.get("bridge_timeout_reason_by_timeout_budget_ms") or []):
        lines.append(f"- {item.get('key')}: {item.get('count')}")
    lines.append("")
    lines.append("LATE_RESPONSE_OVER_BUDGET")
    lines.append(str(reasons.get("late_response_over_budget")))
    lines.append("")
    lines.append("TIMEOUT_RATES_BY_TYPE")
    lines.append(str(reasons.get("timeout_rates_by_type")))
    lines.append("")
    lines.append("HEARTBEAT_FAILSAFE_EVENTS")
    hb = after.get("heartbeat_failsafe_events") or {}
    lines.append(f"- current_window: {hb.get('current_window')}")
    lines.append(f"- historical_total: {hb.get('historical_total')}")
    lines.append("")
    lines.append("VERDICT")
    lines.append(str(report.get("verdict")))
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build A7 bridge soak comparison report.")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--start-marker", default="")
    parser.add_argument("--stage2-report", default="")
    parser.add_argument("--out-json", default="")
    parser.add_argument("--out-txt", default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    marker_path = Path(args.start_marker).resolve() if args.start_marker else _latest_start_marker(root)
    if args.stage2_report:
        stage2_report = Path(args.stage2_report).resolve()
    else:
        stage2_candidates = sorted(
            (root / "EVIDENCE" / "latency_stage2").glob("latency_stage2_section_profile_*.json"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        if not stage2_candidates:
            raise FileNotFoundError("No latency_stage2_section_profile_*.json found.")
        stage2_report = stage2_candidates[0]

    report = _build_report(root=root, marker_path=marker_path, stage2_report_path=stage2_report)
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    out_json = (
        Path(args.out_json).resolve()
        if args.out_json
        else root / "EVIDENCE" / "bridge_audit" / f"bridge_soak_compare_{stamp}.json"
    )
    out_txt = (
        Path(args.out_txt).resolve()
        if args.out_txt
        else root / "EVIDENCE" / "bridge_audit" / f"bridge_soak_compare_{stamp}.txt"
    )
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_txt.parent.mkdir(parents=True, exist_ok=True)
    report["OUTPUT_REPORT_PATH"] = str(out_json)
    report["OUTPUT_REPORT_PATH_TXT"] = str(out_txt)
    out_json.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    out_txt.write_text(_render_txt(report), encoding="utf-8")
    print(f"BRIDGE_SOAK_COMPARE_OK json={out_json} txt={out_txt}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
