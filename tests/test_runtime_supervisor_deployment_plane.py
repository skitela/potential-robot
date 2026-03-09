import datetime as dt
import json
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace
import unittest


ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

from deployment_plane import build_kernel_symbol_rows, build_policy_runtime_payload
from runtime_supervisor import (
    build_runtime_loop_state,
    build_mt5_common_file_path,
    build_runtime_loop_settings,
    evaluate_mql5_active_readiness_gate,
    resolve_trade_trigger_mode,
)


UTC = dt.timezone.utc


class TestRuntimeSupervisorDeploymentPlane(unittest.TestCase):
    def test_resolve_trade_trigger_mode_fallbacks(self) -> None:
        self.assertEqual(
            ("MQL5_SHADOW_COMPARE", "MQL5_ACTIVE_NOT_CUTOVER_READY"),
            resolve_trade_trigger_mode("MQL5_ACTIVE", allow_mql5_active=False),
        )
        self.assertEqual(
            ("MQL5_ACTIVE", "OK"),
            resolve_trade_trigger_mode("MQL5_ACTIVE", allow_mql5_active=True),
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

    def test_build_runtime_loop_settings_normalizes_bounds(self) -> None:
        cfg = SimpleNamespace(
            scan_interval_sec=30,
            zmq_heartbeat_interval_sec=0,
            zmq_heartbeat_fail_threshold=0,
            zmq_heartbeat_fail_safe_cooldown_sec=-5,
            zmq_heartbeat_fail_log_interval_sec=0,
            zmq_scan_suppressed_log_interval_sec=0,
            bridge_trade_timeout_ms=2000,
            bridge_default_timeout_ms=1200,
            bridge_trade_retries=3,
            bridge_default_retries=2,
            bridge_heartbeat_timeout_ms=3000,
            bridge_heartbeat_retries=5,
            bridge_heartbeat_queue_lock_timeout_ms=250,
            run_loop_idle_sleep_sec=0.0,
            run_loop_scan_slow_warn_ms=10,
            zmq_heartbeat_worker_stale_sec=10,
            bridge_trade_probe_enabled=True,
            bridge_trade_probe_interval_sec=2,
            bridge_trade_probe_max_per_run=-1,
            bridge_trade_probe_signal="invalid",
            bridge_trade_probe_symbol=" EURUSD.pro ",
            bridge_trade_probe_group=" fx ",
            bridge_trade_probe_volume=-1.0,
            bridge_trade_probe_deviation_points=0,
            bridge_trade_probe_comment=" test-comment ",
        )

        got = build_runtime_loop_settings(cfg)
        self.assertEqual(30, got.scan_interval)
        self.assertEqual(1, got.heartbeat_interval)
        self.assertEqual(1, got.heartbeat_fail_threshold)
        self.assertEqual(1, got.heartbeat_fail_safe_cooldown)
        self.assertEqual(1, got.heartbeat_fail_log_interval)
        self.assertEqual(1, got.scan_suppressed_log_interval)
        self.assertEqual(2000, got.trade_timeout_budget_ms)
        self.assertEqual(3, got.trade_retries_budget)
        self.assertEqual(1500, got.heartbeat_timeout_budget_ms)
        self.assertEqual(3, got.heartbeat_retries_budget)
        self.assertEqual(100, got.heartbeat_queue_lock_timeout_ms)
        self.assertEqual(0.001, got.run_loop_idle_sleep)
        self.assertEqual(100, got.scan_slow_warn_ms)
        self.assertEqual(30, got.heartbeat_worker_stale_sec)
        self.assertTrue(got.trade_probe_enabled)
        self.assertEqual(5, got.trade_probe_interval_sec)
        self.assertEqual(0, got.trade_probe_max_per_run)
        self.assertEqual("BUY", got.trade_probe_signal)
        self.assertEqual("EURUSD.pro", got.trade_probe_symbol)
        self.assertEqual("FX", got.trade_probe_group)
        self.assertEqual(0.0, got.trade_probe_volume)
        self.assertEqual(10, got.trade_probe_deviation_points)
        self.assertEqual("test-comment", got.trade_probe_comment)

    def test_build_runtime_loop_state_defaults(self) -> None:
        st = build_runtime_loop_state()
        self.assertEqual(0.0, float(st["last_scan_ts"]))
        self.assertEqual(0.0, float(st["last_heartbeat_ts"]))
        self.assertEqual(0.0, float(st["last_market_data_ts"]))
        self.assertEqual(0, int(st["heartbeat_failures"]))
        self.assertFalse(bool(st["heartbeat_fail_safe_active"]))
        self.assertEqual(0.0, float(st["heartbeat_fail_safe_until"]))
        self.assertEqual(0.0, float(st["last_trade_probe_ts"]))
        self.assertEqual(0, int(st["trade_probe_sent"]))
        self.assertEqual(0, int(st["loop_id"]))

    def test_evaluate_mql5_active_readiness_gate_missing_and_disabled(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            ok, reason = evaluate_mql5_active_readiness_gate(runtime_root=root, enabled=False)
            self.assertFalse(ok)
            self.assertEqual("CUTOVER_GATE_DISABLED", reason)

            ok, reason = evaluate_mql5_active_readiness_gate(runtime_root=root, enabled=True)
            self.assertFalse(ok)
            self.assertEqual("CUTOVER_READINESS_MISSING", reason)

    def test_evaluate_mql5_active_readiness_gate_pass_and_stale(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            readiness = root / "EVIDENCE" / "cutover" / "mql5_cutover_readiness_latest.json"
            readiness.parent.mkdir(parents=True, exist_ok=True)

            fresh_payload = {
                "status": "PASS",
                "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
            }
            readiness.write_text(json.dumps(fresh_payload), encoding="utf-8")
            ok, reason = evaluate_mql5_active_readiness_gate(
                runtime_root=root,
                enabled=True,
                max_age_sec=3600,
            )
            self.assertTrue(ok)
            self.assertEqual("OK", reason)

            stale_payload = {
                "status": "PASS",
                "generated_at_utc": "2026-03-01T00:00:00Z",
            }
            readiness.write_text(json.dumps(stale_payload), encoding="utf-8")
            ok, reason = evaluate_mql5_active_readiness_gate(
                runtime_root=root,
                enabled=True,
                max_age_sec=300,
            )
            self.assertFalse(ok)
            self.assertEqual("CUTOVER_READINESS_STALE", reason)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
