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


class TestFxAmSignalMatrix(unittest.TestCase):
    def test_strong_trend_signal_passes_threshold(self) -> None:
        prev = (
            safetybot.CFG.per_symbol,
            safetybot.CFG.per_group,
            safetybot.CFG.fx_signal_score_threshold,
            safetybot.CFG.fx_signal_score_hot_relaxed_threshold,
        )
        try:
            safetybot.CFG.per_symbol = {"EURUSD": {"fx_spread_cap_points": 18}}
            safetybot.CFG.per_group = {"FX": {"adx_threshold": 13, "adx_range_max": 10}}
            safetybot.CFG.fx_signal_score_threshold = 74
            safetybot.CFG.fx_signal_score_hot_relaxed_threshold = 68

            score, parts = safetybot.score_fx_entry_signal(
                symbol="EURUSD.pro",
                grp="FX",
                mode="HOT",
                signal="BUY",
                signal_reason="TREND_BREAK_CONTINUATION",
                trend_h4="BUY",
                structure_h4="BUY",
                regime="TREND",
                close_price=1.1032,
                open_price=1.1022,
                high_price=1.1035,
                low_price=1.1017,
                sma_fast_value=1.1026,
                adx_value=22.0,
                atr_value=0.0010,
                point=0.0001,
                spread_points=9.0,
                spread_p80=8.0,
                execution_error_recent=0,
            )
            self.assertGreaterEqual(score, 74)
            self.assertGreaterEqual(int(parts.get("A_regime_direction", 0.0)), 20)
        finally:
            (
                safetybot.CFG.per_symbol,
                safetybot.CFG.per_group,
                safetybot.CFG.fx_signal_score_threshold,
                safetybot.CFG.fx_signal_score_hot_relaxed_threshold,
            ) = prev

    def test_weak_signal_fails_threshold(self) -> None:
        prev = (
            safetybot.CFG.per_symbol,
            safetybot.CFG.per_group,
            safetybot.CFG.fx_signal_score_threshold,
        )
        try:
            safetybot.CFG.per_symbol = {"EURUSD": {"fx_spread_cap_points": 18}}
            safetybot.CFG.per_group = {"FX": {"adx_threshold": 13, "adx_range_max": 10}}
            safetybot.CFG.fx_signal_score_threshold = 74

            score, _parts = safetybot.score_fx_entry_signal(
                symbol="EURUSD.pro",
                grp="FX",
                mode="WARM",
                signal="BUY",
                signal_reason="RANGE_PULLBACK_BUY",
                trend_h4="BUY",
                structure_h4="SELL",
                regime="TRANSITION",
                close_price=1.1000,
                open_price=1.1000,
                high_price=1.1003,
                low_price=1.0997,
                sma_fast_value=1.1001,
                adx_value=11.5,
                atr_value=0.0002,
                point=0.0001,
                spread_points=30.0,
                spread_p80=10.0,
                execution_error_recent=3,
            )
            self.assertLess(score, 74)
        finally:
            (
                safetybot.CFG.per_symbol,
                safetybot.CFG.per_group,
                safetybot.CFG.fx_signal_score_threshold,
            ) = prev

    def test_hot_relaxed_threshold_selection(self) -> None:
        prev = (
            safetybot.CFG.fx_signal_score_threshold,
            safetybot.CFG.fx_signal_score_hot_relaxed_enabled,
            safetybot.CFG.fx_signal_score_hot_relaxed_threshold,
        )
        try:
            safetybot.CFG.fx_signal_score_threshold = 74
            safetybot.CFG.fx_signal_score_hot_relaxed_enabled = True
            safetybot.CFG.fx_signal_score_hot_relaxed_threshold = 68
            self.assertEqual(safetybot.fx_score_threshold_for_mode("HOT"), 68)
            self.assertEqual(safetybot.fx_score_threshold_for_mode("WARM"), 74)
        finally:
            (
                safetybot.CFG.fx_signal_score_threshold,
                safetybot.CFG.fx_signal_score_hot_relaxed_enabled,
                safetybot.CFG.fx_signal_score_hot_relaxed_threshold,
            ) = prev


if __name__ == "__main__":
    raise SystemExit(unittest.main())
