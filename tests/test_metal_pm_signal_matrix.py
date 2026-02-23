import sys
import types
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

if "MetaTrader5" not in sys.modules:
    mt5_stub = types.ModuleType("MetaTrader5")
    mt5_stub.TIMEFRAME_M5 = 5
    mt5_stub.TIMEFRAME_H4 = 16388
    mt5_stub.TIMEFRAME_D1 = 16408
    sys.modules["MetaTrader5"] = mt5_stub

import safetybot


class TestMetalPmSignalMatrix(unittest.TestCase):
    def test_strong_metal_signal_passes_threshold(self) -> None:
        prev = (
            safetybot.CFG.per_symbol,
            safetybot.CFG.per_group,
            safetybot.CFG.metal_signal_score_threshold,
            safetybot.CFG.metal_signal_score_hot_relaxed_threshold,
        )
        try:
            safetybot.CFG.per_symbol = {"XAUUSD": {"metal_spread_cap_points": 90}}
            safetybot.CFG.per_group = {"METAL": {"adx_threshold": 17, "adx_range_max": 11}}
            safetybot.CFG.metal_signal_score_threshold = 76
            safetybot.CFG.metal_signal_score_hot_relaxed_threshold = 70

            score, parts = safetybot.score_metal_entry_signal(
                symbol="XAUUSD.pro",
                grp="METAL",
                mode="HOT",
                signal="BUY",
                signal_reason="TREND_BREAK_CONTINUATION",
                trend_h4="BUY",
                structure_h4="BUY",
                regime="TREND",
                close_price=2011.0,
                open_price=2010.0,
                high_price=2011.0,
                low_price=2008.8,
                sma_fast_value=2010.9,
                adx_value=24.0,
                atr_value=1.5,
                point=0.01,
                spread_points=40.0,
                spread_p80=35.0,
                execution_error_recent=0,
            )
            self.assertGreaterEqual(score, 76)
            self.assertGreaterEqual(float(parts.get("wick_ratio", 0.0)), 1.2)
        finally:
            (
                safetybot.CFG.per_symbol,
                safetybot.CFG.per_group,
                safetybot.CFG.metal_signal_score_threshold,
                safetybot.CFG.metal_signal_score_hot_relaxed_threshold,
            ) = prev

    def test_weak_metal_signal_fails_threshold(self) -> None:
        prev = (
            safetybot.CFG.per_symbol,
            safetybot.CFG.per_group,
            safetybot.CFG.metal_signal_score_threshold,
        )
        try:
            safetybot.CFG.per_symbol = {"XAUUSD": {"metal_spread_cap_points": 90}}
            safetybot.CFG.per_group = {"METAL": {"adx_threshold": 17, "adx_range_max": 11}}
            safetybot.CFG.metal_signal_score_threshold = 76

            score, _parts = safetybot.score_metal_entry_signal(
                symbol="XAUUSD.pro",
                grp="METAL",
                mode="WARM",
                signal="BUY",
                signal_reason="RANGE_PULLBACK_BUY",
                trend_h4="BUY",
                structure_h4="SELL",
                regime="TRANSITION",
                close_price=2010.0,
                open_price=2010.0,
                high_price=2010.2,
                low_price=2009.9,
                sma_fast_value=2010.4,
                adx_value=12.0,
                atr_value=0.3,
                point=0.01,
                spread_points=180.0,
                spread_p80=60.0,
                execution_error_recent=4,
            )
            self.assertLess(score, 76)
        finally:
            (
                safetybot.CFG.per_symbol,
                safetybot.CFG.per_group,
                safetybot.CFG.metal_signal_score_threshold,
            ) = prev

    def test_hot_relaxed_threshold_selection(self) -> None:
        prev = (
            safetybot.CFG.metal_signal_score_threshold,
            safetybot.CFG.metal_signal_score_hot_relaxed_enabled,
            safetybot.CFG.metal_signal_score_hot_relaxed_threshold,
        )
        try:
            safetybot.CFG.metal_signal_score_threshold = 76
            safetybot.CFG.metal_signal_score_hot_relaxed_enabled = True
            safetybot.CFG.metal_signal_score_hot_relaxed_threshold = 70
            self.assertEqual(safetybot.metal_score_threshold_for_mode("HOT"), 70)
            self.assertEqual(safetybot.metal_score_threshold_for_mode("WARM"), 76)
        finally:
            (
                safetybot.CFG.metal_signal_score_threshold,
                safetybot.CFG.metal_signal_score_hot_relaxed_enabled,
                safetybot.CFG.metal_signal_score_hot_relaxed_threshold,
            ) = prev


if __name__ == "__main__":
    raise SystemExit(unittest.main())
