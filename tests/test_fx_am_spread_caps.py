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


class TestFxAmSpreadCaps(unittest.TestCase):
    def test_per_symbol_cap_has_priority(self) -> None:
        prev = (
            safetybot.CFG.per_symbol,
            safetybot.CFG.per_group,
            safetybot.CFG.fx_spread_cap_points_default,
        )
        try:
            safetybot.CFG.fx_spread_cap_points_default = 24.0
            safetybot.CFG.per_group = {"FX": {"fx_spread_cap_points": 30.0}}
            safetybot.CFG.per_symbol = {"EURUSD": {"fx_spread_cap_points": 18.0}}
            cap = safetybot.fx_spread_cap_points("EURUSD.pro", grp="FX")
            self.assertEqual(cap, 18.0)
        finally:
            (
                safetybot.CFG.per_symbol,
                safetybot.CFG.per_group,
                safetybot.CFG.fx_spread_cap_points_default,
            ) = prev

    def test_group_cap_used_when_symbol_missing(self) -> None:
        prev = (
            safetybot.CFG.per_symbol,
            safetybot.CFG.per_group,
            safetybot.CFG.fx_spread_cap_points_default,
        )
        try:
            safetybot.CFG.fx_spread_cap_points_default = 24.0
            safetybot.CFG.per_symbol = {}
            safetybot.CFG.per_group = {"FX": {"fx_spread_cap_points": 26.0}}
            cap = safetybot.fx_spread_cap_points("USDCAD.pro", grp="FX")
            self.assertEqual(cap, 26.0)
        finally:
            (
                safetybot.CFG.per_symbol,
                safetybot.CFG.per_group,
                safetybot.CFG.fx_spread_cap_points_default,
            ) = prev

    def test_default_cap_used_when_no_override(self) -> None:
        prev = (
            safetybot.CFG.per_symbol,
            safetybot.CFG.per_group,
            safetybot.CFG.fx_spread_cap_points_default,
        )
        try:
            safetybot.CFG.fx_spread_cap_points_default = 24.0
            safetybot.CFG.per_symbol = {}
            safetybot.CFG.per_group = {}
            cap = safetybot.fx_spread_cap_points("AUDUSD.pro", grp="FX")
            self.assertEqual(cap, 24.0)
        finally:
            (
                safetybot.CFG.per_symbol,
                safetybot.CFG.per_group,
                safetybot.CFG.fx_spread_cap_points_default,
            ) = prev


if __name__ == "__main__":
    raise SystemExit(unittest.main())
