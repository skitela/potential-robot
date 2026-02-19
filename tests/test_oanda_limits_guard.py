import unittest
import sys
import shutil
import uuid
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
    def _tmpdir(self) -> Path:
        base = Path("TMP_AUDIT_IO") / "test_oanda_limits_guard"
        path = base / f"case_{uuid.uuid4().hex}"
        path.mkdir(parents=True, exist_ok=True)
        self.addCleanup(lambda: shutil.rmtree(path, ignore_errors=True))
        return path

    def test_price_request_limits(self):
        db = MemState()
        tmp = self._tmpdir()
        guard = OandaLimitsGuard(
            db,
            tmp,
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
        tmp = self._tmpdir()
        guard = OandaLimitsGuard(
            db,
            tmp,
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
        tmp = self._tmpdir()
        guard = OandaLimitsGuard(
            db,
            tmp,
            warn_day=3,
            hard_stop_day=5,
            orders_per_sec=2,
            positions_pending_limit=4,
        )
        self.assertTrue(guard.allow_positions_pending(3))
        self.assertFalse(guard.allow_positions_pending(4))

    def test_price_kind_breakdown(self):
        db = MemState()
        tmp = self._tmpdir()
        guard = OandaLimitsGuard(
            db,
            tmp,
            warn_day=3,
            hard_stop_day=50,
            orders_per_sec=2,
            positions_pending_limit=4,
        )
        now = 2_000_000
        self.assertTrue(guard.note_price_request(now_ts=now, kind="tick"))
        self.assertTrue(guard.note_price_request(now_ts=now + 1, kind="rates_5"))
        self.assertTrue(guard.note_price_request(now_ts=now + 2, kind="copy_rates"))
        b = guard.get_price_breakdown(now_ts=now + 2)
        self.assertEqual(int(b.get("tick", -1)), 1)
        self.assertEqual(int(b.get("rates", -1)), 2)
        self.assertEqual(int(b.get("total", -1)), 3)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
