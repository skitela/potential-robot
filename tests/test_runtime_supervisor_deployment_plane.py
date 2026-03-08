import datetime as dt
import sys
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

from deployment_plane import build_kernel_symbol_rows, build_policy_runtime_payload
from runtime_supervisor import build_mt5_common_file_path, resolve_trade_trigger_mode


UTC = dt.timezone.utc


class TestRuntimeSupervisorDeploymentPlane(unittest.TestCase):
    def test_resolve_trade_trigger_mode_fallbacks(self) -> None:
        self.assertEqual(
            ("MQL5_SHADOW_COMPARE", "MQL5_ACTIVE_NOT_CUTOVER_READY"),
            resolve_trade_trigger_mode("MQL5_ACTIVE", allow_mql5_active=False),
        )
        self.assertEqual(
            ("BRIDGE_ACTIVE", "INVALID_MODE"),
            resolve_trade_trigger_mode("weird-mode", allow_mql5_active=False),
        )

    def test_build_mt5_common_file_path(self) -> None:
        path = build_mt5_common_file_path(
            enabled=True,
            subdir="OANDA_MT5_SYSTEM",
            file_name="kernel_config_v1.json",
            appdata="C:\\Users\\tester\\AppData\\Roaming",
        )
        self.assertEqual(
            Path("C:/Users/tester/AppData/Roaming/MetaQuotes/Terminal/Common/Files/OANDA_MT5_SYSTEM/kernel_config_v1.json"),
            path,
        )

    def test_build_kernel_symbol_rows_black_swan_halt(self) -> None:
        rows = build_kernel_symbol_rows(
            [("EURUSD", "EURUSD.pro", "FX"), ("EURUSD", "EURUSD.pro", "FX")],
            {"FX": {"entry_allowed": True, "reason": "NONE"}},
            black_swan_action="HALT",
            black_swan_reason="CRASH",
            black_swan_blocks=True,
            group_risk_fallback=lambda group_name, now_dt=None: {"entry_allowed": True, "reason": "NONE"},
            spread_cap_resolver=lambda symbol, group_name: 18.0,
            group_float_resolver=lambda group_name, key, default, symbol: default,
            group_int_resolver=lambda group_name, key, default, symbol: default,
            canonical_symbol_func=lambda symbol: symbol.upper(),
            group_key_func=lambda group_name: str(group_name).upper(),
            now_dt=dt.datetime(2026, 3, 8, tzinfo=UTC),
        )
        self.assertEqual(1, len(rows))
        self.assertFalse(rows[0]["entry_allowed"])
        self.assertTrue(rows[0]["close_only"])
        self.assertTrue(rows[0]["halt"])

    def test_build_policy_runtime_payload(self) -> None:
        payload = build_policy_runtime_payload(
            {"FX": {"priority_factor": 1.2, "price_cap": 10}},
            {"FX": {"entry_allowed": False, "reason": "BLACK_SWAN"}},
            flags={"policy_shadow_mode_enabled": True},
            ts_utc="2026-03-08T10:00:00Z",
            us_overlap_active=False,
        )
        self.assertEqual("1.0", payload["schema_version"])
        self.assertIn("FX", payload["groups"])
        self.assertFalse(payload["groups"]["FX"]["entry_allowed"])
        self.assertEqual("BLACK_SWAN", payload["groups"]["FX"]["reason"])


if __name__ == "__main__":
    raise SystemExit(unittest.main())
