from __future__ import annotations

import argparse
import json
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

try:
    import zmq  # type: ignore
except Exception:  # pragma: no cover
    zmq = None


SCHEMA = "oanda.mt5.kernel_shadow_parity_probe.v1"


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


def _default_symbols_from_strategy(root: Path) -> List[str]:
    cfg = _read_json(root / "CONFIG" / "strategy.json")
    out: List[str] = []
    for key in ("symbols_to_trade", "live_canary_allowed_symbol_intents", "asia_wave1_symbol_intents"):
        arr = cfg.get(key)
        if isinstance(arr, list):
            for x in arr:
                s = str(x or "").strip()
                if s and s not in out:
                    out.append(s)
    if not out:
        out = ["EURUSD", "GBPUSD", "USDJPY", "EURJPY"]
    return out[:20]


def _build_probe_command(symbol: str) -> Dict[str, Any]:
    msg_id = str(uuid.uuid4())
    return {
        "action": "TRADE",
        "msg_id": msg_id,
        "command_id": msg_id,
        "request_id": msg_id,
        "schema_version": "1.0",
        "policy_version": "runtime.v1",
        "timestamp_semantics": "UTC",
        "request_ts_utc": _utc_iso_now(),
        # Celowo błędny hash => bezpieczny reject zanim ExecuteTrade.
        "request_hash": "PARITY_PROBE_HASH_MISMATCH",
        "payload": {
            "signal": "BUY",
            "symbol": str(symbol),
            "symbol_raw": str(symbol),
            "symbol_canonical": str(symbol).upper(),
            "volume": 0.0,
            "sl_price": 0.0,
            "tp_price": 0.0,
            "request_price": 0.0,
            "deviation_points": 10,
            "deviation_unit": "points",
            "spread_at_decision": 0.0,
            "spread_unit": "points",
            "spread_provenance": "PARITY_PROBE",
            "estimated_entry_cost_components": {},
            "estimated_round_trip_cost": {},
            "cost_feasibility_shadow": True,
            "net_cost_feasible": True,
            "cost_gate_policy_mode": "SHADOW_ONLY",
            "cost_gate_reason_code": "PARITY_PROBE",
            "magic": 37630,
            "comment": "PARITY_PROBE_NO_EXECUTION",
            "group": "FX",
            "risk_entry_allowed": True,
            "risk_reason": "NONE",
            "risk_friday": False,
            "risk_reopen": False,
            "policy_shadow_mode": True,
        },
    }


def run_probe(
    *,
    symbols: List[str],
    endpoint: str,
    timeout_ms: int,
) -> Dict[str, Any]:
    if zmq is None:
        return {
            "status": "NO_ZMQ",
            "rows": [],
            "errors": ["pyzmq_missing"],
        }

    ctx = zmq.Context.instance()
    sock = ctx.socket(zmq.REQ)
    sock.setsockopt(zmq.RCVTIMEO, int(max(100, timeout_ms)))
    sock.setsockopt(zmq.SNDTIMEO, int(max(100, timeout_ms)))
    sock.setsockopt(zmq.LINGER, 0)
    sock.connect(endpoint)

    rows: List[Dict[str, Any]] = []
    errors: List[str] = []
    try:
        for symbol in symbols:
            cmd = _build_probe_command(symbol)
            item: Dict[str, Any] = {
                "symbol": str(symbol),
                "msg_id": str(cmd["msg_id"]),
                "status": "UNKNOWN",
                "reply_status": "",
                "reply_retcode_str": "",
            }
            try:
                sock.send_string(json.dumps(cmd, ensure_ascii=False, separators=(",", ":")))
                raw = sock.recv_string()
                reply = json.loads(raw)
                item["status"] = "REPLY"
                item["reply_status"] = str(reply.get("status") or "")
                item["reply_retcode_str"] = str(reply.get("retcode_str") or "")
            except Exception as exc:  # pragma: no cover
                item["status"] = "FAILED"
                item["error"] = f"{type(exc).__name__}:{exc}"
                errors.append(str(item["error"]))
            rows.append(item)
    finally:
        try:
            sock.close(0)
        except Exception:
            pass

    ok_rows = sum(1 for r in rows if r.get("status") == "REPLY")
    return {
        "status": "OK" if ok_rows > 0 else "FAILED",
        "rows": rows,
        "ok_rows": int(ok_rows),
        "errors": errors,
    }


def main(argv: Optional[Iterable[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Send safe TRADE probe messages to produce KERNEL_SHADOW_TRADE_PARITY rows.")
    ap.add_argument("--root", default="C:/OANDA_MT5_SYSTEM")
    ap.add_argument("--symbols", default="", help="Comma-separated symbols.")
    ap.add_argument("--endpoint", default="tcp://127.0.0.1:5556")
    ap.add_argument("--timeout-ms", type=int, default=1200)
    ap.add_argument("--out-json", default="")
    args = ap.parse_args(list(argv) if argv is not None else None)

    root = Path(args.root).resolve()
    symbols = [s.strip() for s in str(args.symbols or "").split(",") if s.strip()]
    if not symbols:
        symbols = _default_symbols_from_strategy(root)

    result = run_probe(symbols=symbols, endpoint=str(args.endpoint), timeout_ms=int(args.timeout_ms))
    payload = {
        "schema": SCHEMA,
        "generated_at_utc": _utc_iso_now(),
        "endpoint": str(args.endpoint),
        "timeout_ms": int(args.timeout_ms),
        "symbols": symbols,
        "result": result,
    }

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_json = (
        Path(args.out_json).resolve()
        if str(args.out_json or "").strip()
        else root / "EVIDENCE" / "kernel_shadow" / f"kernel_shadow_parity_probe_{stamp}.json"
    )
    _write_json(out_json, payload)
    _write_json(out_json.parent / "kernel_shadow_parity_probe_latest.json", payload)

    print(
        "KERNEL_SHADOW_PARITY_PROBE_DONE "
        f"status={result.get('status')} ok_rows={result.get('ok_rows', 0)} "
        f"symbols={len(symbols)} out={out_json}"
    )
    return 0 if str(result.get("status")) == "OK" else 2


if __name__ == "__main__":
    raise SystemExit(main())
