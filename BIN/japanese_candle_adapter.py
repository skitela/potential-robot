from __future__ import annotations

from dataclasses import dataclass
from typing import Any

_VALID_MODES = {"SHADOW_ONLY", "ADVISORY_SCORE", "DISABLED"}


def _norm_mode(raw: Any) -> str:
    mode = str(raw or "SHADOW_ONLY").strip().upper()
    return mode if mode in _VALID_MODES else "SHADOW_ONLY"


@dataclass(frozen=True)
class JapaneseCandleAdapterConfig:
    enabled: bool
    mode: str
    min_body_to_range: float
    pin_wick_ratio_min: float


@dataclass(frozen=True)
class JapaneseCandleInput:
    signal: str
    trend_h4: str
    regime: str
    open_price: float
    high_price: float
    low_price: float
    close_price: float
    prev_open: float
    prev_high: float
    prev_low: float
    prev_close: float


def _safe_ratio(num: float, den: float) -> float:
    if den <= 0.0:
        return 0.0
    return float(num / den)


def evaluate_japanese_candle_adapter(
    cfg: JapaneseCandleAdapterConfig, inp: JapaneseCandleInput
) -> dict[str, Any]:
    mode = _norm_mode(cfg.mode)
    if not bool(cfg.enabled) or mode == "DISABLED":
        return {
            "ready": False,
            "candle_bias": "NONE",
            "candle_score_long": 0.0,
            "candle_score_short": 0.0,
            "candle_quality_grade": "UNKNOWN",
            "candle_patterns": [],
            "no_trade_hint": False,
            "reason_code": "CANDLE_ADAPTER_DISABLED",
            "mode": mode,
        }

    o = float(inp.open_price)
    h = float(inp.high_price)
    low = float(inp.low_price)
    c = float(inp.close_price)
    po = float(inp.prev_open)
    pc = float(inp.prev_close)

    rng = max(0.0, h - low)
    body = abs(c - o)
    min_body = float(max(0.0, cfg.min_body_to_range))
    pin_ratio_min = float(max(0.1, cfg.pin_wick_ratio_min))
    if rng <= 0.0:
        return {
            "ready": False,
            "candle_bias": "NONE",
            "candle_score_long": 0.0,
            "candle_score_short": 0.0,
            "candle_quality_grade": "UNKNOWN",
            "candle_patterns": [],
            "no_trade_hint": False,
            "reason_code": "CANDLE_RANGE_ZERO",
            "mode": mode,
        }

    upper_wick = max(0.0, h - max(o, c))
    lower_wick = max(0.0, min(o, c) - low)
    body_to_range = _safe_ratio(body, rng)
    long_score = 0.0
    short_score = 0.0
    patterns: list[str] = []

    bullish_engulf = (
        (c > o)
        and (pc < po)
        and (o <= pc)
        and (c >= po)
        and (body_to_range >= min_body)
    )
    bearish_engulf = (
        (c < o)
        and (pc > po)
        and (o >= pc)
        and (c <= po)
        and (body_to_range >= min_body)
    )
    if bullish_engulf:
        long_score += 0.65
        patterns.append("BULLISH_ENGULFING")
    if bearish_engulf:
        short_score += 0.65
        patterns.append("BEARISH_ENGULFING")

    bullish_pin = (
        lower_wick > 0.0
        and _safe_ratio(lower_wick, max(body, 1e-12)) >= pin_ratio_min
        and c >= o
    )
    bearish_pin = (
        upper_wick > 0.0
        and _safe_ratio(upper_wick, max(body, 1e-12)) >= pin_ratio_min
        and c <= o
    )
    if bullish_pin:
        long_score += 0.35
        patterns.append("BULLISH_PIN_REJECTION")
    if bearish_pin:
        short_score += 0.35
        patterns.append("BEARISH_PIN_REJECTION")

    if body_to_range >= min_body and c > o and c > pc:
        long_score += 0.15
        patterns.append("BULLISH_BODY_MOMENTUM")
    if body_to_range >= min_body and c < o and c < pc:
        short_score += 0.15
        patterns.append("BEARISH_BODY_MOMENTUM")

    long_score = float(max(0.0, min(1.0, long_score)))
    short_score = float(max(0.0, min(1.0, short_score)))
    bias = "NONE"
    if long_score > short_score:
        bias = "UP"
    elif short_score > long_score:
        bias = "DOWN"

    intended = str(inp.signal or "").strip().upper()
    conflict = bool(
        (intended == "BUY" and bias == "DOWN")
        or (intended == "SELL" and bias == "UP")
    )
    max_score = max(long_score, short_score)
    quality = "POOR"
    if max_score >= 0.70:
        quality = "GOOD"
    elif max_score >= 0.35:
        quality = "FAIR"

    reason = "CANDLE_NEUTRAL"
    if conflict:
        reason = "CANDLE_CONFLICT"
    elif bias == "UP":
        reason = "CANDLE_BULLISH"
    elif bias == "DOWN":
        reason = "CANDLE_BEARISH"

    return {
        "ready": True,
        "candle_bias": bias,
        "candle_score_long": long_score,
        "candle_score_short": short_score,
        "candle_quality_grade": quality,
        "candle_patterns": patterns,
        "no_trade_hint": conflict,
        "reason_code": reason,
        "mode": mode,
    }
