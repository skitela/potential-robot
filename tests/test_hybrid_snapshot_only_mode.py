import shutil
import sys
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

import safetybot


class _TickStub:
    def __init__(self, bid: float, ask: float):
        self.bid = float(bid)
        self.ask = float(ask)
        self.time = int(time.time())
        self.volume = 1


class _AccountStub:
    def __init__(self, balance: float = 1000.0, equity: float = 1000.0, margin_free: float = 800.0):
        self.balance = float(balance)
        self.equity = float(equity)
        self.margin_free = float(margin_free)
        self.margin_level = 100.0


class _StubMT5:
    TIMEFRAME_M5 = 5

    def __init__(self):
        self.symbol_info_tick_calls = 0
        self.account_info_calls = 0

    @staticmethod
    def symbol_select(_symbol, _flag):
        return True

    @staticmethod
    def last_error():
        return (0, "OK")

    def symbol_info_tick(self, _symbol):
        self.symbol_info_tick_calls += 1
        return _TickStub(1.1000, 1.1002)

    def account_info(self):
        self.account_info_calls += 1
        return _AccountStub()


class TestHybridSnapshotOnlyMode(unittest.TestCase):
    def setUp(self):
        self._orig_mt5 = safetybot.mt5
        self._orig_sqlite_connect = safetybot.sqlite3.connect
        self._orig_hybrid_strict = safetybot.CFG.hybrid_m5_no_fetch_strict
        self._orig_hybrid_hard = getattr(safetybot.CFG, "hybrid_no_mt5_data_fetch_hard", False)
        self._orig_account_age = getattr(safetybot.CFG, "hybrid_account_snapshot_max_age_sec", 30)
        self._orig_symbol_age = getattr(safetybot.CFG, "hybrid_symbol_snapshot_max_age_sec", 300)

        safetybot.mt5 = _StubMT5()

        def _connect_in_memory(_path, timeout=5, check_same_thread=False, **kwargs):
            return self._orig_sqlite_connect(":memory:", timeout=timeout, check_same_thread=check_same_thread, **kwargs)

        safetybot.sqlite3.connect = _connect_in_memory

    def tearDown(self):
        safetybot.mt5 = self._orig_mt5
        safetybot.sqlite3.connect = self._orig_sqlite_connect
        safetybot.CFG.hybrid_m5_no_fetch_strict = self._orig_hybrid_strict
        safetybot.CFG.hybrid_no_mt5_data_fetch_hard = self._orig_hybrid_hard
        safetybot.CFG.hybrid_account_snapshot_max_age_sec = self._orig_account_age
        safetybot.CFG.hybrid_symbol_snapshot_max_age_sec = self._orig_symbol_age

    def _tmpdir(self) -> Path:
        base = ROOT / "TMP_AUDIT_IO" / "test_hybrid_snapshot_only_mode"
        path = base / f"case_{uuid.uuid4().hex}"
        path.mkdir(parents=True, exist_ok=True)
        self.addCleanup(lambda: shutil.rmtree(path, ignore_errors=True))
        return path

    def _build_engine(self):
        tmp = self._tmpdir()
        db = safetybot.Persistence(tmp / "state.sqlite")
        self.addCleanup(db.conn.close)
        gov = safetybot.RequestGovernor(db)
        engine = safetybot.ExecutionEngine(
            {"MT5_LOGIN": "1", "MT5_PASSWORD": "x", "MT5_SERVER": "y"},
            gov,
            limits=None,
        )
        return engine

    def test_tick_strict_hard_uses_zmq_cache_without_mt5_fetch(self):
        safetybot.CFG.hybrid_m5_no_fetch_strict = True
        safetybot.CFG.hybrid_no_mt5_data_fetch_hard = True
        engine = self._build_engine()
        now_ms = int(time.time() * 1000)
        engine._zmq_tick_cache["EURUSD"] = {
            "bid": 1.1234,
            "ask": 1.1236,
            "timestamp_ms": now_ms,
            "volume": 2,
        }

        t = engine.tick("EURUSD", "FX", emergency=False)

        self.assertIsNotNone(t)
        self.assertAlmostEqual(1.1234, float(getattr(t, "bid", 0.0)), places=6)
        self.assertEqual(0, safetybot.mt5.symbol_info_tick_calls)

    def test_tick_strict_hard_uses_normalized_zmq_cache_key_without_mt5_fetch(self):
        safetybot.CFG.hybrid_m5_no_fetch_strict = True
        safetybot.CFG.hybrid_no_mt5_data_fetch_hard = True
        engine = self._build_engine()
        now_ms = int(time.time() * 1000)
        engine._zmq_tick_cache["EURUSD.PRO"] = {
            "bid": 1.2234,
            "ask": 1.2237,
            "timestamp_ms": now_ms,
            "volume": 3,
        }

        t = engine.tick("EURUSD.pro", "FX", emergency=False)

        self.assertIsNotNone(t)
        self.assertAlmostEqual(1.2234, float(getattr(t, "bid", 0.0)), places=6)
        self.assertEqual(0, safetybot.mt5.symbol_info_tick_calls)

    def test_tick_strict_hard_blocks_mt5_fallback_when_cache_missing(self):
        safetybot.CFG.hybrid_m5_no_fetch_strict = True
        safetybot.CFG.hybrid_no_mt5_data_fetch_hard = True
        engine = self._build_engine()

        t = engine.tick("EURUSD", "FX", emergency=False)

        self.assertIsNone(t)
        self.assertEqual(0, safetybot.mt5.symbol_info_tick_calls)

    def test_account_info_strict_hard_uses_snapshot_without_mt5_fetch(self):
        safetybot.CFG.hybrid_m5_no_fetch_strict = True
        safetybot.CFG.hybrid_no_mt5_data_fetch_hard = True
        safetybot.CFG.hybrid_account_snapshot_max_age_sec = 60
        engine = self._build_engine()
        engine._zmq_account_cache = {
            "recv_ts": time.time(),
            "balance": 1234.5,
            "equity": 1200.0,
            "margin_free": 900.0,
            "margin_level": 150.0,
        }

        acc = engine.account_info()

        self.assertIsNotNone(acc)
        self.assertAlmostEqual(1234.5, float(getattr(acc, "balance", 0.0)), places=6)
        self.assertAlmostEqual(900.0, float(getattr(acc, "margin_free", 0.0)), places=6)
        self.assertEqual(0, safetybot.mt5.account_info_calls)

    def test_account_info_strict_hard_rejects_stale_snapshot(self):
        safetybot.CFG.hybrid_m5_no_fetch_strict = True
        safetybot.CFG.hybrid_no_mt5_data_fetch_hard = True
        safetybot.CFG.hybrid_account_snapshot_max_age_sec = 5
        engine = self._build_engine()
        engine._zmq_account_cache = {
            "recv_ts": time.time() - 600.0,
            "balance": 1000.0,
            "equity": 1000.0,
            "margin_free": 1000.0,
            "margin_level": 100.0,
        }

        acc = engine.account_info()

        self.assertIsNone(acc)
        self.assertEqual(0, safetybot.mt5.account_info_calls)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
