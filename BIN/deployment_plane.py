from __future__ import annotations

import datetime as dt
from typing import Any, Callable, Dict, Iterable, List, Optional, Sequence, Tuple

from kernel_config_plane import KERNEL_CONFIG_POLICY_VERSION, build_kernel_config_payload


UTC = dt.timezone.utc


def build_kernel_symbol_rows(
    universe: Sequence[Tuple[str, str, str]],
    group_risk: Dict[str, Dict[str, Any]],
    *,
    black_swan_action: str,
    black_swan_reason: str,
    black_swan_blocks: bool,
    group_risk_fallback: Callable[..., Dict[str, Any]],
    spread_cap_resolver: Callable[[str, str], float],
    group_float_resolver: Callable[[str, str, float, str], float],
    group_int_resolver: Callable[[str, str, int, str], int],
    canonical_symbol_func: Callable[[str], str],
    group_key_func: Callable[[str], str],
    now_dt: Optional[dt.datetime] = None,
) -> List[Dict[str, Any]]:
    ref = (now_dt or dt.datetime.now(UTC)).astimezone(UTC)
    rows: List[Dict[str, Any]] = []
    seen: set[str] = set()

    bs_action = str(black_swan_action or "ALLOW").strip().upper()
    bs_reason = str(black_swan_reason or "NONE").strip().upper() or "NONE"
    bs_halt = bool(bs_action in {"FORCE_FLAT", "HALT"})
    bs_close_only = bool(bs_action in {"CLOSE_ONLY", "FORCE_FLAT"})

    for _raw, sym, grp in list(universe or []):
        sym_canon = str(sym or "").strip()
        if not sym_canon:
            continue
        sym_key = canonical_symbol_func(sym_canon)
        if sym_key in seen:
            continue
        seen.add(sym_key)

        grp_u = group_key_func(grp)
        rs = dict(group_risk.get(grp_u) or group_risk_fallback(grp_u, now_dt=ref))
        entry_allowed = bool(rs.get("entry_allowed", True))
        reason = str(rs.get("reason", "NONE") or "NONE").strip().upper() or "NONE"
        close_only = bool(not entry_allowed)
        halt = False

        if black_swan_blocks:
            entry_allowed = False
            close_only = True
            if bs_reason == "NONE":
                bs_reason = "BLACK_SWAN_GUARD"
            reason = f"BLACK_SWAN_{bs_reason}"
        if bs_close_only:
            close_only = True
        if bs_halt:
            halt = True
            close_only = True
            entry_allowed = False

        row = {
            "symbol": str(sym_canon),
            "group": str(grp_u),
            "entry_allowed": bool(entry_allowed),
            "close_only": bool(close_only),
            "halt": bool(halt),
            "reason": str(reason),
            "spread_cap_points": float(max(0.0, spread_cap_resolver(sym_canon, grp_u))),
            "max_latency_ms": float(max(0.0, group_float_resolver(grp_u, "max_latency_ms", 1200.0, sym_canon))),
            "min_tick_rate_1s": int(max(0, group_int_resolver(grp_u, "min_tick_rate_1s", 0, sym_canon))),
            "min_liquidity_score": float(
                max(0.0, min(1.0, group_float_resolver(grp_u, "min_liquidity_score", 0.0, sym_canon)))
            ),
            "min_tradeability_score": float(
                max(0.0, min(1.0, group_float_resolver(grp_u, "min_tradeability_score", 0.0, sym_canon)))
            ),
            "min_setup_quality_score": float(
                max(0.0, min(1.0, group_float_resolver(grp_u, "min_setup_quality_score", 0.0, sym_canon)))
            ),
        }
        rows.append(row)
    return rows


def build_kernel_runtime_payload(
    universe: Sequence[Tuple[str, str, str]],
    group_risk: Dict[str, Dict[str, Any]],
    *,
    black_swan_action: str,
    black_swan_reason: str,
    black_swan_blocks: bool,
    group_risk_fallback: Callable[..., Dict[str, Any]],
    spread_cap_resolver: Callable[[str, str], float],
    group_float_resolver: Callable[[str, str, float, str], float],
    group_int_resolver: Callable[[str, str, int, str], int],
    canonical_symbol_func: Callable[[str], str],
    group_key_func: Callable[[str], str],
    generated_at_utc: str,
    meta: Dict[str, Any],
    policy_version: str = KERNEL_CONFIG_POLICY_VERSION,
) -> Dict[str, Any]:
    rows = build_kernel_symbol_rows(
        universe,
        group_risk,
        black_swan_action=black_swan_action,
        black_swan_reason=black_swan_reason,
        black_swan_blocks=black_swan_blocks,
        group_risk_fallback=group_risk_fallback,
        spread_cap_resolver=spread_cap_resolver,
        group_float_resolver=group_float_resolver,
        group_int_resolver=group_int_resolver,
        canonical_symbol_func=canonical_symbol_func,
        group_key_func=group_key_func,
        now_dt=dt.datetime.fromisoformat(generated_at_utc.replace("Z", "+00:00")),
    )
    return build_kernel_config_payload(
        rows,
        policy_version=policy_version,
        generated_at_utc=generated_at_utc,
        meta=dict(meta or {}),
    )


def build_policy_runtime_payload(
    group_arb: Dict[str, Dict[str, Any]],
    group_risk: Dict[str, Dict[str, Any]],
    *,
    flags: Dict[str, Any],
    ts_utc: str,
    us_overlap_active: bool,
    baseline_groups: Optional[Iterable[str]] = None,
) -> Dict[str, Any]:
    groups_seed = set(baseline_groups or {"FX", "METAL", "INDEX", "CRYPTO", "EQUITY"})
    groups = sorted(set(list(group_arb.keys()) + list(group_risk.keys()) + list(groups_seed)))
    groups_payload: Dict[str, Any] = {}
    for group_name in groups:
        arb_state = dict(group_arb.get(group_name) or {})
        risk_state = dict(group_risk.get(group_name) or {})
        groups_payload[group_name] = {
            "entry_allowed": bool(risk_state.get("entry_allowed", True)),
            "borrow_blocked": bool(risk_state.get("borrow_blocked", False)),
            "priority_factor": float(arb_state.get("priority_factor", risk_state.get("priority_factor", 1.0))),
            "reason": str(risk_state.get("reason", "NONE")),
            "risk_friday": bool(risk_state.get("friday_risk", False)),
            "risk_reopen": bool(risk_state.get("reopen_guard", False)),
            "price_cap": int(arb_state.get("price_cap", 0)),
            "price_used": int(arb_state.get("price_used", 0)),
            "price_borrow": int(arb_state.get("price_borrow", 0)),
            "order_cap": int(arb_state.get("order_cap", 0)),
            "order_used": int(arb_state.get("order_used", 0)),
            "order_borrow": int(arb_state.get("order_borrow", 0)),
            "sys_cap": int(arb_state.get("sys_cap", 0)),
            "sys_used": int(arb_state.get("sys_used", 0)),
            "sys_borrow": int(arb_state.get("sys_borrow", 0)),
        }

    return {
        "schema_version": "1.0",
        "policy_version": "windows_v2",
        "ts_utc": str(ts_utc),
        "flags": dict(flags or {}),
        "us_overlap_active": bool(us_overlap_active),
        "groups": groups_payload,
    }
