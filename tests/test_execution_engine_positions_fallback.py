import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, call, patch

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from BIN.safetybot import ExecutionEngine


def _cfg() -> dict:
    return {
        "MT5_LOGIN": "37360",
        "MT5_PASSWORD": "x",
        "MT5_SERVER": "x",
        "MT5_PATH": r"C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    }


class TestExecutionEnginePositionsFallback(unittest.TestCase):
    @patch("BIN.safetybot.mt5")
    def test_positions_get_recovers_on_emergency_retry_after_none(self, mock_mt5):
        gov = MagicMock()
        gov.consume = MagicMock(side_effect=[True, True])
        engine = ExecutionEngine(_cfg(), gov)

        mock_mt5.positions_get.side_effect = [None, ("p1",)]
        mock_mt5.last_error.return_value = (-10004, "no ipc")

        got = engine.positions_get(emergency=False)

        self.assertEqual(("p1",), got)
        self.assertEqual(2, mock_mt5.positions_get.call_count)
        self.assertEqual(
            [
                call("SYS", "__POSITIONS__", "positions_get", 1, emergency=False),
                call("SYS", "__POSITIONS__", "positions_get", 1, emergency=True),
            ],
            gov.consume.call_args_list,
        )

    @patch("BIN.safetybot.mt5")
    def test_positions_get_returns_cache_when_budget_blocked(self, mock_mt5):
        gov = MagicMock()
        gov.consume = MagicMock(return_value=False)
        engine = ExecutionEngine(_cfg(), gov)
        engine._positions_cache = ("cached-pos",)

        got = engine.positions_get(emergency=False)

        self.assertEqual(("cached-pos",), got)
        mock_mt5.positions_get.assert_not_called()

    @patch("BIN.safetybot.mt5")
    def test_positions_get_returns_cache_when_mt5_none(self, mock_mt5):
        gov = MagicMock()
        gov.consume = MagicMock(side_effect=[True, True, True])
        engine = ExecutionEngine(_cfg(), gov)

        mock_mt5.positions_get.side_effect = [("first",), None, None]
        mock_mt5.last_error.return_value = (-10004, "no ipc")

        first = engine.positions_get(emergency=False)
        second = engine.positions_get(emergency=False)

        self.assertEqual(("first",), first)
        self.assertEqual(("first",), second)
        self.assertEqual(3, mock_mt5.positions_get.call_count)

    @patch("BIN.safetybot.mt5")
    def test_orders_get_returns_cache_when_budget_blocked(self, mock_mt5):
        gov = MagicMock()
        gov.consume = MagicMock(return_value=False)
        engine = ExecutionEngine(_cfg(), gov)
        engine._orders_cache = ("cached-ord",)

        got = engine.orders_get(emergency=False)

        self.assertEqual(("cached-ord",), got)
        mock_mt5.orders_get.assert_not_called()


if __name__ == "__main__":
    unittest.main()
