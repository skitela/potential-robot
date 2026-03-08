from __future__ import annotations

import copy
import datetime as dt
import hashlib
import json
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Optional

UTC = dt.timezone.utc

KERNEL_CONFIG_SCHEMA_VERSION = "kernel_config_v1"
KERNEL_CONFIG_POLICY_VERSION = "kernel.shadow.v1"

RISK_LOCKED_KEYS = {
    "risk_per_trade",
    "risk_per_trade_pct",
    "max_daily_drawdown",
    "max_daily_drawdown_pct",
    "max_weekly_drawdown",
    "max_weekly_drawdown_pct",
    "max_open_positions",
    "max_global_exposure",
    "max_series_loss",
    "capital_risk_mode",
    "account_risk_mode",
    "lot_sizing_mode",
    "fixed_lot",
    "kelly_fraction",
    "max_loss_account_ccy_day",
    "max_loss_account_ccy_week",
}

ALLOWED_SYMBOL_FIELDS = {
    "symbol",
    "entry_allowed",
    "close_only",
    "halt",
    "reason",
    "group",
    "spread_cap_points",
    "max_latency_ms",
    "min_tick_rate_1s",
    "min_liquidity_score",
    "min_tradeability_score",
    "min_setup_quality_score",
}


def iso_utc(dt_value: Optional[dt.datetime] = None) -> str:
    ref = (dt_value or dt.datetime.now(UTC)).astimezone(UTC)
    return ref.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def canonical_json_dumps(payload: Dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def compute_hash_excluding_field(payload: Dict[str, Any], field_name: str = "config_hash") -> str:
    obj = copy.deepcopy(payload)
    obj.pop(field_name, None)
    raw = canonical_json_dumps(obj)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _clamp_float(raw: Any, default: float, low: float, high: float) -> float:
    try:
        value = float(raw)
    except Exception:
        value = float(default)
    return float(max(low, min(high, value)))


def _clamp_int(raw: Any, default: int, low: int, high: int) -> int:
    try:
        value = int(raw)
    except Exception:
        value = int(default)
    return int(max(low, min(high, value)))


def sanitize_symbol_entry(row: Dict[str, Any]) -> Dict[str, Any]:
    clean: Dict[str, Any] = {}
    symbol = str(row.get("symbol") or "").strip()
    if not symbol:
        raise ValueError("kernel_config_symbol_missing")

    clean["symbol"] = symbol
    clean["entry_allowed"] = bool(row.get("entry_allowed", True))
    clean["close_only"] = bool(row.get("close_only", False))
    clean["halt"] = bool(row.get("halt", False))
    clean["reason"] = str(row.get("reason") or "NONE").strip().upper() or "NONE"
    clean["group"] = str(row.get("group") or "").strip().upper()
    clean["spread_cap_points"] = _clamp_float(row.get("spread_cap_points"), 0.0, 0.0, 10000.0)
    clean["max_latency_ms"] = _clamp_float(row.get("max_latency_ms"), 0.0, 0.0, 30000.0)
    clean["min_tick_rate_1s"] = _clamp_int(row.get("min_tick_rate_1s"), 0, 0, 100000)
    clean["min_liquidity_score"] = _clamp_float(row.get("min_liquidity_score"), 0.0, 0.0, 1.0)
    clean["min_tradeability_score"] = _clamp_float(row.get("min_tradeability_score"), 0.0, 0.0, 1.0)
    clean["min_setup_quality_score"] = _clamp_float(row.get("min_setup_quality_score"), 0.0, 0.0, 1.0)

    # Twarda ochrona przed przypadkowym przepchnięciem kluczy ryzyka do kernela runtime.
    for key in list(row.keys()):
        if str(key) in RISK_LOCKED_KEYS:
            raise ValueError(f"kernel_config_risk_locked:{key}")

    for key in list(clean.keys()):
        if key not in ALLOWED_SYMBOL_FIELDS:
            clean.pop(key, None)

    return clean


def build_kernel_config_payload(
    symbol_rows: Iterable[Dict[str, Any]],
    *,
    policy_version: str = KERNEL_CONFIG_POLICY_VERSION,
    generated_at_utc: Optional[str] = None,
    meta: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    rows: List[Dict[str, Any]] = []
    seen: set[str] = set()
    for raw_row in symbol_rows:
        if not isinstance(raw_row, dict):
            continue
        clean = sanitize_symbol_entry(raw_row)
        sym_u = str(clean["symbol"]).upper()
        if sym_u in seen:
            continue
        seen.add(sym_u)
        rows.append(clean)

    rows.sort(key=lambda item: str(item.get("symbol") or "").upper())
    payload: Dict[str, Any] = {
        "schema_version": KERNEL_CONFIG_SCHEMA_VERSION,
        "generated_at_utc": str(generated_at_utc or iso_utc()),
        "policy_version": str(policy_version or KERNEL_CONFIG_POLICY_VERSION),
        "config_hash": "",
        "symbols": rows,
        "meta": dict(meta or {}),
    }
    payload["config_hash"] = compute_hash_excluding_field(payload, "config_hash")
    return payload


def write_kernel_config(
    path: Path,
    payload: Dict[str, Any],
    *,
    atomic_write_json_func: Callable[[Path, Dict[str, Any]], None],
) -> str:
    path = Path(path)
    atomic_write_json_func(path, payload)
    return str(payload.get("config_hash") or "")
