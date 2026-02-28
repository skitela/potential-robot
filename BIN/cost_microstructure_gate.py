from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Optional


_VALID_MODES = {"SHADOW_ONLY", "GATE_ENFORCE", "DISABLED"}


def _norm_mode(raw: Any) -> str:
    mode = str(raw or "SHADOW_ONLY").strip().upper()
    return mode if mode in _VALID_MODES else "SHADOW_ONLY"


def _cost_grade_from_score(score: float) -> str:
    if score >= 0.80:
        return "GOOD"
    if score >= 0.50:
        return "FAIR"
    return "POOR"


def _risk_from_score(score: float) -> str:
    if score >= 0.80:
        return "LOW"
    if score >= 0.50:
        return "MED"
    return "HIGH"


@dataclass(frozen=True)
class CostMicrostructureGateConfig:
    enabled: bool
    mode: str
    block_on_missing_snapshot: bool
    block_on_unknown_quality: bool
    min_target_to_cost_ratio: float


@dataclass(frozen=True)
class CostMicrostructureGateInput:
    group: str
    symbol: str
    spread_points: Optional[float]
    spread_caution_points: float
    spread_block_points: float
    tick_age_sec: Optional[float]
    max_tick_age_sec: float
    tick_gap_sec: Optional[float]
    gap_block_sec: float
    price_jump_points: Optional[float]
    jump_block_points: float
    ask_lt_bid: bool
    cost_estimation_quality: str
    cost_feasibility_shadow: Optional[bool]
    target_move_price: Optional[float]
    estimated_round_trip_cost_price: Optional[float]


def evaluate_cost_microstructure_gate(
    cfg: CostMicrostructureGateConfig, inp: CostMicrostructureGateInput
) -> Dict[str, Any]:
    mode = _norm_mode(cfg.mode)
    if not bool(cfg.enabled) or mode == "DISABLED":
        return {
            "cost_allow_trade": True,
            "cost_grade": "UNKNOWN",
            "microstructure_quality_score": 1.0,
            "estimated_execution_risk": "UNKNOWN",
            "hard_block_flag": False,
            "reason_code": "CMG_DISABLED",
            "mode": mode,
        }

    if (inp.spread_points is None or inp.tick_age_sec is None) and bool(cfg.block_on_missing_snapshot):
        return {
            "cost_allow_trade": False,
            "cost_grade": "UNKNOWN",
            "microstructure_quality_score": 0.0,
            "estimated_execution_risk": "HIGH",
            "hard_block_flag": True,
            "reason_code": "CMG_SNAPSHOT_MISSING",
            "mode": mode,
        }
    if bool(inp.ask_lt_bid):
        return {
            "cost_allow_trade": False,
            "cost_grade": "POOR",
            "microstructure_quality_score": 0.0,
            "estimated_execution_risk": "HIGH",
            "hard_block_flag": True,
            "reason_code": "CMG_ASK_LT_BID",
            "mode": mode,
        }
    if inp.tick_age_sec is not None and float(inp.tick_age_sec) > float(max(0.1, inp.max_tick_age_sec)):
        return {
            "cost_allow_trade": False,
            "cost_grade": "POOR",
            "microstructure_quality_score": 0.0,
            "estimated_execution_risk": "HIGH",
            "hard_block_flag": True,
            "reason_code": "CMG_TICK_STALE",
            "mode": mode,
        }
    if inp.tick_gap_sec is not None and float(inp.tick_gap_sec) > float(max(0.1, inp.gap_block_sec)):
        return {
            "cost_allow_trade": False,
            "cost_grade": "POOR",
            "microstructure_quality_score": 0.0,
            "estimated_execution_risk": "HIGH",
            "hard_block_flag": True,
            "reason_code": "CMG_TICK_GAP",
            "mode": mode,
        }
    if inp.price_jump_points is not None and float(inp.price_jump_points) > float(max(0.0, inp.jump_block_points)):
        return {
            "cost_allow_trade": False,
            "cost_grade": "POOR",
            "microstructure_quality_score": 0.0,
            "estimated_execution_risk": "HIGH",
            "hard_block_flag": True,
            "reason_code": "CMG_PRICE_JUMP",
            "mode": mode,
        }
    if inp.spread_points is not None and float(inp.spread_points) > float(max(0.0, inp.spread_block_points)):
        return {
            "cost_allow_trade": False,
            "cost_grade": "POOR",
            "microstructure_quality_score": 0.0,
            "estimated_execution_risk": "HIGH",
            "hard_block_flag": True,
            "reason_code": "CMG_SPREAD_BLOCK",
            "mode": mode,
        }

    quality = str(inp.cost_estimation_quality or "UNKNOWN").strip().upper()
    cost_unknown = quality in {"UNKNOWN", "HEURISTIC", "PARTIAL"}
    if bool(cfg.block_on_unknown_quality) and cost_unknown:
        return {
            "cost_allow_trade": False,
            "cost_grade": "POOR",
            "microstructure_quality_score": 0.0,
            "estimated_execution_risk": "HIGH",
            "hard_block_flag": True,
            "reason_code": "CMG_COST_QUALITY_UNKNOWN",
            "mode": mode,
        }
    if inp.cost_feasibility_shadow is False:
        return {
            "cost_allow_trade": False,
            "cost_grade": "POOR",
            "microstructure_quality_score": 0.0,
            "estimated_execution_risk": "HIGH",
            "hard_block_flag": True,
            "reason_code": "CMG_COST_NOT_FEASIBLE",
            "mode": mode,
        }

    ratio = None
    try:
        if (
            inp.target_move_price is not None
            and inp.estimated_round_trip_cost_price is not None
            and float(inp.estimated_round_trip_cost_price) > 0.0
        ):
            ratio = float(inp.target_move_price) / float(inp.estimated_round_trip_cost_price)
    except Exception:
        ratio = None
    if ratio is not None and float(ratio) < float(max(0.0, cfg.min_target_to_cost_ratio)):
        return {
            "cost_allow_trade": False,
            "cost_grade": "POOR",
            "microstructure_quality_score": 0.0,
            "estimated_execution_risk": "HIGH",
            "hard_block_flag": True,
            "reason_code": "CMG_COST_RATIO_LOW",
            "mode": mode,
            "cost_target_to_estimated_ratio": float(ratio),
            "cost_ratio_min_required": float(cfg.min_target_to_cost_ratio),
        }

    score = 1.0
    caution = False
    if inp.spread_points is not None:
        spread = float(max(0.0, inp.spread_points))
        caution_thr = float(max(0.0, inp.spread_caution_points))
        block_thr = float(max(caution_thr, inp.spread_block_points))
        if block_thr > 0.0:
            score -= min(0.50, spread / block_thr * 0.45)
        if caution_thr > 0.0 and spread > caution_thr:
            caution = True
    if inp.tick_age_sec is not None:
        score -= min(0.20, float(max(0.0, inp.tick_age_sec)) / float(max(0.1, inp.max_tick_age_sec)) * 0.20)
    if inp.price_jump_points is not None and inp.jump_block_points > 0.0:
        jump_ratio = float(max(0.0, inp.price_jump_points)) / float(max(0.1, inp.jump_block_points))
        score -= min(0.25, jump_ratio * 0.25)
    score = float(max(0.0, min(1.0, score)))

    return {
        "cost_allow_trade": True,
        "cost_grade": _cost_grade_from_score(score),
        "microstructure_quality_score": score,
        "estimated_execution_risk": _risk_from_score(score),
        "hard_block_flag": False,
        "reason_code": ("CMG_CAUTION" if caution else "CMG_OK"),
        "mode": mode,
        "cost_target_to_estimated_ratio": (None if ratio is None else float(ratio)),
        "cost_ratio_min_required": float(cfg.min_target_to_cost_ratio),
    }
