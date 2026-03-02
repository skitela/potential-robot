from __future__ import annotations

from BIN.renko_sensor import (
    RenkoSensorConfig,
    RenkoTick,
    build_renko_bricks,
)


def test_renko_invalid_config_not_ready() -> None:
    out = build_renko_bricks(
        RenkoSensorConfig(brick_size_points=0.0, point=0.0001, price_source="MID"),
        [],
    )
    assert out["ready"] is False
    assert out["reason_code"] == "RENKO_INVALID_CONFIG"


def test_renko_builds_bricks_with_reversal_flag() -> None:
    ticks = [
        RenkoTick(ts_msc=1000, bid=1.10000, ask=1.10020),
        RenkoTick(ts_msc=1100, bid=1.10060, ask=1.10080),  # up
        RenkoTick(ts_msc=1200, bid=1.10120, ask=1.10140),  # up
        RenkoTick(ts_msc=1300, bid=1.10010, ask=1.10030),  # down reversal
    ]
    out = build_renko_bricks(
        RenkoSensorConfig(brick_size_points=5.0, point=0.0001, price_source="MID"),
        ticks,
    )
    assert out["ready"] is True
    assert out["bricks_count"] >= 2
    assert out["last_brick_dir"] in {"UP", "DOWN"}
    assert "quality_flags" in out


def test_renko_detects_ask_lt_bid_quality_issue() -> None:
    ticks = [
        RenkoTick(ts_msc=1000, bid=1.10020, ask=1.10000),
        RenkoTick(ts_msc=2000, bid=1.10120, ask=1.10100),
    ]
    out = build_renko_bricks(
        RenkoSensorConfig(brick_size_points=2.0, point=0.0001, price_source="MID"),
        ticks,
    )
    assert out["quality_flags"]["ask_lt_bid_count"] >= 1

