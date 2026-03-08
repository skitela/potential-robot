import json
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch

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
from kernel_config_plane import (
    KERNEL_CONFIG_HASH_METHOD,
    KERNEL_CONFIG_HASH_SCOPE,
    KERNEL_CONFIG_SCHEMA_VERSION,
    build_kernel_config_payload,
    build_kernel_config_signature,
    sanitize_symbol_entry,
)


class TestKernelConfigPlane(unittest.TestCase):
    def test_sanitize_symbol_entry_rejects_risk_locked_keys(self) -> None:
        with self.assertRaisesRegex(ValueError, "kernel_config_risk_locked"):
            sanitize_symbol_entry(
                {
                    "symbol": "EURUSD.pro",
                    "entry_allowed": True,
                    "risk_per_trade": 0.01,
                }
            )

    def test_build_kernel_config_payload_is_hashed_and_sorted(self) -> None:
        payload = build_kernel_config_payload(
            [
                {"symbol": "GBPUSD.pro", "entry_allowed": True, "reason": "NONE"},
                {"symbol": "EURUSD.pro", "entry_allowed": False, "close_only": True, "reason": "FRIDAY"},
            ],
            meta={"source": "unit-test"},
        )
        self.assertEqual(KERNEL_CONFIG_SCHEMA_VERSION, payload.get("schema_version"))
        self.assertEqual(KERNEL_CONFIG_HASH_METHOD, str(payload.get("hash_method") or ""))
        self.assertEqual(KERNEL_CONFIG_HASH_SCOPE, str(payload.get("hash_scope") or ""))
        self.assertEqual(64, len(str(payload.get("config_hash") or "")))
        symbols = payload.get("symbols") or []
        self.assertEqual(["EURUSD.pro", "GBPUSD.pro"], [str(x.get("symbol")) for x in symbols])

    def test_build_kernel_config_signature_is_stable_for_same_rows(self) -> None:
        rows = [
            sanitize_symbol_entry(
                {
                    "symbol": "EURUSD.pro",
                    "group": "FX",
                    "entry_allowed": True,
                    "close_only": False,
                    "halt": False,
                    "reason": "NONE",
                    "spread_cap_points": 12.5,
                    "max_latency_ms": 300.0,
                    "min_tick_rate_1s": 3,
                    "min_liquidity_score": 0.1,
                    "min_tradeability_score": 0.2,
                    "min_setup_quality_score": 0.3,
                }
            )
        ]
        a = build_kernel_config_signature(
            schema_version="kernel_config_v1",
            generated_at_utc="2026-03-08T00:00:00Z",
            policy_version="kernel.shadow.v1",
            symbols=rows,
        )
        b = build_kernel_config_signature(
            schema_version="kernel_config_v1",
            generated_at_utc="2026-03-08T00:00:00Z",
            policy_version="kernel.shadow.v1",
            symbols=rows,
        )
        self.assertEqual(a, b)

    def test_safetybot_builds_kernel_payload_for_universe(self) -> None:
        with patch.object(safetybot.SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = safetybot.SafetyBot()

        bot.universe = [("EURUSD", "EURUSD.pro", "FX"), ("GOLD", "GOLD.pro", "METAL")]
        bot.runtime_root = ROOT
        bot.meta_dir = ROOT / "RUN"
        bot._black_swan_v2_state = "NORMAL"
        bot._black_swan_v2_action = "ALLOW"
        bot._black_swan_v2_reason = "NONE"
        bot._black_swan_block_new_entries = False

        payload = bot._build_kernel_config_payload(group_risk={"FX": {"entry_allowed": True, "reason": "NONE"}})
        self.assertEqual(KERNEL_CONFIG_SCHEMA_VERSION, str(payload.get("schema_version") or ""))
        rows = payload.get("symbols") or []
        self.assertEqual(2, len(rows))
        eurusd = next(x for x in rows if str(x.get("symbol") or "") == "EURUSD.pro")
        self.assertIn("spread_cap_points", eurusd)
        self.assertIn("max_latency_ms", eurusd)
        self.assertIn("entry_allowed", eurusd)
        self.assertIn("meta", payload)

    def test_trade_trigger_mode_falls_back_for_unimplemented_active_mode(self) -> None:
        with patch.object(safetybot.SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = safetybot.SafetyBot()
        old = safetybot.CFG.trade_trigger_mode
        try:
            safetybot.CFG.trade_trigger_mode = "MQL5_ACTIVE"
            self.assertEqual("MQL5_SHADOW_COMPARE", bot._trade_trigger_mode())
            safetybot.CFG.trade_trigger_mode = "UNKNOWN"
            self.assertEqual("BRIDGE_ACTIVE", bot._trade_trigger_mode())
        finally:
            safetybot.CFG.trade_trigger_mode = old


if __name__ == "__main__":
    raise SystemExit(unittest.main())
