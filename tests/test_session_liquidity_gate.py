from __future__ import annotations

from BIN.session_liquidity_gate import (
    SessionLiquidityGateConfig,
    SessionLiquidityGateInput,
    evaluate_session_liquidity_gate,
)


def _base_input(**overrides):
    data = {
        "group": "FX",
        "symbol": "USDJPY.pro",
        "trade_window_phase": "ACTIVE",
        "trade_window_id": "FX_ASIA",
        "trade_window_group": "FX",
        "strict_group_routing": True,
        "spread_points": 12.0,
        "tick_age_sec": 1.0,
        "max_tick_age_sec": 8.0,
        "spread_caution_points": 24.0,
        "spread_block_points": 32.0,
    }
    data.update(overrides)
    return SessionLiquidityGateInput(**data)


def test_disabled_gate_always_allows() -> None:
    cfg = SessionLiquidityGateConfig(enabled=False, mode="GATE_ENFORCE", block_on_missing_snapshot=True)
    out = evaluate_session_liquidity_gate(cfg, _base_input(trade_window_phase="OFF"))
    assert out["allow_trade"] is True
    assert out["reason_code"] == "SLG_DISABLED"


def test_window_off_blocks() -> None:
    cfg = SessionLiquidityGateConfig(enabled=True, mode="GATE_ENFORCE", block_on_missing_snapshot=True)
    out = evaluate_session_liquidity_gate(cfg, _base_input(trade_window_phase="OFF"))
    assert out["allow_trade"] is False
    assert out["reason_code"] == "SLG_WINDOW_OFF"


def test_strict_group_mismatch_blocks() -> None:
    cfg = SessionLiquidityGateConfig(enabled=True, mode="GATE_ENFORCE", block_on_missing_snapshot=True)
    out = evaluate_session_liquidity_gate(cfg, _base_input(trade_window_group="METAL"))
    assert out["allow_trade"] is False
    assert out["reason_code"] == "SLG_WINDOW_GROUP_MISMATCH"


def test_stale_tick_blocks() -> None:
    cfg = SessionLiquidityGateConfig(enabled=True, mode="GATE_ENFORCE", block_on_missing_snapshot=True)
    out = evaluate_session_liquidity_gate(cfg, _base_input(tick_age_sec=15.0, max_tick_age_sec=8.0))
    assert out["allow_trade"] is False
    assert out["reason_code"] == "SLG_TICK_STALE"


def test_spread_caution_keeps_allow() -> None:
    cfg = SessionLiquidityGateConfig(enabled=True, mode="GATE_ENFORCE", block_on_missing_snapshot=True)
    out = evaluate_session_liquidity_gate(cfg, _base_input(spread_points=28.0))
    assert out["allow_trade"] is True
    assert out["gate_state"] == "CAUTION"
    assert out["reason_code"] == "SLG_SPREAD_CAUTION"

