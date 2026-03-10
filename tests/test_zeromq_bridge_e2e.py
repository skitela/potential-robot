import json
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock
import zmq

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from BIN.zeromq_bridge import PROTOCOL_VERSION, ZMQBridge, build_request_hash, build_response_hash


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
        command = {"action": "TRADE", "msg_id": "msg-1", "payload": {"symbol": "EURUSD"}}
        request_hash = build_request_hash(command)
        reply = {
            "status": "PROCESSED",
            "correlation_id": "msg-1",
            "action": "TRADE_REPLY",
            "request_hash": request_hash,
            "details": {"retcode": 10009, "order": 123, "deal": 456},
            "error": "",
        }
        reply["response_hash"] = build_response_hash(reply)

        bridge.req_socket.poll.side_effect = [True]
        bridge.req_socket.recv_string.side_effect = [json.dumps(reply)]

        result = bridge.send_command(command)

        self.assertIsInstance(result, dict)
        self.assertEqual("PROCESSED", result.get("status"))
        self.assertEqual("msg-1", result.get("correlation_id"))
        self.assertEqual(request_hash, result.get("request_hash"))
        self.assertIsInstance(result.get("__bridge_diag"), dict)
        self.assertEqual("OK", (result.get("__bridge_diag") or {}).get("status"))
        self.assertIn("bridge_send_ms", result.get("__bridge_diag") or {})
        self.assertIn("bridge_wait_ms", result.get("__bridge_diag") or {})
        self.assertIn("bridge_parse_ms", result.get("__bridge_diag") or {})
        self.assertEqual(1, bridge.req_socket.send_string.call_count)

        sent_raw = bridge.req_socket.send_string.call_args.args[0]
        sent_obj = json.loads(sent_raw)
        self.assertEqual("msg-1", sent_obj.get("msg_id"))
        self.assertEqual(PROTOCOL_VERSION, sent_obj.get("__v"))
        self.assertEqual(request_hash, sent_obj.get("request_hash"))

    def test_send_command_timeout_retries_and_fails(self):
        bridge = self._build_bridge(retries=3)
        bridge.req_socket.poll.side_effect = [False, False, False]
        bridge._reconnect_req_socket = MagicMock()

        result = bridge.send_command({"action": "TRADE", "msg_id": "timeout-1", "payload": {"symbol": "EURUSD"}})

        self.assertIsNone(result)
        self.assertEqual(3, bridge.req_socket.send_string.call_count)
        self.assertEqual(3, bridge._reconnect_req_socket.call_count)
        diag = bridge.get_last_command_diag()
        self.assertEqual("FAILED", diag.get("status"))
        self.assertEqual("TIMEOUT_NO_RESPONSE", diag.get("bridge_timeout_reason"))

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

    def test_send_command_rejects_mismatched_response_hash(self):
        bridge = self._build_bridge(retries=2)
        bridge.req_socket.poll.side_effect = [True, True]
        command = {"action": "TRADE", "msg_id": "msg-2", "payload": {"symbol": "EURUSD"}}
        request_hash = build_request_hash(command)
        bad_reply = {
            "status": "PROCESSED",
            "correlation_id": "msg-2",
            "action": "TRADE_REPLY",
            "request_hash": request_hash,
            "details": {"retcode": 10009, "order": 1, "deal": 2},
            "error": "",
            "response_hash": "DEADBEEF",
        }
        bridge.req_socket.recv_string.side_effect = [json.dumps(bad_reply), json.dumps(bad_reply)]

        result = bridge.send_command(command)

        self.assertIsNone(result)
        self.assertEqual(2, bridge.req_socket.send_string.call_count)

    def test_send_command_skips_when_queue_lock_busy(self):
        bridge = self._build_bridge(retries=1)
        bridge._command_lock.acquire()
        try:
            result = bridge.send_command(
                {"action": "HEARTBEAT", "msg_id": "hb-lock-busy"},
                queue_lock_timeout_ms=1,
            )
        finally:
            bridge._command_lock.release()

        self.assertIsNone(result)
        self.assertEqual(0, bridge.req_socket.send_string.call_count)
        diag = bridge.get_last_command_diag()
        self.assertEqual("SKIPPED", diag.get("status"))
        self.assertEqual("QUEUE_LOCK_TIMEOUT", diag.get("bridge_timeout_reason"))

    def test_send_command_timeout_can_skip_reconnect(self):
        bridge = self._build_bridge(retries=2)
        bridge.req_socket.poll.side_effect = [False, False]
        bridge._reconnect_req_socket = MagicMock()

        result = bridge.send_command(
            {"action": "HEARTBEAT", "msg_id": "hb-no-reconnect"},
            reconnect_on_timeout=False,
        )

        self.assertIsNone(result)
        self.assertEqual(2, bridge.req_socket.send_string.call_count)
        self.assertEqual(0, bridge._reconnect_req_socket.call_count)

    def test_send_command_send_timeout_can_skip_reconnect_for_heartbeat(self):
        bridge = self._build_bridge(retries=2)
        bridge.req_socket.send_string.side_effect = [zmq.Again(), zmq.Again()]
        bridge._reconnect_req_socket = MagicMock()

        result = bridge.send_command(
            {"action": "HEARTBEAT", "msg_id": "hb-send-timeout-no-reconnect"},
            reconnect_on_timeout=False,
        )

        self.assertIsNone(result)
        self.assertEqual(2, bridge.req_socket.send_string.call_count)
        self.assertEqual(0, bridge._reconnect_req_socket.call_count)
        diag = bridge.get_last_command_diag()
        self.assertEqual("FAILED", diag.get("status"))
        self.assertEqual("SEND_TIMEOUT", diag.get("bridge_timeout_reason"))
        self.assertEqual("NO_ACTIVE_PEER", diag.get("bridge_timeout_subreason"))

    def test_send_command_zmq_error_can_skip_reconnect_for_heartbeat(self):
        bridge = self._build_bridge(retries=2)
        bridge.req_socket.send_string.side_effect = [zmq.ZMQError(), zmq.ZMQError()]
        bridge._reconnect_req_socket = MagicMock()

        result = bridge.send_command(
            {"action": "HEARTBEAT", "msg_id": "hb-zmq-error-no-reconnect"},
            reconnect_on_timeout=False,
        )

        self.assertIsNone(result)
        self.assertEqual(2, bridge.req_socket.send_string.call_count)
        self.assertEqual(0, bridge._reconnect_req_socket.call_count)
        diag = bridge.get_last_command_diag()
        self.assertEqual("FAILED", diag.get("status"))
        self.assertEqual("ZMQ_ERROR", diag.get("bridge_timeout_reason"))
        self.assertEqual("SOCKET_ERROR", diag.get("bridge_timeout_subreason"))

    def test_send_command_heartbeat_yields_to_trade_priority_window(self):
        bridge = self._build_bridge(retries=1)
        bridge._trade_mark_waiting(+1)
        try:
            result = bridge.send_command({"action": "HEARTBEAT", "msg_id": "hb-priority-yield"})
        finally:
            bridge._trade_mark_waiting(-1)

        self.assertIsNone(result)
        self.assertEqual(0, bridge.req_socket.send_string.call_count)
        diag = bridge.get_last_command_diag()
        self.assertEqual("SKIPPED", diag.get("status"))
        self.assertEqual("QUEUE_LOCK_TIMEOUT", diag.get("bridge_timeout_reason"))
        self.assertEqual("TRADE_PRIORITY_WINDOW", diag.get("bridge_timeout_subreason"))


if __name__ == "__main__":
    unittest.main()
