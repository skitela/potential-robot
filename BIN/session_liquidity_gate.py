from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Optional


_VALID_MODES = {"SHADOW_ONLY", "GATE_ENFORCE", "DISABLED"}


def _norm_mode(raw: Any) -> str:
    mode = str(raw or "SHADOW_ONLY").strip().upper()
    return mode if mode in _VALID_MODES else "SHADOW_ONLY"


@dataclass(frozen=True)
class SessionLiquidityGateConfig:
    enabled: bool
    mode: str
    block_on_missing_snapshot: bool


@dataclass(frozen=True)
class SessionLiquidityGateInput:
    group: str
    symbol: str
    trade_window_phase: str
    trade_window_id: str
    trade_window_group: str
    strict_group_routing: bool
    spread_points: Optional[float]
    tick_age_sec: Optional[float]
    max_tick_age_sec: float
    spread_caution_points: float
    spread_block_points: float


def evaluate_session_liquidity_gate(
    cfg: SessionLiquidityGateConfig, inp: SessionLiquidityGateInput
) -> Dict[str, Any]:
    mode = _norm_mode(cfg.mode)
    if not bool(cfg.enabled) or mode == "DISABLED":
        return {
            "allow_trade": True,
            "gate_state": "ALLOW",
            "session_state": "DISABLED",
            "liquidity_grade": "UNKNOWN",
            "reason_code": "SLG_DISABLED",
            "risk_budget_hint": 1.0,
            "mode": mode,
        }

    phase = str(inp.trade_window_phase or "UNKNOWN").strip().upper()
    window_id = str(inp.trade_window_id or "NONE").strip() or "NONE"
    session_state = f"{phase}:{window_id}"
    grp = str(inp.group or "").strip().upper()
    tw_grp = str(inp.trade_window_group or "").strip().upper()
    spread = inp.spread_points
    tick_age = inp.tick_age_sec

    if phase == "OFF":
        return {
            "allow_trade": False,
            "gate_state": "BLOCK",
            "session_state": session_state,
            "liquidity_grade": "UNKNOWN",
            "reason_code": "SLG_WINDOW_OFF",
            "risk_budget_hint": 0.0,
            "mode": mode,
        }
    if phase == "CLOSEOUT":
        return {
            "allow_trade": False,
            "gate_state": "BLOCK",
            "session_state": session_state,
            "liquidity_grade": "UNKNOWN",
            "reason_code": "SLG_WINDOW_CLOSEOUT",
            "risk_budget_hint": 0.0,
            "mode": mode,
        }
    if bool(inp.strict_group_routing) and tw_grp and grp and tw_grp != grp:
        return {
            "allow_trade": False,
            "gate_state": "BLOCK",
            "session_state": session_state,
            "liquidity_grade": "UNKNOWN",
            "reason_code": "SLG_WINDOW_GROUP_MISMATCH",
            "risk_budget_hint": 0.0,
            "mode": mode,
        }
    if (spread is None or tick_age is None) and bool(cfg.block_on_missing_snapshot):
        return {
            "allow_trade": False,
            "gate_state": "BLOCK",
            "session_state": session_state,
            "liquidity_grade": "UNKNOWN",
            "reason_code": "SLG_SNAPSHOT_MISSING",
            "risk_budget_hint": 0.0,
            "mode": mode,
        }
    if tick_age is not None and float(tick_age) > float(max(0.1, inp.max_tick_age_sec)):
        return {
            "allow_trade": False,
            "gate_state": "BLOCK",
            "session_state": session_state,
            "liquidity_grade": "POOR",
            "reason_code": "SLG_TICK_STALE",
            "risk_budget_hint": 0.0,
            "mode": mode,
        }

    spread_block = float(max(0.0, inp.spread_block_points))
    spread_caution = float(max(0.0, min(spread_block, inp.spread_caution_points)))
    if spread is not None and spread_block > 0.0 and float(spread) > spread_block:
        return {
            "allow_trade": False,
            "gate_state": "BLOCK",
            "session_state": session_state,
            "liquidity_grade": "POOR",
            "reason_code": "SLG_SPREAD_BLOCK",
            "risk_budget_hint": 0.0,
            "mode": mode,
        }
    if spread is not None and spread_caution > 0.0 and float(spread) > spread_caution:
        return {
            "allow_trade": True,
            "gate_state": "CAUTION",
            "session_state": session_state,
            "liquidity_grade": "FAIR",
            "reason_code": "SLG_SPREAD_CAUTION",
            "risk_budget_hint": 0.6,
            "mode": mode,
        }

    return {
        "allow_trade": True,
        "gate_state": "ALLOW",
        "session_state": session_state,
        "liquidity_grade": ("GOOD" if spread is not None and tick_age is not None else "UNKNOWN"),
        "reason_code": "SLG_OK",
        "risk_budget_hint": 1.0,
        "mode": mode,
    }
