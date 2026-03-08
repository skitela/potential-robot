from __future__ import annotations

from pathlib import Path


def test_budget_and_price_breakdown_log_throttle_contract_present() -> None:
    src = Path("BIN/safetybot.py").read_text(encoding="utf-8")
    assert "budget_log_interval_sec" in src
    assert "oanda_price_breakdown_log_interval_sec" in src
    assert "_last_budget_log_ts" in src
    assert "_last_oanda_price_breakdown_log_ts" in src
    assert "BUDGET day_ny=" in src
    assert "OANDA_PRICE_BREAKDOWN day=" in src
