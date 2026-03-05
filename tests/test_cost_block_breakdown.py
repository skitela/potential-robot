import json
import datetime as dt
from pathlib import Path
from zoneinfo import ZoneInfo

from TOOLS.cost_block_breakdown import build_block_breakdown


def test_build_block_breakdown_counts_cost_and_basket_blocks(tmp_path: Path) -> None:
    root = tmp_path
    (root / "LOGS").mkdir(parents=True, exist_ok=True)
    (root / "EVIDENCE").mkdir(parents=True, exist_ok=True)

    start_utc = dt.datetime(2026, 3, 5, 7, 0, 0, tzinfo=dt.timezone.utc)

    telemetry = [
        {
            "ts_utc": "2026-03-05T07:01:00Z",
            "event_type": "ENTRY_BLOCK_COST",
            "reason_code": "BLOCK_TRADE_COST_UNKNOWN",
            "cost_estimation_quality": "PARTIAL",
            "cost_target_to_estimated_ratio": 2.0,
            "cost_ratio_min_required": 1.15,
            "symbol_canonical": "USDJPY.pro",
        },
        {
            "ts_utc": "2026-03-05T07:02:00Z",
            "event_type": "ENTRY_BLOCK_BASKET",
            "reason_code": "JPY_BASKET_RISK_BUDGET",
            "symbol_canonical": "EURJPY.pro",
        },
        {
            "ts_utc": "2026-03-05T07:03:00Z",
            "event_type": "ENTRY_SHADOW_BLOCK_COST_MICROSTRUCTURE",
            "reason_code": "CMG_COST_QUALITY_UNKNOWN",
            "cost_grade": "POOR",
            "spread_roll_mean_points": None,
            "spread_roll_p95_points": None,
            "tick_rate_1s": None,
        },
    ]
    with (root / "LOGS" / "execution_telemetry_v2.jsonl").open("w", encoding="utf-8") as fh:
        for row in telemetry:
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")

    # Log timestamp is local (Europe/Warsaw) in this codebase.
    (root / "LOGS" / "safetybot.log").write_text(
        "\n".join(
            [
                "2026-03-05 08:01:10,000 | INFO | ENTRY_READY symbol=USDJPY.pro grp=FX mode=ECO",
                "2026-03-05 08:01:11,000 | INFO | ENTRY_SKIP_PRE symbol=USDJPY.pro grp=FX mode=ECO reason=M5_WAIT_NEW_BAR wait_s=10",
                "2026-03-05 08:01:12,000 | INFO | ENTRY_SIGNAL symbol=USDJPY.pro grp=FX mode=ECO",
                "2026-03-05 08:01:13,000 | ERROR | Order failed: 10006 JPY_BASKET_RISK_BUDGET",
            ]
        ),
        encoding="utf-8",
    )

    (root / "EVIDENCE" / "cost_guard_auto_relax_status.json").write_text(
        json.dumps({"active": True, "reason": "AUTO_RELAX_ACTIVE_THRESHOLD_MET"}, ensure_ascii=False),
        encoding="utf-8",
    )

    report = build_block_breakdown(
        root=root,
        start_utc=start_utc,
        local_tz=ZoneInfo("Europe/Warsaw"),
    )
    assert report["entry_block_cost"]["count"] == 1
    assert report["entry_block_basket"]["count"] == 1
    assert report["entry_shadow_block_cost_microstructure"]["count"] == 1
    assert report["safety_runtime"]["entry_skip_pre"] == 1
    assert report["safety_runtime"]["entry_signal"] == 1
    assert report["safety_runtime"]["order_failed"] == 1
