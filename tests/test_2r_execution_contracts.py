import json
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import MagicMock

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

if "zmq" not in sys.modules:
    zmq_stub = types.ModuleType("zmq")

    class _DummySocket:
        def setsockopt(self, *_args, **_kwargs):
            return None

        def bind(self, *_args, **_kwargs):
            return None

        def close(self):
            return None

    class _DummyContext:
        def socket(self, *_args, **_kwargs):
            return _DummySocket()

        def term(self):
            return None

    class _Again(Exception):
        pass

    class _ZMQError(Exception):
        pass

    zmq_stub.Context = _DummyContext
    zmq_stub.Socket = _DummySocket
    zmq_stub.Again = _Again
    zmq_stub.ZMQError = _ZMQError
    zmq_stub.LINGER = 0
    zmq_stub.SNDTIMEO = 1
    zmq_stub.RCVTIMEO = 2
    zmq_stub.IMMEDIATE = 3
    zmq_stub.PULL = 4
    zmq_stub.REQ = 5
    zmq_stub.NOBLOCK = 6
    sys.modules["zmq"] = zmq_stub

from BIN.zeromq_bridge import ZMQBridge, build_request_hash, build_response_hash


class Test2RExecutionContracts(unittest.TestCase):
    def _bridge(self) -> ZMQBridge:
        bridge = ZMQBridge(req_retries=1, req_timeout_ms=5, audit_log_path=None)
        try:
            bridge.context.term()
        except Exception:
            pass
        bridge.context = MagicMock()
        bridge.req_socket = MagicMock()
        return bridge

    def test_trade_request_hash_includes_deviation_points(self) -> None:
        base = {
            "action": "TRADE",
            "msg_id": "m-1",
            "payload": {
                "signal": "BUY",
                "symbol": "EURUSD.pro",
                "volume": 0.01,
                "sl_price": 1.0,
                "tp_price": 2.0,
                "magic": 7,
                "comment": "x",
                "deviation_points": 10,
            },
        }
        alt = json.loads(json.dumps(base))
        alt["payload"]["deviation_points"] = 11
        self.assertNotEqual(build_request_hash(base), build_request_hash(alt))

    def test_send_command_adds_time_semantics_and_ids(self) -> None:
        bridge = self._bridge()
        cmd = {
            "action": "TRADE",
            "msg_id": "m-2",
            "payload": {"signal": "BUY", "symbol": "EURUSD.pro", "deviation_points": 10},
        }
        req_hash = build_request_hash(cmd)
        reply = {
            "status": "PROCESSED",
            "correlation_id": "m-2",
            "action": "TRADE_REPLY",
            "request_hash": req_hash,
            "details": {"retcode": 10009, "order": 1, "deal": 2},
            "error": "",
        }
        reply["response_hash"] = build_response_hash(reply)
        bridge.req_socket.poll.side_effect = [True]
        bridge.req_socket.recv_string.side_effect = [json.dumps(reply)]

        result = bridge.send_command(cmd)
        self.assertIsInstance(result, dict)
        diag = result.get("__bridge_diag") if isinstance(result, dict) else {}
        self.assertIsInstance(diag, dict)
        self.assertEqual("OK", str((diag or {}).get("status")))
        sent = json.loads(bridge.req_socket.send_string.call_args.args[0])
        self.assertEqual("UTC", sent.get("request_ts_semantics"))
        self.assertEqual("m-2", sent.get("command_id"))
        self.assertEqual("m-2", sent.get("request_id"))

    def test_schema_files_present(self) -> None:
        tele = ROOT / "SCHEMAS" / "execution_telemetry_contract_v2.json"
        comp = ROOT / "SCHEMAS" / "execution_comparison_contract_v1.json"
        self.assertTrue(tele.exists())
        self.assertTrue(comp.exists())
        tele_obj = json.loads(tele.read_text(encoding="utf-8-sig"))
        comp_obj = json.loads(comp.read_text(encoding="utf-8-sig"))
        self.assertIn("required", tele_obj)
        self.assertIn("required", comp_obj)
        self.assertIn("timestamp_semantics", tele_obj["required"])
        self.assertIn("exact_window", comp_obj["required"])


if __name__ == "__main__":
    raise SystemExit(unittest.main())
