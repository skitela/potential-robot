from __future__ import annotations

import json
from pathlib import Path

from TOOLS.kernel_shadow_parity_report import (
    _parse_parity_line,
    _parse_state_line,
    build_report,
)


def test_parse_state_line_extracts_core_fields() -> None:
    line = (
        "AB 0 19:32:22.351 HybridAgent (EURUSD.pro,M5) "
        "KERNEL_SHADOW_STATE src=TIMER symbol=EURUSD.PRO action=BLOCK "
        "reason=PROFILE_NOT_LOADED profile_loaded=0 spread_now=10.00"
    )
    parsed = _parse_state_line(line)
    assert parsed is not None
    assert parsed["symbol"] == "EURUSD.PRO"
    assert parsed["action"] == "BLOCK"
    assert parsed["reason"] == "PROFILE_NOT_LOADED"
    assert parsed["profile_loaded"] is False


def test_parse_parity_line_extracts_core_fields() -> None:
    line = (
        "AB 0 19:32:22.351 HybridAgent (EURUSD.pro,M5) "
        "KERNEL_SHADOW_TRADE_PARITY parity=MISMATCH symbol=EURUSD.PRO "
        "legacy_allowed=1 legacy_reason=NONE kernel_action=BLOCK kernel_reason=PROFILE_NOT_LOADED"
    )
    parsed = _parse_parity_line(line)
    assert parsed is not None
    assert parsed["parity"] == "MISMATCH"
    assert parsed["symbol"] == "EURUSD.PRO"
    assert parsed["legacy_allowed"] is True
    assert parsed["kernel_reason"] == "PROFILE_NOT_LOADED"


def test_build_report_counts_state_and_parity(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    root.mkdir(parents=True, exist_ok=True)
    (root / "CONFIG").mkdir(parents=True, exist_ok=True)
    (root / "CONFIG" / "strategy.json").write_text(
        json.dumps(
            {
                "trade_windows": {
                    "FX_EVE": {
                        "anchor_tz": "UTC",
                        "start_hm": [19, 0],
                        "end_hm": [20, 0],
                        "group": "FX",
                    }
                }
            }
        ),
        encoding="utf-8",
    )
    mql_log = tmp_path / "20260308.log"
    mql_log.write_text(
        "\n".join(
            [
                "AB 0 19:32:22.351 HybridAgent (EURUSD.pro,M5) KERNEL_SHADOW_STATE src=TIMER symbol=EURUSD.PRO action=BLOCK reason=PROFILE_NOT_LOADED profile_loaded=0",
                "AB 0 19:33:22.351 HybridAgent (EURUSD.pro,M5) KERNEL_SHADOW_TRADE_PARITY parity=MATCH symbol=EURUSD.PRO legacy_allowed=1 legacy_reason=NONE kernel_action=ALLOW kernel_reason=NONE",
                "AB 0 19:34:22.351 HybridAgent (GBPUSD.pro,M5) KERNEL_SHADOW_TRADE_PARITY parity=MISMATCH symbol=GBPUSD.PRO legacy_allowed=1 legacy_reason=NONE kernel_action=BLOCK kernel_reason=PROFILE_NOT_LOADED",
            ]
        ),
        encoding="utf-8",
    )

    report = build_report(root=root, hours=72, mt5_data_dir=None, log_path=mql_log)
    assert report["status"] in {"WARN", "PASS", "NO_PARITY_DATA"}
    summary = dict(report.get("summary") or {})
    assert summary.get("state_rows") == 1
    assert summary.get("state_profile_not_loaded_rows") == 1
    assert summary.get("parity_rows") == 2
    assert summary.get("parity_mismatch") == 1
    counts = dict(report.get("counts") or {})
    parity_by_window = list(counts.get("parity_by_window_top10") or [])
    assert parity_by_window and parity_by_window[0]["window"] == "FX_EVE"
    mismatch_symbol_window = list(counts.get("parity_mismatch_by_symbol_window_top10") or [])
    assert mismatch_symbol_window and mismatch_symbol_window[0]["symbol_window"] == "GBPUSD.PRO|FX_EVE"
