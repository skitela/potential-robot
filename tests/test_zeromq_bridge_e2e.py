import json
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from BIN.zeromq_bridge import PROTOCOL_VERSION, ZMQBridge


class TestZMQBridgeE2E(unittest.TestCase):
    def _build_bridge(self, retries: int = 3) -> ZMQBridge:
        bridge = ZMQBridge(req_retries=retries, req_timeout_ms=5, audit_log_path=None)
        try:
            bridge.context.term()
        except Exception:
            pass
        bridge.context = MagicMock()
        bridge.req_socket = MagicMock()
        return bridge

    def test_send_command_success_with_matching_correlation_id(self):
        bridge = self._build_bridge(retries=1)
        bridge.req_socket.poll.side_effect = [True]
        bridge.req_socket.recv_string.side_effect = [
            json.dumps(
                {
                    "status": "PROCESSED",
                    "correlation_id": "msg-1",
                    "details": {"retcode": 10009, "order": 123, "deal": 456},
                }
            )
        ]

        result = bridge.send_command({"action": "TRADE", "msg_id": "msg-1", "payload": {"symbol": "EURUSD"}})

        self.assertIsInstance(result, dict)
        self.assertEqual("PROCESSED", result.get("status"))
        self.assertEqual("msg-1", result.get("correlation_id"))
        self.assertEqual(1, bridge.req_socket.send_string.call_count)

        sent_raw = bridge.req_socket.send_string.call_args.args[0]
        sent_obj = json.loads(sent_raw)
        self.assertEqual("msg-1", sent_obj.get("msg_id"))
        self.assertEqual(PROTOCOL_VERSION, sent_obj.get("__v"))

    def test_send_command_timeout_retries_and_fails(self):
        bridge = self._build_bridge(retries=3)
        bridge.req_socket.poll.side_effect = [False, False, False]
        bridge._reconnect_req_socket = MagicMock()

        result = bridge.send_command({"action": "TRADE", "msg_id": "timeout-1", "payload": {"symbol": "EURUSD"}})

        self.assertIsNone(result)
        self.assertEqual(3, bridge.req_socket.send_string.call_count)
        self.assertEqual(3, bridge._reconnect_req_socket.call_count)

    def test_send_command_desync_wrong_correlation_id(self):
        bridge = self._build_bridge(retries=2)
        bridge.req_socket.poll.side_effect = [True, True]
        bridge.req_socket.recv_string.side_effect = [
            json.dumps({"status": "PROCESSED", "correlation_id": "wrong-1", "details": {"retcode": 10009}}),
            json.dumps({"status": "PROCESSED", "correlation_id": "wrong-2", "details": {"retcode": 10009}}),
        ]
        bridge._reconnect_req_socket = MagicMock()

        result = bridge.send_command({"action": "TRADE", "msg_id": "expected-1", "payload": {"symbol": "EURUSD"}})

        self.assertIsNone(result)
        self.assertEqual(2, bridge.req_socket.send_string.call_count)
        self.assertEqual(0, bridge._reconnect_req_socket.call_count)


if __name__ == "__main__":
    unittest.main()
