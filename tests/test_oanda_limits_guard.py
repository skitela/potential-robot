import unittest
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

from oanda_limits_guard import OandaLimitsGuard


class MemState:
    def __init__(self):
        self._data = {}

    def state_get(self, key: str, default: str = "0") -> str:
        return str(self._data.get(key, default))

    def state_set(self, key: str, value: str) -> None:
        self._data[str(key)] = str(value)


class TestOandaLimitsGuard(unittest.TestCase):
    def test_price_request_limits(self):
        db = MemState()
        with tempfile.TemporaryDirectory() as tmp:
            guard = OandaLimitsGuard(
                db,
                Path(tmp),
                warn_day=3,
                hard_stop_day=5,
                orders_per_sec=2,
                positions_pending_limit=4,
            )
        now = 1_000_000
        self.assertTrue(guard.note_price_request(now_ts=now))
        self.assertTrue(guard.note_price_request(now_ts=now + 1))
        self.assertTrue(guard.note_price_request(now_ts=now + 2))
        self.assertTrue(guard.allow_price_request())
        # Hard stop reached
        self.assertTrue(guard.note_price_request(now_ts=now + 3))
        self.assertFalse(guard.note_price_request(now_ts=now + 4))
        self.assertFalse(guard.allow_price_request())

    def test_order_rate_limit(self):
        db = MemState()
        with tempfile.TemporaryDirectory() as tmp:
            guard = OandaLimitsGuard(
                db,
                Path(tmp),
                warn_day=3,
                hard_stop_day=5,
                orders_per_sec=2,
                positions_pending_limit=4,
            )
        t = 123.0
        self.assertTrue(guard.allow_order_submit(now_ts=t))
        self.assertTrue(guard.allow_order_submit(now_ts=t + 0.1))
        self.assertFalse(guard.allow_order_submit(now_ts=t + 0.2))

    def test_positions_pending_limit(self):
        db = MemState()
        with tempfile.TemporaryDirectory() as tmp:
            guard = OandaLimitsGuard(
                db,
                Path(tmp),
                warn_day=3,
                hard_stop_day=5,
                orders_per_sec=2,
                positions_pending_limit=4,
            )
        self.assertTrue(guard.allow_positions_pending(3))
        self.assertFalse(guard.allow_positions_pending(4))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
