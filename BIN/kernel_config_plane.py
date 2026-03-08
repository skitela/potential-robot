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
KERNEL_CONFIG_HASH_METHOD = "sha256_sig_v1"
KERNEL_CONFIG_HASH_SCOPE = "kernel_core_v1"

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


def sha256_hex(value: str) -> str:
    return hashlib.sha256(str(value).encode("utf-8")).hexdigest()


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


def _sig_bool(value: Any) -> str:
    return "1" if bool(value) else "0"


def _sig_float(value: Any) -> str:
    try:
        v = float(value)
    except Exception:
        v = 0.0
    return f"{v:.6f}"


def _symbol_signature(row: Dict[str, Any]) -> str:
    return (
        f"symbol={str(row.get('symbol') or '')};"
        f"group={str(row.get('group') or '')};"
        f"entry_allowed={_sig_bool(row.get('entry_allowed'))};"
        f"close_only={_sig_bool(row.get('close_only'))};"
        f"halt={_sig_bool(row.get('halt'))};"
        f"reason={str(row.get('reason') or '')};"
        f"spread_cap_points={_sig_float(row.get('spread_cap_points'))};"
        f"max_latency_ms={_sig_float(row.get('max_latency_ms'))};"
        f"min_tick_rate_1s={int(row.get('min_tick_rate_1s') or 0)};"
        f"min_liquidity_score={_sig_float(row.get('min_liquidity_score'))};"
        f"min_tradeability_score={_sig_float(row.get('min_tradeability_score'))};"
        f"min_setup_quality_score={_sig_float(row.get('min_setup_quality_score'))}"
    )


def build_kernel_config_signature(
    *,
    schema_version: str,
    generated_at_utc: str,
    policy_version: str,
    symbols: Iterable[Dict[str, Any]],
) -> str:
    rows = [str(_symbol_signature(dict(row))) for row in symbols]
    parts = [
        f"schema_version={str(schema_version or '')}",
        f"generated_at_utc={str(generated_at_utc or '')}",
        f"policy_version={str(policy_version or '')}",
        f"symbols_n={len(rows)}",
    ]
    parts.extend(rows)
    return "\n".join(parts)


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
        "hash_method": KERNEL_CONFIG_HASH_METHOD,
        "hash_scope": KERNEL_CONFIG_HASH_SCOPE,
        "config_hash": "",
        "symbols": rows,
        "meta": dict(meta or {}),
    }
    signature = build_kernel_config_signature(
        schema_version=str(payload.get("schema_version") or ""),
        generated_at_utc=str(payload.get("generated_at_utc") or ""),
        policy_version=str(payload.get("policy_version") or ""),
        symbols=rows,
    )
    payload["config_hash"] = sha256_hex(signature)
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
