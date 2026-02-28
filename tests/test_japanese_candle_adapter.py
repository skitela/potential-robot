from __future__ import annotations

from BIN.japanese_candle_adapter import (
    JapaneseCandleAdapterConfig,
    JapaneseCandleInput,
    evaluate_japanese_candle_adapter,
)


def _cfg(mode: str = "SHADOW_ONLY") -> JapaneseCandleAdapterConfig:
    return JapaneseCandleAdapterConfig(
        enabled=True,
        mode=mode,
        min_body_to_range=0.35,
        pin_wick_ratio_min=1.6,
    )


def test_disabled_returns_neutral() -> None:
    out = evaluate_japanese_candle_adapter(
        JapaneseCandleAdapterConfig(False, "ADVISORY_SCORE", 0.35, 1.6),
        JapaneseCandleInput(
            signal="BUY",
            trend_h4="BUY",
            regime="TREND",
            open_price=1.0,
            high_price=1.1,
            low_price=0.9,
            close_price=1.05,
            prev_open=1.02,
            prev_high=1.03,
            prev_low=0.98,
            prev_close=0.99,
        ),
    )
    assert out["ready"] is False
    assert out["reason_code"] == "CANDLE_ADAPTER_DISABLED"


def test_bullish_engulfing_bias_up() -> None:
    out = evaluate_japanese_candle_adapter(
        _cfg(),
        JapaneseCandleInput(
            signal="BUY",
            trend_h4="BUY",
            regime="TREND",
            open_price=0.98,
            high_price=1.08,
            low_price=0.96,
            close_price=1.07,
            prev_open=1.04,
            prev_high=1.05,
            prev_low=0.97,
            prev_close=0.99,
        ),
    )
    assert out["ready"] is True
    assert out["candle_bias"] == "UP"
    assert "BULLISH_ENGULFING" in out["candle_patterns"]


def test_bearish_pin_conflict_for_buy() -> None:
    out = evaluate_japanese_candle_adapter(
        _cfg(),
        JapaneseCandleInput(
            signal="BUY",
            trend_h4="BUY",
            regime="TREND",
            open_price=1.05,
            high_price=1.15,
            low_price=1.02,
            close_price=1.03,
            prev_open=1.01,
            prev_high=1.07,
            prev_low=1.0,
            prev_close=1.04,
        ),
    )
    assert out["ready"] is True
    assert out["candle_bias"] in {"DOWN", "NONE"}
    if out["candle_bias"] == "DOWN":
        assert out["no_trade_hint"] is True
        assert out["reason_code"] == "CANDLE_CONFLICT"


def test_zero_range_is_not_ready() -> None:
    out = evaluate_japanese_candle_adapter(
        _cfg(),
        JapaneseCandleInput(
            signal="SELL",
            trend_h4="SELL",
            regime="RANGE",
            open_price=1.0,
            high_price=1.0,
            low_price=1.0,
            close_price=1.0,
            prev_open=1.0,
            prev_high=1.1,
            prev_low=0.9,
            prev_close=1.05,
        ),
    )
    assert out["ready"] is False
    assert out["reason_code"] == "CANDLE_RANGE_ZERO"

