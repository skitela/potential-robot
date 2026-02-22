import shutil
import sys
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

import safetybot


class _StubMT5:
    TIMEFRAME_M5 = 5

    def __init__(self):
        self.copy_rates_calls = 0

    def copy_rates_from_pos(self, _symbol, _timeframe, _start, n):
        self.copy_rates_calls += 1
        base_ts = 1_700_000_000
        out = []
        for i in range(max(1, int(n))):
            out.append(
                {
                    "time": int(base_ts + (i * 300)),
                    "open": 1.1000,
                    "high": 1.1005,
                    "low": 1.0995,
                    "close": 1.1002,
                }
            )
        return out

    @staticmethod
    def symbol_select(_symbol, _flag):
        return True

    @staticmethod
    def last_error():
        return (0, "OK")


class _StoreStub:
    def __init__(self, frames=None):
        self.frames = dict(frames or {})

    @staticmethod
    def upsert_df(_base_symbol, _df):
        return None

    def read_recent_df(self, base_symbol: str, limit: int):
        df = self.frames.get(str(base_symbol))
        if df is None:
            return None
        try:
            return df.tail(max(1, int(limit))).reset_index(drop=True)
        except Exception:
            return None


class TestHybridM5NoFetch(unittest.TestCase):
    def setUp(self):
        self._orig_mt5 = safetybot.mt5
        self._orig_sqlite_connect = safetybot.sqlite3.connect
        self._orig_hybrid_use = safetybot.CFG.hybrid_use_zmq_m5_bars
        self._orig_hybrid_strict = safetybot.CFG.hybrid_m5_no_fetch_strict
        safetybot.mt5 = _StubMT5()

        def _connect_in_memory(_path, timeout=5, check_same_thread=False, **kwargs):
            return self._orig_sqlite_connect(":memory:", timeout=timeout, check_same_thread=check_same_thread, **kwargs)

        safetybot.sqlite3.connect = _connect_in_memory

    def tearDown(self):
        safetybot.mt5 = self._orig_mt5
        safetybot.sqlite3.connect = self._orig_sqlite_connect
        safetybot.CFG.hybrid_use_zmq_m5_bars = self._orig_hybrid_use
        safetybot.CFG.hybrid_m5_no_fetch_strict = self._orig_hybrid_strict

    def _tmpdir(self) -> Path:
        base = ROOT / "TMP_AUDIT_IO" / "test_hybrid_m5_no_fetch"
        path = base / f"case_{uuid.uuid4().hex}"
        path.mkdir(parents=True, exist_ok=True)
        self.addCleanup(lambda: shutil.rmtree(path, ignore_errors=True))
        return path

    def _build_engine(self, store_stub):
        tmp = self._tmpdir()
        db = safetybot.Persistence(tmp / "state.sqlite")
        self.addCleanup(db.conn.close)
        gov = safetybot.RequestGovernor(db)
        engine = safetybot.ExecutionEngine(
            {"MT5_LOGIN": "1", "MT5_PASSWORD": "x", "MT5_SERVER": "y"},
            gov,
            limits=None,
        )
        engine.bars_store = store_stub
        return engine

    def test_copy_rates_prefers_zmq_store_for_m5(self):
        safetybot.CFG.hybrid_use_zmq_m5_bars = True
        safetybot.CFG.hybrid_m5_no_fetch_strict = True
        df_src = safetybot.pd.DataFrame(
            [
                {"time": safetybot.pd.Timestamp("2026-02-22T09:00:00+01:00"), "open": 1.1, "high": 1.11, "low": 1.09, "close": 1.105},
                {"time": safetybot.pd.Timestamp("2026-02-22T09:05:00+01:00"), "open": 1.2, "high": 1.21, "low": 1.19, "close": 1.205},
                {"time": safetybot.pd.Timestamp("2026-02-22T09:10:00+01:00"), "open": 1.3, "high": 1.31, "low": 1.29, "close": 1.305},
            ]
        )
        engine = self._build_engine(_StoreStub({"EURUSD": df_src}))
        df = engine.copy_rates("EURUSD", "FX", safetybot.CFG.timeframe_trade, 2)
        self.assertIsNotNone(df)
        self.assertEqual(2, len(df))
        self.assertEqual(0, safetybot.mt5.copy_rates_calls)

    def test_copy_rates_strict_no_fetch_returns_none_when_store_short(self):
        safetybot.CFG.hybrid_use_zmq_m5_bars = True
        safetybot.CFG.hybrid_m5_no_fetch_strict = True
        engine = self._build_engine(_StoreStub())
        df = engine.copy_rates("EURUSD", "FX", safetybot.CFG.timeframe_trade, 2)
        self.assertIsNone(df)
        self.assertEqual(0, safetybot.mt5.copy_rates_calls)

    def test_copy_rates_non_strict_falls_back_to_mt5(self):
        safetybot.CFG.hybrid_use_zmq_m5_bars = True
        safetybot.CFG.hybrid_m5_no_fetch_strict = False
        engine = self._build_engine(_StoreStub())
        df = engine.copy_rates("EURUSD", "FX", safetybot.CFG.timeframe_trade, 2)
        self.assertIsNotNone(df)
        self.assertGreaterEqual(len(df), 1)
        self.assertEqual(1, safetybot.mt5.copy_rates_calls)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
