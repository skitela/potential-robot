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


class TestStrategyRegimeAdaptive(unittest.TestCase):
    def test_resolve_adx_regime(self) -> None:
        self.assertEqual(safetybot.resolve_adx_regime(25.0, 14.0, 11.0), "TREND")
        self.assertEqual(safetybot.resolve_adx_regime(9.0, 14.0, 11.0), "RANGE")
        self.assertEqual(safetybot.resolve_adx_regime(12.0, 14.0, 11.0), "TRANSITION")

    def test_select_entry_signal_trend(self) -> None:
        sig, reason = safetybot.select_entry_signal(
            trend_h4="BUY",
            structure_h4="BUY",
            regime="TREND",
            close_price=1.1020,
            open_price=1.1000,
            sma_fast_value=1.1010,
            structure_filter_enabled=True,
            mean_reversion_enabled=True,
        )
        self.assertEqual(sig, "BUY")
        self.assertEqual(reason, "TREND_BREAK_CONTINUATION")

    def test_select_entry_signal_range(self) -> None:
        sig, reason = safetybot.select_entry_signal(
            trend_h4="SELL",
            structure_h4="SELL",
            regime="RANGE",
            close_price=1.2020,
            open_price=1.2000,
            sma_fast_value=1.2010,
            structure_filter_enabled=True,
            mean_reversion_enabled=True,
        )
        self.assertEqual(sig, "SELL")
        self.assertEqual(reason, "RANGE_PULLBACK_SELL")

    def test_select_entry_signal_structure_block(self) -> None:
        sig, reason = safetybot.select_entry_signal(
            trend_h4="BUY",
            structure_h4="SELL",
            regime="TREND",
            close_price=1.1020,
            open_price=1.1000,
            sma_fast_value=1.1010,
            structure_filter_enabled=True,
            mean_reversion_enabled=True,
        )
        self.assertIsNone(sig)
        self.assertEqual(reason, "STRUCTURE_MISMATCH")

    def test_select_entry_signal_trend_relaxed_for_warm(self) -> None:
        # Strict condition fails (close <= sma_fast), relaxed WARM path should still allow BUY.
        sig, reason = safetybot.select_entry_signal(
            trend_h4="BUY",
            structure_h4="BUY",
            regime="TREND",
            close_price=1.1005,
            open_price=1.1000,
            sma_fast_value=1.1010,
            structure_filter_enabled=False,
            mean_reversion_enabled=True,
            mode="WARM",
        )
        self.assertEqual(sig, "BUY")
        self.assertEqual(reason, "TREND_RELAXED_CONTINUATION")

    def test_select_entry_signal_trend_relaxed_not_applied_in_hot(self) -> None:
        # The same setup in HOT must remain strict and return NO_TREND_SIGNAL.
        sig, reason = safetybot.select_entry_signal(
            trend_h4="BUY",
            structure_h4="BUY",
            regime="TREND",
            close_price=1.1005,
            open_price=1.1000,
            sma_fast_value=1.1010,
            structure_filter_enabled=False,
            mean_reversion_enabled=True,
            mode="HOT",
        )
        self.assertIsNone(sig)
        self.assertEqual(reason, "NO_TREND_SIGNAL")

    def test_select_entry_signal_transition_relaxed_for_eco(self) -> None:
        sig, reason = safetybot.select_entry_signal(
            trend_h4="BUY",
            structure_h4="BUY",
            regime="TRANSITION",
            close_price=1.1012,
            open_price=1.1009,
            sma_fast_value=1.1010,
            structure_filter_enabled=False,
            mean_reversion_enabled=True,
            mode="ECO",
        )
        self.assertEqual(sig, "BUY")
        self.assertEqual(reason, "ADX_TRANSITION_ECO_CONTINUATION")

    def test_select_entry_signal_transition_not_relaxed_for_hot(self) -> None:
        sig, reason = safetybot.select_entry_signal(
            trend_h4="BUY",
            structure_h4="BUY",
            regime="TRANSITION",
            close_price=1.1012,
            open_price=1.1009,
            sma_fast_value=1.1010,
            structure_filter_enabled=False,
            mean_reversion_enabled=True,
            mode="HOT",
        )
        self.assertIsNone(sig)
        self.assertEqual(reason, "ADX_TRANSITION")

    def test_adaptive_exit_points_uses_atr(self) -> None:
        prev = (
            safetybot.CFG.fixed_sl_points,
            safetybot.CFG.fixed_tp_points,
            safetybot.CFG.atr_exit_enabled,
            safetybot.CFG.atr_exit_use_override,
            safetybot.CFG.atr_sl_mult_hot,
            safetybot.CFG.atr_tp_mult_hot,
            safetybot.CFG.atr_sl_min_points,
            safetybot.CFG.atr_tp_min_points,
        )
        try:
            safetybot.CFG.fixed_sl_points = 250
            safetybot.CFG.fixed_tp_points = 500
            safetybot.CFG.atr_exit_enabled = True
            safetybot.CFG.atr_exit_use_override = True
            safetybot.CFG.atr_sl_mult_hot = 1.0
            safetybot.CFG.atr_tp_mult_hot = 2.0
            safetybot.CFG.atr_sl_min_points = 50
            safetybot.CFG.atr_tp_min_points = 100

            sl_pts, tp_pts = safetybot.adaptive_exit_points("HOT", point=0.0001, atr_value=0.0040)
            self.assertEqual(sl_pts, 50)
            self.assertEqual(tp_pts, 100)
        finally:
            (
                safetybot.CFG.fixed_sl_points,
                safetybot.CFG.fixed_tp_points,
                safetybot.CFG.atr_exit_enabled,
                safetybot.CFG.atr_exit_use_override,
                safetybot.CFG.atr_sl_mult_hot,
                safetybot.CFG.atr_tp_mult_hot,
                safetybot.CFG.atr_sl_min_points,
                safetybot.CFG.atr_tp_min_points,
            ) = prev

    def test_partial_close_volume(self) -> None:
        vol = safetybot.partial_close_volume(0.30, 0.5, vol_min=0.01, vol_step=0.01)
        self.assertAlmostEqual(vol, 0.15)
        # minimum leg respected on both sides
        vol2 = safetybot.partial_close_volume(0.02, 0.8, vol_min=0.01, vol_step=0.01)
        self.assertEqual(vol2, 0.01)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
