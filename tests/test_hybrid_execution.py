import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from BIN.safetybot import SafetyBot, StandardStrategy


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


if __name__ == "__main__":
    unittest.main()
