import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from BIN.safetybot import SafetyBot, StandardStrategy, build_response_hash


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


if __name__ == "__main__":
    unittest.main()
