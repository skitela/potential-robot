from __future__ import annotations

from TOOLS.preseed_kernel_config import build_rows_from_strategy, guess_group, normalize_symbol


def test_normalize_symbol_maps_metals_and_pro_suffix() -> None:
    assert normalize_symbol("XAUUSD") == "GOLD.pro"
    assert normalize_symbol("xagusd") == "SILVER.pro"
    assert normalize_symbol("EURUSD") == "EURUSD.pro"
    assert normalize_symbol("EURUSD.PRO") == "EURUSD.pro"


def test_guess_group_detects_core_groups() -> None:
    assert guess_group("EURUSD.pro") == "FX"
    assert guess_group("GOLD.pro") == "METAL"
    assert guess_group("US500.pro") == "INDEX"
    assert guess_group("BTCUSD") == "CRYPTO"


def test_build_rows_from_strategy_builds_unique_kernel_rows() -> None:
    cfg = {
        "symbols_to_trade": ["EURUSD", "XAUUSD", "US500", "EURUSD"],
        "fx_spread_cap_points_default": 12.0,
        "metal_spread_cap_points_default": 180.0,
    }
    rows = build_rows_from_strategy(cfg)
    assert len(rows) == 3
    symbols = {row["symbol"] for row in rows}
    assert symbols == {"EURUSD.pro", "GOLD.pro", "US500.pro"}
    by_symbol = {row["symbol"]: row for row in rows}
    assert by_symbol["EURUSD.pro"]["spread_cap_points"] == 12.0
    assert by_symbol["GOLD.pro"]["spread_cap_points"] == 180.0
    assert by_symbol["US500.pro"]["spread_cap_points"] == 0.0
