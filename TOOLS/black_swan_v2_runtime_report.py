from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

SCHEMA = "oanda.mt5.black_swan_v2_runtime_report.v1"

LINE_RX = re.compile(
    r"BLACK_SWAN_V2\s+state=(?P<state>[A-Z_]+)\s+action=(?P<action>[A-Z_]+)\s+"
    r"trigger=(?P<trigger>[A-Z_]+)\s+stress=(?P<stress>[-+]?\d+(?:\.\d+)?)\s+"
    r"cooldown_s=(?P<cooldown>[-+]?\d+(?:\.\d+)?)\s+reason=(?P<reason>[^\s]+)"
)
TS_RX = re.compile(r"^(?P<ts>\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[.,]\d{1,6})?)")


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _iso_utc(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _parse_line_timestamp(raw: str) -> Optional[datetime]:
    m = TS_RX.search(raw)
    if not m:
        return None
    text = m.group("ts").replace(",", ".")
    # logging timestamps are usually local naive; keep local tz assumption
    for fmt in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S.%f", "%Y-%m-%dT%H:%M:%S"):
        try:
            dt = datetime.strptime(text, fmt)
            local_tz = datetime.now().astimezone().tzinfo or timezone.utc
            return dt.replace(tzinfo=local_tz).astimezone(timezone.utc)
        except ValueError:
            continue
    return None


def _read_log_lines(path: Path) -> List[str]:
    if not path.exists():
        return []
    try:
        return path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except Exception:
        return []


def build_report(root: Path, hours: int) -> Dict[str, Any]:
    now_utc = _utc_now()
    cutoff = now_utc - timedelta(hours=max(1, int(hours)))
    log_path = root / "LOGS" / "safetybot.log"
    lines = _read_log_lines(log_path)

    total_scanned = 0
    matched_total = 0
    matched_in_window = 0
    unknown_ts_kept = 0

    states = Counter()
    actions = Counter()
    triggers = Counter()
    reasons = Counter()
    stress_values: List[float] = []
    cooldown_values: List[float] = []

    for line in lines:
        total_scanned += 1
        m = LINE_RX.search(line)
        if not m:
            continue
        matched_total += 1

        ts = _parse_line_timestamp(line)
        if ts is not None and ts < cutoff:
            continue
        if ts is None:
            unknown_ts_kept += 1
        matched_in_window += 1

        state = str(m.group("state") or "").strip().upper()
        action = str(m.group("action") or "").strip().upper()
        trigger = str(m.group("trigger") or "").strip().upper()
        reason = str(m.group("reason") or "").strip().upper()
        stress = float(m.group("stress") or 0.0)
        cooldown = float(m.group("cooldown") or 0.0)

        if state:
            states[state] += 1
        if action:
            actions[action] += 1
        if trigger:
            triggers[trigger] += 1
        if reason:
            reasons[reason] += 1
        stress_values.append(stress)
        cooldown_values.append(cooldown)

    max_stress = max(stress_values) if stress_values else 0.0
    avg_stress = (sum(stress_values) / len(stress_values)) if stress_values else 0.0
    max_cooldown = max(cooldown_values) if cooldown_values else 0.0
    top_reasons: List[Tuple[str, int]] = reasons.most_common(10)

    status = "NO_DATA"
    if matched_in_window > 0:
        if actions.get("FORCE_FLAT", 0) > 0 or actions.get("CLOSE_ONLY", 0) > 0:
            status = "HIGH_STRESS"
        elif actions.get("BLOCK_NEW_TRADES", 0) > 0:
            status = "GUARDED"
        else:
            status = "STABLE"

    report: Dict[str, Any] = {
        "schema": SCHEMA,
        "generated_at_utc": _iso_utc(now_utc),
        "root": str(root),
        "hours": int(hours),
        "window_start_utc": _iso_utc(cutoff),
        "window_end_utc": _iso_utc(now_utc),
        "log_path": str(log_path),
        "status": status,
        "scan": {
            "lines_scanned": int(total_scanned),
            "black_swan_v2_lines_total": int(matched_total),
            "black_swan_v2_lines_window": int(matched_in_window),
            "unknown_timestamp_lines_kept": int(unknown_ts_kept),
        },
        "metrics": {
            "max_stress_score": round(float(max_stress), 6),
            "avg_stress_score": round(float(avg_stress), 6),
            "max_cooldown_sec": round(float(max_cooldown), 3),
        },
        "counts": {
            "states": dict(states),
            "actions": dict(actions),
            "triggers": dict(triggers),
            "reasons_top10": [{"reason": k, "count": int(v)} for k, v in top_reasons],
        },
    }
    return report


def render_txt(report: Dict[str, Any]) -> str:
    lines: List[str] = []
    lines.append("BLACK SWAN V2 RUNTIME REPORT")
    lines.append(f"Status: {report.get('status')}")
    lines.append(
        f"Window: {report.get('window_start_utc')} -> {report.get('window_end_utc')} "
        f"({report.get('hours')}h)"
    )
    scan = report.get("scan") if isinstance(report.get("scan"), dict) else {}
    lines.append(
        f"Lines: scanned={scan.get('lines_scanned')} "
        f"matched_total={scan.get('black_swan_v2_lines_total')} "
        f"matched_window={scan.get('black_swan_v2_lines_window')}"
    )
    metrics = report.get("metrics") if isinstance(report.get("metrics"), dict) else {}
    lines.append(
        f"Stress: max={metrics.get('max_stress_score')} avg={metrics.get('avg_stress_score')} "
        f"cooldown_max_s={metrics.get('max_cooldown_sec')}"
    )

    counts = report.get("counts") if isinstance(report.get("counts"), dict) else {}
    states = counts.get("states") if isinstance(counts.get("states"), dict) else {}
    actions = counts.get("actions") if isinstance(counts.get("actions"), dict) else {}
    triggers = counts.get("triggers") if isinstance(counts.get("triggers"), dict) else {}
    lines.append(f"States: {json.dumps(states, ensure_ascii=False)}")
    lines.append(f"Actions: {json.dumps(actions, ensure_ascii=False)}")
    lines.append(f"Triggers: {json.dumps(triggers, ensure_ascii=False)}")

    lines.append("Top reasons:")
    reasons_top10 = counts.get("reasons_top10") if isinstance(counts.get("reasons_top10"), list) else []
    if reasons_top10:
        for item in reasons_top10:
            if not isinstance(item, dict):
                continue
            lines.append(f"- {item.get('reason')}: {item.get('count')}")
    else:
        lines.append("- brak danych")
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Black Swan v2 runtime report (from safetybot.log)")
    ap.add_argument("--root", default="C:/OANDA_MT5_SYSTEM")
    ap.add_argument("--hours", type=int, default=24)
    ap.add_argument("--out-report", default="")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    stamp = _utc_now().strftime("%Y%m%dT%H%M%SZ")

    if str(args.out_report).strip():
        out_json = Path(args.out_report).resolve()
    else:
        out_json = (root / "EVIDENCE" / "black_swan_v2" / f"black_swan_v2_runtime_{stamp}.json").resolve()
    out_txt = out_json.with_suffix(".txt")
    out_json.parent.mkdir(parents=True, exist_ok=True)

    report = build_report(root=root, hours=int(args.hours))
    out_json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    out_txt.write_text(render_txt(report), encoding="utf-8")

    latest_json = out_json.parent / "black_swan_v2_runtime_latest.json"
    latest_txt = out_json.parent / "black_swan_v2_runtime_latest.txt"
    latest_json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    latest_txt.write_text(render_txt(report), encoding="utf-8")

    print(
        "BLACK_SWAN_V2_RUNTIME_REPORT_DONE "
        f"status={report.get('status')} "
        f"window_lines={report.get('scan', {}).get('black_swan_v2_lines_window', 0)} "
        f"json={out_json}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
