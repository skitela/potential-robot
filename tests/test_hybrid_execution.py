import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from BIN.safetybot import SafetyBot


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


if __name__ == "__main__":
    unittest.main()
