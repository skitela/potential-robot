from __future__ import annotations

from TOOLS.lab_mt5_history_ingest import count_gap_events, resolve_broker_symbol


def test_resolve_broker_symbol_exact() -> None:
    broker, mode = resolve_broker_symbol("EURUSD", ["EURUSD", "GBPUSD.a"])
    assert broker == "EURUSD"
    assert mode == "EXACT"


def test_resolve_broker_symbol_prefix() -> None:
    broker, mode = resolve_broker_symbol("GBPUSD", ["EURUSD", "GBPUSD.a", "GBPUSD.pro"])
    assert broker == "GBPUSD.a"
    assert mode == "PREFIX"


def test_resolve_broker_symbol_not_found() -> None:
    broker, mode = resolve_broker_symbol("USDNOK", ["EURUSD", "GBPUSD"])
    assert broker is None
    assert mode == "NOT_FOUND"


def test_count_gap_events() -> None:
    rows = [
        {"ts_utc": "2026-03-02T10:00:00Z"},
        {"ts_utc": "2026-03-02T10:01:00Z"},
        {"ts_utc": "2026-03-02T10:05:00Z"},  # gap vs M1
        {"ts_utc": "2026-03-02T10:06:00Z"},
    ]
    assert count_gap_events(rows, expected_interval_sec=60) == 1

