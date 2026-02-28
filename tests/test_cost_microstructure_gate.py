from __future__ import annotations

from BIN.cost_microstructure_gate import (
    CostMicrostructureGateConfig,
    CostMicrostructureGateInput,
    evaluate_cost_microstructure_gate,
)


def _base_input(**overrides):
    data = {
        "group": "FX",
        "symbol": "USDJPY.pro",
        "spread_points": 12.0,
        "spread_caution_points": 22.0,
        "spread_block_points": 30.0,
        "tick_age_sec": 1.0,
        "max_tick_age_sec": 6.0,
        "tick_gap_sec": 1.5,
        "gap_block_sec": 20.0,
        "price_jump_points": 10.0,
        "jump_block_points": 80.0,
        "ask_lt_bid": False,
        "cost_estimation_quality": "DIRECT",
        "cost_feasibility_shadow": True,
        "target_move_price": 0.0012,
        "estimated_round_trip_cost_price": 0.0005,
    }
    data.update(overrides)
    return CostMicrostructureGateInput(**data)


def test_disabled_gate_allows() -> None:
    cfg = CostMicrostructureGateConfig(
        enabled=False,
        mode="GATE_ENFORCE",
        block_on_missing_snapshot=True,
        block_on_unknown_quality=True,
        min_target_to_cost_ratio=1.1,
    )
    out = evaluate_cost_microstructure_gate(cfg, _base_input(spread_points=None, tick_age_sec=None))
    assert out["cost_allow_trade"] is True
    assert out["reason_code"] == "CMG_DISABLED"


def test_snapshot_missing_blocks() -> None:
    cfg = CostMicrostructureGateConfig(
        enabled=True,
        mode="GATE_ENFORCE",
        block_on_missing_snapshot=True,
        block_on_unknown_quality=True,
        min_target_to_cost_ratio=1.1,
    )
    out = evaluate_cost_microstructure_gate(cfg, _base_input(spread_points=None, tick_age_sec=None))
    assert out["cost_allow_trade"] is False
    assert out["reason_code"] == "CMG_SNAPSHOT_MISSING"


def test_ask_bid_inversion_blocks() -> None:
    cfg = CostMicrostructureGateConfig(
        enabled=True,
        mode="GATE_ENFORCE",
        block_on_missing_snapshot=True,
        block_on_unknown_quality=True,
        min_target_to_cost_ratio=1.1,
    )
    out = evaluate_cost_microstructure_gate(cfg, _base_input(ask_lt_bid=True))
    assert out["cost_allow_trade"] is False
    assert out["reason_code"] == "CMG_ASK_LT_BID"


def test_cost_ratio_low_blocks() -> None:
    cfg = CostMicrostructureGateConfig(
        enabled=True,
        mode="GATE_ENFORCE",
        block_on_missing_snapshot=True,
        block_on_unknown_quality=True,
        min_target_to_cost_ratio=1.2,
    )
    out = evaluate_cost_microstructure_gate(
        cfg,
        _base_input(target_move_price=0.0003, estimated_round_trip_cost_price=0.0005),
    )
    assert out["cost_allow_trade"] is False
    assert out["reason_code"] == "CMG_COST_RATIO_LOW"


def test_caution_state_keeps_allow() -> None:
    cfg = CostMicrostructureGateConfig(
        enabled=True,
        mode="GATE_ENFORCE",
        block_on_missing_snapshot=True,
        block_on_unknown_quality=True,
        min_target_to_cost_ratio=1.1,
    )
    out = evaluate_cost_microstructure_gate(cfg, _base_input(spread_points=24.0))
    assert out["cost_allow_trade"] is True
    assert out["reason_code"] == "CMG_CAUTION"
    assert out["cost_grade"] in {"FAIR", "GOOD", "POOR"}

