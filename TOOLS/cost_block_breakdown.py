#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
from collections import Counter
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple
from zoneinfo import ZoneInfo

UTC = dt.timezone.utc
LOCAL_TZ_DEFAULT = "Europe/Warsaw"


def _parse_log_ts(line: str, local_tz: ZoneInfo) -> Optional[dt.datetime]:
    if len(line) < 23:
        return None
    raw = line[:23]
    try:
        naive = dt.datetime.strptime(raw, "%Y-%m-%d %H:%M:%S,%f")
    except ValueError:
        return None
    return naive.replace(tzinfo=local_tz).astimezone(UTC)


def _last_restart_utc(safety_log: Path, local_tz: ZoneInfo) -> Optional[dt.datetime]:
    if not safety_log.exists():
        return None
    last: Optional[dt.datetime] = None
    for line in safety_log.read_text(encoding="utf-8", errors="replace").splitlines():
        if "Runtime root:" not in line:
            continue
        ts = _parse_log_ts(line, local_tz)
        if ts is not None:
            last = ts
    return last


def _iter_jsonl(path: Path) -> Iterable[Dict[str, Any]]:
    if not path.exists():
        return
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            try:
                payload = json.loads(line)
            except Exception:
                continue
            if isinstance(payload, dict):
                yield payload


def _within_start(payload: Dict[str, Any], start_utc: dt.datetime) -> bool:
    ts_raw = payload.get("ts_utc")
    if not isinstance(ts_raw, str):
        return False
    try:
        ts = dt.datetime.fromisoformat(ts_raw.replace("Z", "+00:00")).astimezone(UTC)
    except ValueError:
        return False
    return ts >= start_utc


def _tail_log_since(safety_log: Path, start_utc: dt.datetime, local_tz: ZoneInfo) -> List[str]:
    if not safety_log.exists():
        return []
    out: List[str] = []
    for line in safety_log.read_text(encoding="utf-8", errors="replace").splitlines():
        ts = _parse_log_ts(line, local_tz)
        if ts is None:
            continue
        if ts >= start_utc:
            out.append(line)
    return out


def build_block_breakdown(
    *,
    root: Path,
    start_utc: dt.datetime,
    local_tz: ZoneInfo,
) -> Dict[str, Any]:
    logs_dir = root / "LOGS"
    telemetry_path = logs_dir / "execution_telemetry_v2.jsonl"
    safety_log = logs_dir / "safetybot.log"
    guard_state_path = root / "EVIDENCE" / "cost_guard_auto_relax_status.json"

    tele_rows = [row for row in _iter_jsonl(telemetry_path) if _within_start(row, start_utc)]
    safety_lines = _tail_log_since(safety_log, start_utc, local_tz)

    event_counts = Counter(str(row.get("event_type") or "NONE") for row in tele_rows)
    block_cost = [r for r in tele_rows if str(r.get("event_type")) == "ENTRY_BLOCK_COST"]
    block_basket = [r for r in tele_rows if str(r.get("event_type")) == "ENTRY_BLOCK_BASKET"]
    block_micro = [r for r in tele_rows if str(r.get("event_type")) == "ENTRY_SHADOW_BLOCK_COST_MICROSTRUCTURE"]

    ratios = [float(r.get("cost_target_to_estimated_ratio")) for r in block_cost if r.get("cost_target_to_estimated_ratio") is not None]
    ratio_ge_min = 0
    ratio_lt_min = 0
    for row in block_cost:
        rv = row.get("cost_target_to_estimated_ratio")
        mv = row.get("cost_ratio_min_required")
        if rv is None or mv is None:
            continue
        if float(rv) >= float(mv):
            ratio_ge_min += 1
        else:
            ratio_lt_min += 1

    safety_counter = Counter()
    for line in safety_lines:
        if "ENTRY_SKIP_PRE" in line:
            safety_counter["entry_skip_pre"] += 1
        if "ENTRY_SKIP " in line:
            safety_counter["entry_skip"] += 1
        if "ENTRY_READY" in line:
            safety_counter["entry_ready"] += 1
        if "ENTRY_SIGNAL" in line:
            safety_counter["entry_signal"] += 1
        if "Order failed:" in line:
            safety_counter["order_failed"] += 1

    guard_state: Dict[str, Any] = {}
    if guard_state_path.exists():
        try:
            guard_state = json.loads(guard_state_path.read_text(encoding="utf-8"))
        except Exception:
            guard_state = {}

    diagnosis = {
        "primary_block_driver": "NONE",
        "ratio_gate_not_driver": False,
        "cost_unknown_block_active": False,
    }
    if block_cost:
        reasons = Counter(str(r.get("reason_code") or "NONE") for r in block_cost)
        primary_reason = reasons.most_common(1)[0][0]
        diagnosis["primary_block_driver"] = primary_reason
        diagnosis["ratio_gate_not_driver"] = bool(ratio_ge_min > 0 and ratio_lt_min == 0)
        if primary_reason == "BLOCK_TRADE_COST_UNKNOWN":
            diagnosis["cost_unknown_block_active"] = True
    elif block_basket:
        reasons = Counter(str(r.get("reason_code") or "NONE") for r in block_basket)
        diagnosis["primary_block_driver"] = reasons.most_common(1)[0][0]

    return {
        "schema_version": "oanda.mt5.cost_block_breakdown.v1",
        "generated_at_utc": dt.datetime.now(tz=UTC).isoformat().replace("+00:00", "Z"),
        "start_utc": start_utc.isoformat().replace("+00:00", "Z"),
        "event_counts": dict(event_counts),
        "entry_block_cost": {
            "count": len(block_cost),
            "by_reason_code": dict(Counter(str(r.get("reason_code") or "NONE") for r in block_cost)),
            "by_quality": dict(Counter(str(r.get("cost_estimation_quality") or "NONE") for r in block_cost)),
            "by_symbol": dict(Counter(str(r.get("symbol_canonical") or r.get("symbol_raw") or "NONE") for r in block_cost)),
            "ratio_ge_min": int(ratio_ge_min),
            "ratio_lt_min": int(ratio_lt_min),
            "ratio_min": min(ratios) if ratios else None,
            "ratio_max": max(ratios) if ratios else None,
        },
        "entry_block_basket": {
            "count": len(block_basket),
            "by_reason_code": dict(Counter(str(r.get("reason_code") or "NONE") for r in block_basket)),
            "by_symbol": dict(Counter(str(r.get("symbol_canonical") or r.get("symbol_raw") or "NONE") for r in block_basket)),
        },
        "entry_shadow_block_cost_microstructure": {
            "count": len(block_micro),
            "by_reason_code": dict(Counter(str(r.get("reason_code") or "NONE") for r in block_micro)),
            "by_grade": dict(Counter(str(r.get("cost_grade") or "NONE") for r in block_micro)),
            "null_spread_roll_mean_points": int(sum(1 for r in block_micro if r.get("spread_roll_mean_points") is None)),
            "null_spread_roll_p95_points": int(sum(1 for r in block_micro if r.get("spread_roll_p95_points") is None)),
            "null_tick_rate_1s": int(sum(1 for r in block_micro if r.get("tick_rate_1s") is None)),
        },
        "safety_runtime": dict(safety_counter),
        "cost_guard_auto_relax_state": guard_state,
        "diagnosis": diagnosis,
    }


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Generate runtime block breakdown for SafetyBot execution telemetry.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--mode", choices=("since_restart", "lookback_minutes"), default="since_restart")
    ap.add_argument("--lookback-minutes", type=int, default=60)
    ap.add_argument("--local-tz", default=LOCAL_TZ_DEFAULT)
    ap.add_argument("--out-json", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    local_tz = ZoneInfo(str(args.local_tz))
    safety_log = root / "LOGS" / "safetybot.log"
    now_utc = dt.datetime.now(tz=UTC)
    start_utc = now_utc - dt.timedelta(minutes=max(1, int(args.lookback_minutes)))
    if str(args.mode) == "since_restart":
        restart_utc = _last_restart_utc(safety_log, local_tz)
        if restart_utc is not None:
            start_utc = restart_utc
    out_json = (
        Path(args.out_json).resolve()
        if str(args.out_json).strip()
        else (root / "EVIDENCE" / f"cost_block_breakdown_{now_utc.strftime('%Y%m%dT%H%M%SZ')}.json").resolve()
    )
    out_json.parent.mkdir(parents=True, exist_ok=True)
    report = build_block_breakdown(root=root, start_utc=start_utc, local_tz=local_tz)
    out_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"COST_BLOCK_BREAKDOWN report={out_json}")
    print(
        "COST_BLOCK_BREAKDOWN summary "
        f"start_utc={report['start_utc']} "
        f"block_cost={report['entry_block_cost']['count']} "
        f"block_basket={report['entry_block_basket']['count']} "
        f"block_micro={report['entry_shadow_block_cost_microstructure']['count']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
