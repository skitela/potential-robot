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

from self_heal_guard import SelfHealGuard, SelfHealPolicy


class TestSelfHealGuard(unittest.TestCase):
    def test_loss_streak_triggers_pause(self) -> None:
        now = 1_700_000_000
        guard = SelfHealGuard(
            SelfHealPolicy(
                lookback_sec=3600,
                min_deals_in_window=3,
                loss_streak_trigger=3,
                max_net_loss_abs=0.0,
                backoff_seconds=600,
                symbol_cooldown_seconds=300,
            )
        )
        deals = [
            (now - 10, "EURUSD", -1.20),
            (now - 20, "EURUSD", -0.80),
            (now - 30, "GBPUSD", -0.50),
            (now - 40, "EURUSD", 0.40),
        ]
        sig = guard.evaluate(deals_desc=deals, now_ts=now)
        self.assertTrue(sig.active)
        self.assertIn("LOSS_STREAK", sig.reasons)
        self.assertEqual(sig.loss_streak, 3)
        self.assertEqual(sig.backoff_seconds, 600)
        self.assertEqual(sig.symbol_cooldown_seconds, 300)
        self.assertEqual(sig.streak_symbols, ("EURUSD", "GBPUSD"))

    def test_net_loss_abs_triggers_pause(self) -> None:
        now = 1_700_000_000
        guard = SelfHealGuard(
            SelfHealPolicy(
                lookback_sec=3600,
                min_deals_in_window=2,
                loss_streak_trigger=5,
                max_net_loss_abs=2.0,
                backoff_seconds=900,
            )
        )
        deals = [
            (now - 10, "EURUSD", -1.40),
            (now - 20, "GBPUSD", -0.90),
            (now - 30, "EURUSD", 0.10),
        ]
        sig = guard.evaluate(deals_desc=deals, now_ts=now)
        self.assertTrue(sig.active)
        self.assertIn("NET_LOSS_ABS", sig.reasons)
        self.assertLessEqual(sig.net_pnl, -2.0)

    def test_persistence_api_added(self) -> None:
        src = (ROOT / "BIN" / "safetybot.py").read_text(encoding="utf-8", errors="replace")
        self.assertIn("def recent_deals_for_self_heal", src)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
