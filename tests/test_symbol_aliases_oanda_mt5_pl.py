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


class _MtStub:
    def __init__(self, available):
        self.available = set(str(x).upper() for x in available)
        self.calls = []

    def symbol_info_cached(self, symbol, grp, _db):
        key = str(symbol).upper()
        self.calls.append((key, str(grp)))
        return object() if key in self.available else None


class _Info:
    def __init__(self, trade_mode: int):
        self.trade_mode = int(trade_mode)


class _Mt5Probe:
    SYMBOL_TRADE_MODE_DISABLED = 0
    SYMBOL_TRADE_MODE_LONGONLY = 1
    SYMBOL_TRADE_MODE_SHORTONLY = 2
    SYMBOL_TRADE_MODE_CLOSEONLY = 3
    SYMBOL_TRADE_MODE_FULL = 4

    def __init__(self, mode_map):
        self.mode_map = {str(k).upper(): int(v) for k, v in dict(mode_map).items()}

    def symbol_info(self, symbol):
        mode = self.mode_map.get(str(symbol).upper())
        if mode is None:
            return None
        return _Info(mode)

    def symbol_select(self, _symbol, _enabled):
        return True


class TestSymbolAliasesOandaMt5Pl(unittest.TestCase):
    def test_alias_candidates_cover_oanda_tms_names(self):
        dax = safetybot.symbol_alias_candidates("DAX40")
        self.assertIn("DE30", dax)
        self.assertIn("DE40", dax)

        xau = safetybot.symbol_alias_candidates("XAUUSD")
        self.assertIn("GOLD", xau)

    def test_group_and_profile_support_oanda_aliases(self):
        self.assertEqual(safetybot.guess_group("DE30.pro"), "INDEX")
        self.assertEqual(safetybot.index_profile("DE30.pro"), "EU")
        self.assertEqual(safetybot.guess_group("GOLD.pro"), "METAL")
        self.assertEqual(safetybot.guess_group("BTCUSD.pro"), "CRYPTO")

    def test_resolve_canon_symbol_uses_aliases_and_suffixes(self):
        bot = types.SimpleNamespace()
        bot.resolved_symbols = {}
        bot.db = object()
        bot.mt = _MtStub({"DE30.PRO", "GOLD.PRO"})

        got_dax = safetybot.SafetyBot.resolve_canon_symbol(bot, "DAX40")
        got_xau = safetybot.SafetyBot.resolve_canon_symbol(bot, "XAUUSD")

        self.assertEqual(got_dax, "DE30.pro")
        self.assertEqual(got_xau, "GOLD.pro")
        self.assertEqual(bot.resolved_symbols.get("DAX40"), "DE30.pro")
        self.assertEqual(bot.resolved_symbols.get("XAUUSD"), "GOLD.pro")

    def test_resolve_canon_symbol_prefers_tradeable_over_disabled_base(self):
        bot = types.SimpleNamespace()
        bot.resolved_symbols = {}
        bot.db = object()
        bot.mt = _MtStub({"GBPUSD", "GBPUSD.PRO"})

        prev_mt5 = safetybot.mt5
        safetybot.mt5 = _Mt5Probe(
            {
                "GBPUSD": _Mt5Probe.SYMBOL_TRADE_MODE_DISABLED,
                "GBPUSD.PRO": _Mt5Probe.SYMBOL_TRADE_MODE_FULL,
            }
        )
        try:
            got = safetybot.SafetyBot.resolve_canon_symbol(bot, "GBPUSD")
        finally:
            safetybot.mt5 = prev_mt5

        self.assertEqual(got, "GBPUSD.pro")
        self.assertEqual(bot.resolved_symbols.get("GBPUSD"), "GBPUSD.pro")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
