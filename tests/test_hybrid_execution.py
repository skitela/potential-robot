import datetime as dt
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from BIN.safetybot import CFG, SafetyBot, StandardStrategy, build_response_hash
from BIN.self_heal_guard import SelfHealSignal
from BIN.canary_rollout_guard import CanarySignal
from BIN.drift_guard import DriftSignal


class TestHybridExecution(unittest.TestCase):
    def _build_bot(self) -> SafetyBot:
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot.execution_queue = None
        bot.execution_engine = MagicMock()
        bot._send_trade_command = MagicMock()
        return bot

    @patch("BIN.safetybot.mt5")
    def test_dispatch_order_builds_result_from_processed_reply(self, mock_mt5):
        bot = self._build_bot()

        mock_mt5.TRADE_ACTION_DEAL = 1
        mock_mt5.ORDER_TYPE_BUY = 0
        mock_mt5.TRADE_RETCODE_DONE = 10009
        mock_mt5.TRADE_RETCODE_PLACED = 10008
        mock_mt5.TRADE_RETCODE_REJECT = 10006
        mock_mt5.TRADE_RETCODE_ERROR = 10011

        bot._send_trade_command.return_value = {
            "status": "PROCESSED",
            "correlation_id": "abc-1",
            "details": {
                "retcode": 10009,
                "order": 12345,
                "deal": 67890,
                "comment": "ok",
                "retcode_str": "TRADE_RETCODE_DONE",
            },
        }

        req = {
            "action": mock_mt5.TRADE_ACTION_DEAL,
            "type": mock_mt5.ORDER_TYPE_BUY,
            "volume": 0.01,
            "sl": 1.1,
            "tp": 1.2,
            "magic": 777,
            "comment": "test",
        }
        res = bot._dispatch_order("EURUSD", "FX", req, emergency=False)

        self.assertIsNotNone(res)
        self.assertEqual(10009, int(getattr(res, "retcode", -1)))
        self.assertEqual(12345, int(getattr(res, "order", -1)))
        self.assertEqual(67890, int(getattr(res, "deal", -1)))
        bot._send_trade_command.assert_called_once()

    @patch("BIN.safetybot.mt5")
    def test_dispatch_order_returns_none_on_missing_reply(self, mock_mt5):
        bot = self._build_bot()

        mock_mt5.TRADE_ACTION_DEAL = 1
        mock_mt5.ORDER_TYPE_BUY = 0

        bot._send_trade_command.return_value = None

        req = {
            "action": mock_mt5.TRADE_ACTION_DEAL,
            "type": mock_mt5.ORDER_TYPE_BUY,
            "volume": 0.01,
        }
        res = bot._dispatch_order("EURUSD", "FX", req, emergency=False)

        self.assertIsNone(res)

    @patch("BIN.safetybot.group_market_risk_state")
    @patch("BIN.safetybot.mt5")
    def test_dispatch_order_forces_entry_allowed_on_ambiguous_risk_state(self, mock_mt5, mock_group_risk):
        bot = self._build_bot()

        mock_mt5.TRADE_ACTION_DEAL = 1
        mock_mt5.ORDER_TYPE_BUY = 0
        mock_mt5.TRADE_RETCODE_DONE = 10009
        mock_mt5.TRADE_RETCODE_PLACED = 10008
        mock_mt5.TRADE_RETCODE_REJECT = 10006
        mock_mt5.TRADE_RETCODE_ERROR = 10011

        mock_group_risk.return_value = {
            "entry_allowed": False,
            "reason": "NONE",
            "friday_risk": False,
            "reopen_guard": False,
        }
        bot._send_trade_command.return_value = {
            "status": "PROCESSED",
            "correlation_id": "risk-ambiguous-1",
            "details": {
                "retcode": 10009,
                "order": 10,
                "deal": 11,
                "comment": "ok",
            },
        }

        req = {
            "action": mock_mt5.TRADE_ACTION_DEAL,
            "type": mock_mt5.ORDER_TYPE_BUY,
            "volume": 0.01,
            "sl": 1.1,
            "tp": 1.2,
            "magic": 777,
            "comment": "test",
        }
        res = bot._dispatch_order("US500.pro", "INDEX", req, emergency=False)

        self.assertIsNotNone(res)
        self.assertTrue(bot._send_trade_command.called)
        sent_kwargs = bot._send_trade_command.call_args.kwargs
        self.assertTrue(bool(sent_kwargs.get("risk_entry_allowed")))
        self.assertEqual("NONE", str(sent_kwargs.get("risk_reason")))

    @patch("BIN.safetybot.mt5")
    def test_dispatch_order_falls_back_for_position_close(self, mock_mt5):
        bot = self._build_bot()

        mock_mt5.TRADE_ACTION_DEAL = 1
        mock_mt5.ORDER_TYPE_BUY = 0

        fallback_result = object()
        bot.execution_engine.order_send.return_value = fallback_result

        req = {
            "action": mock_mt5.TRADE_ACTION_DEAL,
            "type": mock_mt5.ORDER_TYPE_BUY,
            "volume": 0.01,
            "position": 999,
        }
        res = bot._dispatch_order("EURUSD", "FX", req, emergency=False)

        self.assertIs(fallback_result, res)
        bot._send_trade_command.assert_not_called()
        bot.execution_engine.order_send.assert_called_once()

    @patch("BIN.safetybot.mt5")
    def test_standard_strategy_uses_dispatch_hook(self, mock_mt5):
        mock_mt5.TRADE_ACTION_DEAL = 1

        engine = MagicMock()
        hook = MagicMock(return_value="HOOK_RESULT")
        strategy = StandardStrategy(
            engine=engine,
            gov=MagicMock(),
            throttle=MagicMock(),
            db=MagicMock(),
            config=MagicMock(),
            risk_manager=MagicMock(),
            order_queue=None,
            dispatch_order_hook=hook,
        )

        req = {"action": mock_mt5.TRADE_ACTION_DEAL, "symbol": "EURUSD", "volume": 0.01}
        res = strategy._dispatch_order("EURUSD", "FX", req, emergency=False)

        self.assertEqual("HOOK_RESULT", res)
        hook.assert_called_once()
        engine.order_send.assert_not_called()

    def test_send_trade_command_bypasses_bridge_in_mql5_active_mode(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._trade_trigger_mode = MagicMock(return_value="MQL5_ACTIVE")

        reply = SafetyBot._send_trade_command(
            bot,
            signal="BUY",
            symbol="EURUSD.pro",
            volume=0.01,
            sl_price=1.0,
            tp_price=1.1,
            request_price=1.05,
            deviation_points=10,
            spread_at_decision_points=1.2,
            spread_unit="points",
            spread_provenance="TEST",
            estimated_entry_cost_components={},
            estimated_round_trip_cost={},
            cost_feasibility_shadow=True,
            net_cost_feasible=True,
            cost_gate_policy_mode="DIAGNOSTIC_ONLY",
            cost_gate_reason_code="NONE",
            magic=37630,
            comment="unit",
        )

        self.assertIsInstance(reply, dict)
        self.assertEqual("SKIPPED", str(reply.get("status")))
        self.assertEqual("MQL5_ACTIVE_BRIDGE_BYPASS", str(reply.get("retcode_str")))

    @patch("BIN.safetybot.mt5")
    def test_dispatch_order_handles_skipped_bridge_reply_as_neutral(self, mock_mt5):
        bot = self._build_bot()
        mock_mt5.TRADE_ACTION_DEAL = 1
        mock_mt5.ORDER_TYPE_BUY = 0
        mock_mt5.TRADE_RETCODE_TRADE_DISABLED = 10017

        bot._send_trade_command.return_value = {
            "status": "SKIPPED",
            "retcode": 10017,
            "details": {
                "retcode": 10017,
                "retcode_str": "MQL5_ACTIVE_BRIDGE_BYPASS",
                "comment": "Bridge bypass enabled in MQL5_ACTIVE mode.",
            },
        }

        req = {
            "action": mock_mt5.TRADE_ACTION_DEAL,
            "type": mock_mt5.ORDER_TYPE_BUY,
            "volume": 0.01,
        }
        res = bot._dispatch_order("EURUSD", "FX", req, emergency=False)
        self.assertIsNotNone(res)
        self.assertEqual(10017, int(getattr(res, "retcode", 0)))

    def test_runtime_scan_step_runs_scan_once_when_due(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._last_scan_suppressed_log_ts = 0.0
        bot._loop_scan_runs = 0
        bot._loop_scan_errors = 0
        bot.scan_once = MagicMock()
        bot._record_scan_duration = MagicMock()
        bot._record_section_duration = MagicMock()

        out_ts = bot._runtime_scan_step(
            now=100.0,
            last_scan_ts=0.0,
            scan_interval=10,
            heartbeat_fail_safe_active=False,
            heartbeat_failures=0,
            heartbeat_fail_safe_until=0.0,
            scan_suppressed_log_interval=60,
            scan_slow_warn_ms=1000,
        )

        self.assertEqual(100.0, out_ts)
        self.assertEqual(1, int(bot._loop_scan_runs))
        bot.scan_once.assert_called_once()
        bot._record_scan_duration.assert_called_once()
        bot._record_section_duration.assert_called_once()

    def test_runtime_scan_step_skips_when_heartbeat_failsafe_active(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._last_scan_suppressed_log_ts = 0.0
        bot._loop_scan_runs = 0
        bot._loop_scan_errors = 0
        bot.scan_once = MagicMock()
        bot._record_scan_duration = MagicMock()
        bot._record_section_duration = MagicMock()

        out_ts = bot._runtime_scan_step(
            now=100.0,
            last_scan_ts=0.0,
            scan_interval=10,
            heartbeat_fail_safe_active=True,
            heartbeat_failures=3,
            heartbeat_fail_safe_until=140.0,
            scan_suppressed_log_interval=60,
            scan_slow_warn_ms=1000,
        )

        self.assertEqual(100.0, out_ts)
        self.assertEqual(0, int(bot._loop_scan_runs))
        self.assertEqual(100.0, float(bot._last_scan_suppressed_log_ts))
        bot.scan_once.assert_not_called()
        bot._record_scan_duration.assert_not_called()
        bot._record_section_duration.assert_not_called()

    def test_runtime_trade_probe_step_sends_probe_and_updates_counters(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._send_trade_command = MagicMock(return_value={"status": "PROCESSED", "details": {"retcode_str": "OK"}})
        bot._record_bridge_diag = MagicMock()
        bot.zmq_bridge = MagicMock()
        bot.zmq_bridge.get_last_command_diag.return_value = {"status": "OK"}

        next_ts, next_count = bot._runtime_trade_probe_step(
            now=100.0,
            heartbeat_fail_safe_active=False,
            trade_probe_enabled=True,
            trade_probe_interval_sec=15,
            trade_probe_max_per_run=120,
            trade_probe_sent=0,
            last_trade_probe_ts=0.0,
            trade_probe_signal="BUY",
            trade_probe_symbol="__TRADE_PROBE_INVALID__",
            trade_probe_volume=0.01,
            trade_probe_deviation_points=10,
            trade_probe_comment="TRADE_PROBE_SAFE_NO_LIVE",
            trade_probe_group="FX",
        )

        self.assertEqual(100.0, next_ts)
        self.assertEqual(1, int(next_count))
        bot._send_trade_command.assert_called_once()
        bot._record_bridge_diag.assert_called_once()

    def test_runtime_trade_probe_step_returns_unchanged_when_disabled(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._send_trade_command = MagicMock()
        bot._record_bridge_diag = MagicMock()
        bot.zmq_bridge = MagicMock()

        next_ts, next_count = bot._runtime_trade_probe_step(
            now=100.0,
            heartbeat_fail_safe_active=False,
            trade_probe_enabled=False,
            trade_probe_interval_sec=15,
            trade_probe_max_per_run=120,
            trade_probe_sent=7,
            last_trade_probe_ts=90.0,
            trade_probe_signal="BUY",
            trade_probe_symbol="__TRADE_PROBE_INVALID__",
            trade_probe_volume=0.01,
            trade_probe_deviation_points=10,
            trade_probe_comment="TRADE_PROBE_SAFE_NO_LIVE",
            trade_probe_group="FX",
        )

        self.assertEqual(90.0, next_ts)
        self.assertEqual(7, int(next_count))
        bot._send_trade_command.assert_not_called()
        bot._record_bridge_diag.assert_not_called()

    def test_runtime_heartbeat_step_returns_unchanged_when_not_due(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._record_bridge_diag = MagicMock()
        bot.zmq_bridge = MagicMock()
        bot._last_heartbeat_fail_log_ts = 0.0
        bot._loop_heartbeat_recoveries = 0
        bot._loop_heartbeat_fail_total = 0
        bot.incident_journal = None

        out = bot._runtime_heartbeat_step(
            now=100.0,
            loop_id=1,
            last_heartbeat_ts=95.0,
            last_market_data_ts=99.0,
            heartbeat_interval=15,
            heartbeat_fail_safe_active=False,
            heartbeat_failures=0,
            heartbeat_fail_safe_until=0.0,
            heartbeat_fail_threshold=3,
            heartbeat_fail_safe_cooldown=30,
            heartbeat_fail_log_interval=15,
            heartbeat_timeout_budget_ms=800,
            heartbeat_retries_budget=1,
            heartbeat_queue_lock_timeout_ms=25,
            heartbeat_worker_stale_sec=120,
        )

        self.assertEqual((95.0, 0, False, 0.0), out)
        bot.zmq_bridge.send_command.assert_not_called()
        bot._record_bridge_diag.assert_not_called()

    def test_runtime_heartbeat_step_success_clears_failures(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._record_bridge_diag = MagicMock()
        bot.zmq_bridge = MagicMock()
        bot._last_heartbeat_fail_log_ts = 0.0
        bot._loop_heartbeat_recoveries = 0
        bot._loop_heartbeat_fail_total = 0
        bot.incident_journal = None

        reply = {"action": "HEARTBEAT_REPLY", "status": "OK"}
        reply["response_hash"] = build_response_hash(reply)
        bot.zmq_bridge.send_command.return_value = reply
        bot.zmq_bridge.get_last_command_diag.return_value = {}

        out = bot._runtime_heartbeat_step(
            now=100.0,
            loop_id=1,
            last_heartbeat_ts=0.0,
            last_market_data_ts=95.0,
            heartbeat_interval=15,
            heartbeat_fail_safe_active=True,
            heartbeat_failures=2,
            heartbeat_fail_safe_until=0.0,
            heartbeat_fail_threshold=3,
            heartbeat_fail_safe_cooldown=30,
            heartbeat_fail_log_interval=15,
            heartbeat_timeout_budget_ms=800,
            heartbeat_retries_budget=1,
            heartbeat_queue_lock_timeout_ms=25,
            heartbeat_worker_stale_sec=120,
        )

        self.assertEqual((100.0, 0, False, 0.0), out)
        self.assertEqual(1, int(bot._loop_heartbeat_recoveries))
        bot.zmq_bridge.send_command.assert_called_once()
        bot._record_bridge_diag.assert_called_once()

    def test_runtime_heartbeat_step_fail_triggers_failsafe(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._record_bridge_diag = MagicMock()
        bot.zmq_bridge = MagicMock()
        bot._last_heartbeat_fail_log_ts = 0.0
        bot._loop_heartbeat_recoveries = 0
        bot._loop_heartbeat_fail_total = 0
        bot.incident_journal = None

        bot.zmq_bridge.send_command.return_value = None
        bot.zmq_bridge.get_last_command_diag.return_value = {}

        out = bot._runtime_heartbeat_step(
            now=100.0,
            loop_id=1,
            last_heartbeat_ts=0.0,
            last_market_data_ts=95.0,
            heartbeat_interval=15,
            heartbeat_fail_safe_active=False,
            heartbeat_failures=1,
            heartbeat_fail_safe_until=0.0,
            heartbeat_fail_threshold=2,
            heartbeat_fail_safe_cooldown=30,
            heartbeat_fail_log_interval=15,
            heartbeat_timeout_budget_ms=800,
            heartbeat_retries_budget=1,
            heartbeat_queue_lock_timeout_ms=25,
            heartbeat_worker_stale_sec=120,
        )

        self.assertEqual((100.0, 2, True, 130.0), out)
        self.assertEqual(1, int(bot._loop_heartbeat_fail_total))

    def test_runtime_heartbeat_step_from_state_maps_cfg_and_state(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._runtime_heartbeat_step = MagicMock(return_value=(10.0, 1, False, 0.0))
        loop_cfg = SimpleNamespace(
            heartbeat_interval=15,
            heartbeat_fail_threshold=3,
            heartbeat_fail_safe_cooldown=30,
            heartbeat_fail_log_interval=15,
            heartbeat_timeout_budget_ms=800,
            heartbeat_retries_budget=1,
            heartbeat_queue_lock_timeout_ms=25,
            heartbeat_worker_stale_sec=120,
        )
        loop_state = {
            "loop_id": 7,
            "last_heartbeat_ts": 1.0,
            "last_market_data_ts": 2.0,
            "heartbeat_fail_safe_active": True,
            "heartbeat_failures": 5,
            "heartbeat_fail_safe_until": 3.0,
        }

        out = bot._runtime_heartbeat_step_from_state(now=9.0, loop_cfg=loop_cfg, loop_state=loop_state)
        self.assertEqual((10.0, 1, False, 0.0), out)
        bot._runtime_heartbeat_step.assert_called_once()

    def test_runtime_ingest_step_updates_timestamp_on_market_data(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot.zmq_bridge = MagicMock()
        bot.zmq_bridge.receive_data.return_value = {"type": "TICK", "symbol": "EURUSD.pro"}
        bot._handle_market_data = MagicMock()
        bot._record_section_duration = MagicMock()

        market_data, ts = bot._runtime_ingest_step(now=100.0, last_market_data_ts=0.0, receive_timeout_ms=100)

        self.assertIsInstance(market_data, dict)
        self.assertEqual(100.0, float(ts))
        bot._handle_market_data.assert_called_once()
        bot._record_section_duration.assert_called_once()

    def test_runtime_ingest_step_keeps_timestamp_when_no_data(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot.zmq_bridge = MagicMock()
        bot.zmq_bridge.receive_data.return_value = None
        bot._handle_market_data = MagicMock()
        bot._record_section_duration = MagicMock()

        market_data, ts = bot._runtime_ingest_step(now=100.0, last_market_data_ts=50.0, receive_timeout_ms=100)

        self.assertIsNone(market_data)
        self.assertEqual(50.0, float(ts))
        bot._handle_market_data.assert_not_called()
        bot._record_section_duration.assert_called_once()

    def test_runtime_loop_step_updates_state_and_calls_substeps(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._runtime_ingest_step = MagicMock(return_value=({"type": "TICK"}, 200.0))
        bot._runtime_heartbeat_step = MagicMock(return_value=(201.0, 2, True, 230.0))
        bot._runtime_trade_probe_step = MagicMock(return_value=(202.0, 3))
        bot._runtime_scan_step = MagicMock(return_value=203.0)
        bot._runtime_maintenance_step = MagicMock(return_value=True)
        bot._runtime_idle_step = MagicMock()

        loop_cfg = SimpleNamespace(
            heartbeat_interval=15,
            heartbeat_fail_threshold=3,
            heartbeat_fail_safe_cooldown=30,
            heartbeat_fail_log_interval=15,
            heartbeat_timeout_budget_ms=800,
            heartbeat_retries_budget=1,
            heartbeat_queue_lock_timeout_ms=25,
            heartbeat_worker_stale_sec=120,
            trade_probe_enabled=True,
            trade_probe_interval_sec=15,
            trade_probe_max_per_run=120,
            trade_probe_signal="BUY",
            trade_probe_symbol="__TRADE_PROBE_INVALID__",
            trade_probe_volume=0.01,
            trade_probe_deviation_points=10,
            trade_probe_comment="TRADE_PROBE_SAFE_NO_LIVE",
            trade_probe_group="FX",
            scan_interval=60,
            scan_suppressed_log_interval=60,
            scan_slow_warn_ms=1500,
            run_loop_idle_sleep=0.01,
        )
        loop_state = {
            "last_scan_ts": 0.0,
            "last_heartbeat_ts": 0.0,
            "last_market_data_ts": 0.0,
            "heartbeat_failures": 0,
            "heartbeat_fail_safe_active": False,
            "heartbeat_fail_safe_until": 0.0,
            "last_trade_probe_ts": 0.0,
            "trade_probe_sent": 0,
            "loop_id": 0,
        }

        with patch("BIN.safetybot.time.time", return_value=200.0):
            ok = bot._runtime_loop_step(loop_cfg=loop_cfg, loop_state=loop_state)

        self.assertTrue(ok)
        self.assertEqual(1, int(loop_state["loop_id"]))
        self.assertEqual(200.0, float(loop_state["last_market_data_ts"]))
        self.assertEqual(201.0, float(loop_state["last_heartbeat_ts"]))
        self.assertEqual(2, int(loop_state["heartbeat_failures"]))
        self.assertTrue(bool(loop_state["heartbeat_fail_safe_active"]))
        self.assertEqual(230.0, float(loop_state["heartbeat_fail_safe_until"]))
        self.assertEqual(202.0, float(loop_state["last_trade_probe_ts"]))
        self.assertEqual(3, int(loop_state["trade_probe_sent"]))
        self.assertEqual(203.0, float(loop_state["last_scan_ts"]))
        bot._runtime_maintenance_step.assert_called_once()
        bot._runtime_idle_step.assert_called_once()

    def test_runtime_loop_step_stops_on_maintenance_false(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._runtime_ingest_step = MagicMock(return_value=(None, 50.0))
        bot._runtime_heartbeat_step = MagicMock(return_value=(51.0, 0, False, 0.0))
        bot._runtime_trade_probe_step = MagicMock(return_value=(52.0, 1))
        bot._runtime_scan_step = MagicMock(return_value=53.0)
        bot._runtime_maintenance_step = MagicMock(return_value=False)
        bot._runtime_idle_step = MagicMock()

        loop_cfg = SimpleNamespace(
            heartbeat_interval=15,
            heartbeat_fail_threshold=3,
            heartbeat_fail_safe_cooldown=30,
            heartbeat_fail_log_interval=15,
            heartbeat_timeout_budget_ms=800,
            heartbeat_retries_budget=1,
            heartbeat_queue_lock_timeout_ms=25,
            heartbeat_worker_stale_sec=120,
            trade_probe_enabled=False,
            trade_probe_interval_sec=15,
            trade_probe_max_per_run=120,
            trade_probe_signal="BUY",
            trade_probe_symbol="__TRADE_PROBE_INVALID__",
            trade_probe_volume=0.01,
            trade_probe_deviation_points=10,
            trade_probe_comment="TRADE_PROBE_SAFE_NO_LIVE",
            trade_probe_group="FX",
            scan_interval=60,
            scan_suppressed_log_interval=60,
            scan_slow_warn_ms=1500,
            run_loop_idle_sleep=0.01,
        )
        loop_state = {
            "last_scan_ts": 0.0,
            "last_heartbeat_ts": 0.0,
            "last_market_data_ts": 0.0,
            "heartbeat_failures": 0,
            "heartbeat_fail_safe_active": False,
            "heartbeat_fail_safe_until": 0.0,
            "last_trade_probe_ts": 0.0,
            "trade_probe_sent": 0,
            "loop_id": 0,
        }

        with patch("BIN.safetybot.time.time", return_value=50.0):
            ok = bot._runtime_loop_step(loop_cfg=loop_cfg, loop_state=loop_state)

        self.assertFalse(ok)
        bot._runtime_idle_step.assert_not_called()

    def test_runtime_refresh_control_plane_state_runs_cached_refreshes_on_cadence(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._runtime_cached_tw_ctx = {"phase": "ACTIVE", "window_id": "TEST"}
        bot._runtime_cached_day_state = {"day_ny": "2026-03-10", "utc_day": "2026-03-10"}
        bot._runtime_cached_group_arb = {}
        bot._runtime_cached_group_risk = {}
        bot._last_group_policy_refresh_ts = 0.0
        bot._last_live_module_refresh_ts = 0.0
        bot._last_no_live_drift_refresh_ts = 0.0
        bot._last_cost_guard_refresh_ts = 0.0
        bot._last_time_anchor_refresh_ts = 0.0
        bot._runtime_refresh_meta_advisory_cache = MagicMock()
        bot._runtime_refresh_group_policy_cache = MagicMock()
        bot._runtime_refresh_global_guard_cache = MagicMock()
        bot._refresh_live_module_states = MagicMock()
        bot._refresh_no_live_drift_check = MagicMock()
        bot._refresh_cost_guard_auto_relax_state = MagicMock()
        bot._time_anchor_sync_if_due = MagicMock()
        bot._emit_runtime_metrics = MagicMock()

        scan_prev = getattr(CFG, "scan_interval_sec", 30)
        CFG.scan_interval_sec = 30
        try:
            with patch("BIN.safetybot.time.time", return_value=100.0):
                bot._runtime_refresh_control_plane_state()
        finally:
            CFG.scan_interval_sec = scan_prev

        bot._runtime_refresh_meta_advisory_cache.assert_called_once_with()
        bot._runtime_refresh_group_policy_cache.assert_called_once_with()
        bot._runtime_refresh_global_guard_cache.assert_called_once_with()
        bot._refresh_live_module_states.assert_called_once_with(
            tw_ctx=bot._runtime_cached_tw_ctx,
            st=bot._runtime_cached_day_state,
        )
        bot._refresh_no_live_drift_check.assert_called_once_with(
            tw_ctx=bot._runtime_cached_tw_ctx,
        )
        bot._refresh_cost_guard_auto_relax_state.assert_called_once_with(
            tw_ctx=bot._runtime_cached_tw_ctx,
        )
        bot._time_anchor_sync_if_due.assert_called_once_with(bot._runtime_cached_day_state)
        bot._emit_runtime_metrics.assert_called_once_with(
            bot._runtime_cached_day_state,
            eco_active=False,
            warn_active=False,
        )

    def test_runtime_refresh_control_plane_state_skips_before_next_cadence(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._runtime_cached_tw_ctx = {"phase": "ACTIVE", "window_id": "TEST"}
        bot._runtime_cached_day_state = {"day_ny": "2026-03-10", "utc_day": "2026-03-10"}
        bot._runtime_cached_group_arb = {"FX": {"priority_factor": 1.0}}
        bot._runtime_cached_group_risk = {"FX": {"entry_allowed": True}}
        bot._last_group_policy_refresh_ts = 95.0
        bot._last_live_module_refresh_ts = 95.0
        bot._last_no_live_drift_refresh_ts = 95.0
        bot._last_cost_guard_refresh_ts = 95.0
        bot._last_time_anchor_refresh_ts = 95.0
        bot._runtime_refresh_meta_advisory_cache = MagicMock()
        bot._runtime_refresh_group_policy_cache = MagicMock()
        bot._runtime_refresh_global_guard_cache = MagicMock()
        bot._refresh_live_module_states = MagicMock()
        bot._refresh_no_live_drift_check = MagicMock()
        bot._refresh_cost_guard_auto_relax_state = MagicMock()
        bot._time_anchor_sync_if_due = MagicMock()
        bot._emit_runtime_metrics = MagicMock()

        scan_prev = getattr(CFG, "scan_interval_sec", 30)
        CFG.scan_interval_sec = 30
        try:
            with patch("BIN.safetybot.time.time", return_value=100.0):
                bot._runtime_refresh_control_plane_state()
        finally:
            CFG.scan_interval_sec = scan_prev

        bot._runtime_refresh_meta_advisory_cache.assert_called_once_with()
        bot._runtime_refresh_group_policy_cache.assert_called_once_with()
        bot._runtime_refresh_global_guard_cache.assert_called_once_with()
        bot._refresh_live_module_states.assert_not_called()
        bot._refresh_no_live_drift_check.assert_not_called()
        bot._refresh_cost_guard_auto_relax_state.assert_not_called()
        bot._time_anchor_sync_if_due.assert_not_called()
        bot._emit_runtime_metrics.assert_called_once_with(
            bot._runtime_cached_day_state,
            eco_active=False,
            warn_active=False,
        )

    def test_runtime_refresh_meta_advisory_cache_loads_runtime_meta_once_per_cadence(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot.meta_dir = Path("C:/meta")
        bot._last_meta_advisory_refresh_ts = 0.0

        scan_prev = getattr(CFG, "scan_interval_sec", 30)
        unified_prev = getattr(CFG, "unified_learning_runtime_enabled", True)
        CFG.scan_interval_sec = 30
        CFG.unified_learning_runtime_enabled = True
        try:
            with (
                patch("BIN.safetybot.time.time", return_value=100.0),
                patch.object(bot, "_read_learner_qa_light", return_value="YELLOW") as qa_mock,
                patch("BIN.safetybot.load_unified_learning_advice", return_value={"runtime_light": {"EURUSD": 1}}) as unified_mock,
                patch("BIN.safetybot.load_verdict", return_value={"light": "GREEN"}) as verdict_mock,
                patch("BIN.safetybot.load_scout_advice", return_value={"preferred_symbol": "EURUSD"}) as scout_mock,
            ):
                bot._runtime_refresh_meta_advisory_cache()
        finally:
            CFG.scan_interval_sec = scan_prev
            CFG.unified_learning_runtime_enabled = unified_prev

        qa_mock.assert_called_once_with()
        unified_mock.assert_called_once_with(bot.meta_dir)
        verdict_mock.assert_called_once_with(bot.meta_dir)
        scout_mock.assert_called_once_with(bot.meta_dir)
        self.assertEqual(bot._runtime_cached_learner_qa_light, "YELLOW")
        self.assertEqual(bot._runtime_cached_verdict, {"light": "GREEN"})
        self.assertEqual(bot._runtime_cached_scout_advice, {"preferred_symbol": "EURUSD"})
        self.assertTrue(bot._runtime_meta_advisory_cache_ready)
        self.assertEqual(bot._last_meta_advisory_refresh_ts, 100.0)

    def test_runtime_refresh_meta_advisory_cache_skips_when_fresh(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot.meta_dir = Path("C:/meta")
        bot._last_meta_advisory_refresh_ts = 95.0

        scan_prev = getattr(CFG, "scan_interval_sec", 30)
        CFG.scan_interval_sec = 30
        try:
            with (
                patch("BIN.safetybot.time.time", return_value=100.0),
                patch.object(bot, "_read_learner_qa_light") as qa_mock,
                patch("BIN.safetybot.load_unified_learning_advice") as unified_mock,
                patch("BIN.safetybot.load_verdict") as verdict_mock,
                patch("BIN.safetybot.load_scout_advice") as scout_mock,
            ):
                bot._runtime_refresh_meta_advisory_cache()
        finally:
            CFG.scan_interval_sec = scan_prev

        qa_mock.assert_not_called()
        unified_mock.assert_not_called()
        verdict_mock.assert_not_called()
        scout_mock.assert_not_called()

    def test_runtime_refresh_group_policy_cache_builds_snapshot_when_missing(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._runtime_cached_group_arb = {}
        bot._runtime_cached_group_risk = {}
        bot._last_group_policy_refresh_ts = 0.0
        bot._compute_group_policy_snapshot = MagicMock(return_value=({"FX": {"priority_factor": 1.0}}, {"FX": {"entry_allowed": True}}))
        bot._cache_group_policy_snapshot = MagicMock()
        bot._emit_group_policy_snapshot_log = MagicMock()

        scan_prev = getattr(CFG, "scan_interval_sec", 30)
        CFG.scan_interval_sec = 30
        try:
            fake_now = 100.0
            with patch("BIN.safetybot.time.time", return_value=fake_now), patch("BIN.safetybot.now_utc") as now_utc_mock:
                now_arb = dt.datetime(2026, 3, 10, 21, 0, 0, tzinfo=dt.timezone.utc)
                now_utc_mock.return_value = now_arb
                bot._runtime_refresh_group_policy_cache()
        finally:
            CFG.scan_interval_sec = scan_prev

        bot._compute_group_policy_snapshot.assert_called_once()
        bot._cache_group_policy_snapshot.assert_called_once()
        bot._emit_group_policy_snapshot_log.assert_called_once_with(group_arb={"FX": {"priority_factor": 1.0}})
        self.assertEqual(bot._last_group_policy_refresh_ts, fake_now)

    def test_runtime_refresh_group_policy_cache_skips_when_cache_is_fresh(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._runtime_cached_group_arb = {"FX": {"priority_factor": 1.0}}
        bot._runtime_cached_group_risk = {"FX": {"entry_allowed": True}}
        bot._last_group_policy_refresh_ts = 95.0
        bot._compute_group_policy_snapshot = MagicMock()
        bot._cache_group_policy_snapshot = MagicMock()
        bot._emit_group_policy_snapshot_log = MagicMock()

        scan_prev = getattr(CFG, "scan_interval_sec", 30)
        CFG.scan_interval_sec = 30
        try:
            with patch("BIN.safetybot.time.time", return_value=100.0):
                bot._runtime_refresh_group_policy_cache()
        finally:
            CFG.scan_interval_sec = scan_prev

        bot._compute_group_policy_snapshot.assert_not_called()
        bot._cache_group_policy_snapshot.assert_not_called()
        bot._emit_group_policy_snapshot_log.assert_not_called()

    def test_runtime_refresh_global_guard_cache_builds_signals_when_missing(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._runtime_cached_self_heal_signal = None
        bot._runtime_cached_canary_signal = None
        bot._runtime_cached_drift_signal = None
        bot._runtime_global_guard_cache_ready = False
        bot._last_global_guard_refresh_ts = 0.0
        bot._evaluate_self_heal = MagicMock(
            return_value=SelfHealSignal(False, ("OK",), 0, 0, 0, 0, 0.0, ())
        )
        bot._evaluate_canary_rollout = MagicMock(
            return_value=CanarySignal(False, False, False, False, 1_000_000, ("NORMAL",), 0, 0, 0.0, 0, 0)
        )
        bot._evaluate_drift = MagicMock(
            return_value=DriftSignal(False, ("DRIFT_OK",), 0, 0.0, 0.0, 0.0, 0.0, 0)
        )

        scan_prev = getattr(CFG, "scan_interval_sec", 30)
        CFG.scan_interval_sec = 30
        try:
            with patch("BIN.safetybot.time.time", return_value=100.0):
                bot._runtime_refresh_global_guard_cache()
        finally:
            CFG.scan_interval_sec = scan_prev

        bot._evaluate_self_heal.assert_called_once_with()
        bot._evaluate_canary_rollout.assert_called_once_with()
        bot._evaluate_drift.assert_called_once_with()
        self.assertTrue(bot._runtime_global_guard_cache_ready)
        self.assertEqual(bot._last_global_guard_refresh_ts, 100.0)

    def test_runtime_refresh_global_guard_cache_skips_when_fresh(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._runtime_cached_self_heal_signal = SelfHealSignal(False, ("OK",), 0, 0, 0, 0, 0.0, ())
        bot._runtime_cached_canary_signal = CanarySignal(
            False, False, False, False, 1_000_000, ("NORMAL",), 0, 0, 0.0, 0, 0
        )
        bot._runtime_cached_drift_signal = DriftSignal(False, ("DRIFT_OK",), 0, 0.0, 0.0, 0.0, 0.0, 0)
        bot._runtime_global_guard_cache_ready = True
        bot._last_global_guard_refresh_ts = 95.0
        bot._runtime_get_cached_global_guard_state = MagicMock(
            return_value=(
                True,
                SelfHealSignal(False, ("OK",), 0, 0, 0, 0, 0.0, ()),
                CanarySignal(False, False, False, False, 1_000_000, ("NORMAL",), 0, 0, 0.0, 0, 0),
                DriftSignal(False, ("DRIFT_OK",), 0, 0.0, 0.0, 0.0, 0.0, 0),
            )
        )
        bot._evaluate_self_heal = MagicMock()
        bot._evaluate_canary_rollout = MagicMock()
        bot._evaluate_drift = MagicMock()

        scan_prev = getattr(CFG, "scan_interval_sec", 30)
        CFG.scan_interval_sec = 30
        try:
            with patch("BIN.safetybot.time.time", return_value=100.0):
                bot._runtime_refresh_global_guard_cache()
        finally:
            CFG.scan_interval_sec = scan_prev

        bot._evaluate_self_heal.assert_not_called()
        bot._evaluate_canary_rollout.assert_not_called()
        bot._evaluate_drift.assert_not_called()

    def test_handle_market_data_dispatches_account(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._handle_account_snapshot = MagicMock()
        bot._handle_tick_snapshot = MagicMock()
        bot._handle_bar_snapshot = MagicMock()

        with patch("BIN.safetybot.time.time", return_value=123.0):
            bot._handle_market_data({"type": "ACCOUNT", "balance": 1.0})

        bot._handle_account_snapshot.assert_called_once()
        bot._handle_tick_snapshot.assert_not_called()
        bot._handle_bar_snapshot.assert_not_called()

    def test_handle_market_data_dispatches_tick_and_bar(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._handle_account_snapshot = MagicMock()
        bot._handle_tick_snapshot = MagicMock()
        bot._handle_bar_snapshot = MagicMock()

        with patch("BIN.safetybot.time.time", return_value=123.0):
            bot._handle_market_data({"type": "TICK", "symbol": "EURUSD.pro"})
            bot._handle_market_data({"type": "BAR", "symbol": "EURUSD.pro"})

        bot._handle_account_snapshot.assert_not_called()
        bot._handle_tick_snapshot.assert_called_once()
        bot._handle_bar_snapshot.assert_called_once()

    def test_handle_market_data_rejects_schema_mismatch(self):
        with patch.object(SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = SafetyBot()
        bot._handle_account_snapshot = MagicMock()
        bot._handle_tick_snapshot = MagicMock()
        bot._handle_bar_snapshot = MagicMock()

        bot._handle_market_data({"type": "TICK", "symbol": "EURUSD.pro", "schema_version": "2.0"})

        bot._handle_account_snapshot.assert_not_called()
        bot._handle_tick_snapshot.assert_not_called()
        bot._handle_bar_snapshot.assert_not_called()


if __name__ == "__main__":
    unittest.main()
