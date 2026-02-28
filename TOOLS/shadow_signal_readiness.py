from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any

UTC = dt.UTC


def _parse_ts_utc(raw: str) -> dt.datetime | None:
    txt = str(raw or "").strip()
    if not txt:
        return None
    try:
        return dt.datetime.fromisoformat(txt.replace("Z", "+00:00")).astimezone(UTC)
    except Exception:
        return None


def _iter_jsonl(path: Path) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    if not path.exists():
        return out
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if isinstance(obj, dict):
            out.append(obj)
    return out


def _tail_lines(path: Path, n: int = 100000) -> list[str]:
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    return lines[-int(max(1, n)) :]


def build_report(root: Path, hours: int) -> dict[str, Any]:
    now = dt.datetime.now(tz=UTC)
    start = now - dt.timedelta(hours=max(1, int(hours)))

    telemetry_path = root / "LOGS" / "execution_telemetry_v2.jsonl"
    audit_path = root / "LOGS" / "audit_trail.jsonl"
    app_log_path = root / "LOGS" / "safetybot.log"

    telemetry = _iter_jsonl(telemetry_path)
    audit = _iter_jsonl(audit_path)
    app_lines = _tail_lines(app_log_path, 120000)

    gate_event_counts: dict[str, int] = {}
    for rec in telemetry:
        ts = _parse_ts_utc(str(rec.get("ts_utc") or ""))
        if ts is None or ts < start:
            continue
        evt = str(rec.get("event_type") or "").strip().upper()
        if "SESSION_LIQUIDITY" in evt or "COST_MICROSTRUCTURE" in evt:
            gate_event_counts[evt] = int(gate_event_counts.get(evt, 0)) + 1

    candle_lines = 0
    candle_conflict = 0
    for ln in app_lines:
        if "CANDLE_ADAPTER" not in ln:
            continue
        # App log may include local timestamps; use tail-window proxy.
        candle_lines += 1
        if "reason=CANDLE_CONFLICT" in ln:
            candle_conflict += 1

    ipc_failure_events = {
        "COMMAND_TIMEOUT",
        "COMMAND_SEND_TIMEOUT",
        "COMMAND_FAILED",
        "REPLY_INVALID_JSON",
        "REPLY_REQUEST_HASH_MISMATCH",
        "REPLY_RESPONSE_HASH_MISMATCH",
    }
    ipc_failures = 0
    for rec in audit:
        ts = _parse_ts_utc(str(rec.get("timestamp_utc") or ""))
        if ts is None or ts < start:
            continue
        evt = str(rec.get("event_type_norm") or rec.get("event_type") or "").strip().upper()
        if evt in ipc_failure_events:
            ipc_failures += 1

    return {
        "schema_version": "1.0",
        "generated_at_utc": now.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "window_utc": {
            "start": start.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "end": now.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "hours": int(hours),
        },
        "sources": {
            "execution_telemetry": str(telemetry_path),
            "audit_trail": str(audit_path),
            "safetybot_log": str(app_log_path),
        },
        "shadow_gate_events": gate_event_counts,
        "candle_adapter_log_lines": int(candle_lines),
        "candle_conflict_lines": int(candle_conflict),
        "ipc_failure_events": int(ipc_failures),
        "notes": [
            "Tool is read-only. No runtime mutation.",
            "Candle lines are approximated from log tail; promote to structured telemetry if stricter windowing is required.",
        ],
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Shadow readiness summary for gate/candle modules.")
    ap.add_argument("--root", default="C:\\OANDA_MT5_SYSTEM", help="Runtime root path.")
    ap.add_argument("--hours", type=int, default=24, help="Lookback window in hours.")
    ap.add_argument("--out", default="", help="Optional output JSON path.")
    args = ap.parse_args()

    root = Path(args.root)
    report = build_report(root, int(args.hours))
    payload = json.dumps(report, ensure_ascii=False, indent=2)
    print(payload)
    if str(args.out or "").strip():
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(payload + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
