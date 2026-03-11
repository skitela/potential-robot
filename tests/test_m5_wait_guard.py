import datetime as dt
import shutil
import sys
import types
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

if "MetaTrader5" not in sys.modules:
    mt5_stub = types.ModuleType("MetaTrader5")
    mt5_stub.TIMEFRAME_M5 = 5
    mt5_stub.TIMEFRAME_H4 = 16388
    mt5_stub.TIMEFRAME_D1 = 16408
    sys.modules["MetaTrader5"] = mt5_stub

import safetybot


class _EngineStub:
    def __init__(self, df):
        self._df = df
        self.calls = 0

    def copy_rates(self, _symbol, _grp, _timeframe, _n):
        self.calls += 1
        return self._df.copy()


class _BotStub:
    def __init__(self, now_ts: float, df):
        self.config = types.SimpleNamespace(scheduler={})
        self.cache = types.SimpleNamespace(
            last_m5_calc_ts={},
            next_m5_fetch_ts={"EU50.pro": float(now_ts + 3600.0)},
            last_m5_bar_time={},
        )
        self.zmq_feature_cache = {}
        self.engine = _EngineStub(df)
        self.last_indicators = {}
        self.skips = []
        self._skip_allowed = []

    def _metric_inc_skip(self, reason: str):
        self.skips.append(str(reason))

    def _skip_log_allowed(self, *_args, **_kwargs):
        return False

    def _log_skip_pre_throttled(self, symbol, grp, mode, reason, **_kwargs):  # noqa: ANN001
        self.skips.append(str(reason))


class TestM5WaitGuard(unittest.TestCase):
    def _tmpdir(self) -> Path:
        base = ROOT / "TMP_AUDIT_IO" / "test_m5_wait_guard"
        path = base / f"case_{uuid.uuid4().hex}"
        path.mkdir(parents=True, exist_ok=True)
        self.addCleanup(lambda: shutil.rmtree(path, ignore_errors=True))
        return path

    @staticmethod
    def _m5_df(rows: int = 120):
        total = max(80, int(rows))
        base = safetybot.pd.Timestamp.now(tz=safetybot.TZ_PL).floor("5min")
        out = []
        for i in range(total):
            t = base - safetybot.pd.Timedelta(minutes=5 * (total - 1 - i))
            op = 100.0 + (i * 0.01)
            cl = op + (0.004 if i % 2 == 0 else -0.003)
            hi = max(op, cl) + 0.010
            lo = min(op, cl) - 0.010
            out.append({"time": t, "open": op, "high": hi, "low": lo, "close": cl})
        return safetybot.pd.DataFrame(out)

    def test_large_next_fetch_is_guarded_and_does_not_block_indicator_calc(self):
        old_guard = safetybot.CFG.m5_wait_new_bar_max_sec
        old_use_features = safetybot.CFG.hybrid_use_zmq_m5_features
        old_atr_period = safetybot.CFG.atr_period
        try:
            safetybot.CFG.m5_wait_new_bar_max_sec = 900
            safetybot.CFG.hybrid_use_zmq_m5_features = False
            safetybot.CFG.atr_period = 14

            now_ts = safetybot.time.time()
            bot = _BotStub(now_ts=now_ts, df=self._m5_df())
            ind = safetybot.StandardStrategy.m5_indicators_if_due(bot, "EU50.pro", "INDEX", "ECO")

            self.assertIsNotNone(ind)
            self.assertEqual(1, bot.engine.calls)
            self.assertNotIn("M5_WAIT_NEW_BAR", bot.skips)
        finally:
            safetybot.CFG.m5_wait_new_bar_max_sec = old_guard
            safetybot.CFG.hybrid_use_zmq_m5_features = old_use_features
            safetybot.CFG.atr_period = old_atr_period

    def test_zmq_feature_cache_uses_bar_age_budget_before_copy_rates_fallback(self):
        old_use_features = safetybot.CFG.hybrid_use_zmq_m5_features
        old_snapshot_age = safetybot.CFG.hybrid_snapshot_max_age_sec
        old_bar_age = safetybot.CFG.hybrid_snapshot_bar_max_age_sec
        old_tf = safetybot.CFG.timeframe_trade
        try:
            safetybot.CFG.hybrid_use_zmq_m5_features = True
            safetybot.CFG.hybrid_snapshot_max_age_sec = 180
            safetybot.CFG.hybrid_snapshot_bar_max_age_sec = 900
            safetybot.CFG.timeframe_trade = 5

            now_ts = safetybot.time.time()
            bot = _BotStub(now_ts=now_ts, df=self._m5_df())
            bot.zmq_feature_cache = {
                "USDJPY": {
                    "recv_ts": float(now_ts - 240.0),
                    "bar_time_pl": safetybot.pd.Timestamp.now(tz=safetybot.TZ_PL).floor("5min"),
                    "open": 157.0,
                    "close": 158.0,
                    "sma_fast": 157.5,
                    "adx": 28.0,
                    "atr": 0.12,
                }
            }

            ind = safetybot.StandardStrategy.m5_indicators_if_due(bot, "USDJPY.pro", "FX", "ECO")

            self.assertIsNotNone(ind)
            self.assertEqual(0, bot.engine.calls)
            self.assertAlmostEqual(158.0, float(ind["close"]), places=6)
            self.assertAlmostEqual(28.0, float(ind["adx"]), places=6)
        finally:
            safetybot.CFG.hybrid_use_zmq_m5_features = old_use_features
            safetybot.CFG.hybrid_snapshot_max_age_sec = old_snapshot_age
            safetybot.CFG.hybrid_snapshot_bar_max_age_sec = old_bar_age
            safetybot.CFG.timeframe_trade = old_tf

    def test_paper_reuses_recent_cached_indicators_on_pull_wait(self):
        old_paper = safetybot.CFG.paper_trading
        old_reuse = safetybot.CFG.paper_m5_wait_reuse_enabled
        old_reuse_age = safetybot.CFG.paper_m5_indicator_reuse_max_age_sec
        old_pull = safetybot.CFG.m5_pull_sec_eco
        try:
            safetybot.CFG.paper_trading = True
            safetybot.CFG.paper_m5_wait_reuse_enabled = True
            safetybot.CFG.paper_m5_indicator_reuse_max_age_sec = 300
            safetybot.CFG.m5_pull_sec_eco = 300

            now_ts = safetybot.time.time()
            bot = _BotStub(now_ts=now_ts, df=self._m5_df())
            bot.cache.last_m5_calc_ts["USDJPY.pro"] = float(now_ts - 10.0)
            bot.last_indicators["USDJPY"] = {
                "close": 158.0,
                "open": 157.0,
                "high": 158.2,
                "low": 156.9,
                "sma": 157.5,
                "adx": 28.0,
                "atr": 0.12,
            }

            ind = safetybot.StandardStrategy.m5_indicators_if_due(bot, "USDJPY.pro", "FX", "ECO")

            self.assertIsNotNone(ind)
            self.assertEqual(0, bot.engine.calls)
            self.assertEqual(158.0, float(ind["close"]))
            self.assertNotIn("M5_PULL_WAIT", bot.skips)
        finally:
            safetybot.CFG.paper_trading = old_paper
            safetybot.CFG.paper_m5_wait_reuse_enabled = old_reuse
            safetybot.CFG.paper_m5_indicator_reuse_max_age_sec = old_reuse_age
            safetybot.CFG.m5_pull_sec_eco = old_pull

    def test_paper_reuses_recent_cached_indicators_on_wait_new_bar(self):
        old_paper = safetybot.CFG.paper_trading
        old_reuse = safetybot.CFG.paper_m5_wait_reuse_enabled
        old_reuse_age = safetybot.CFG.paper_m5_indicator_reuse_max_age_sec
        old_pull = safetybot.CFG.m5_pull_sec_eco
        try:
            safetybot.CFG.paper_trading = True
            safetybot.CFG.paper_m5_wait_reuse_enabled = True
            safetybot.CFG.paper_m5_indicator_reuse_max_age_sec = 300
            safetybot.CFG.m5_pull_sec_eco = 1

            now_ts = safetybot.time.time()
            bot = _BotStub(now_ts=now_ts, df=self._m5_df())
            bot.cache.last_m5_calc_ts["USDJPY.pro"] = float(now_ts - 5.0)
            bot.cache.next_m5_fetch_ts["USDJPY.pro"] = float(now_ts + 10.0)
            bot.last_indicators["USDJPY"] = {
                "close": 158.0,
                "open": 157.0,
                "high": 158.2,
                "low": 156.9,
                "sma": 157.5,
                "adx": 28.0,
                "atr": 0.12,
            }

            ind = safetybot.StandardStrategy.m5_indicators_if_due(bot, "USDJPY.pro", "FX", "ECO")

            self.assertIsNotNone(ind)
            self.assertEqual(0, bot.engine.calls)
            self.assertEqual(158.0, float(ind["close"]))
            self.assertNotIn("M5_WAIT_NEW_BAR", bot.skips)
        finally:
            safetybot.CFG.paper_trading = old_paper
            safetybot.CFG.paper_m5_wait_reuse_enabled = old_reuse
            safetybot.CFG.paper_m5_indicator_reuse_max_age_sec = old_reuse_age
            safetybot.CFG.m5_pull_sec_eco = old_pull

    def test_live_mode_does_not_reuse_cached_indicators_on_pull_wait(self):
        old_paper = safetybot.CFG.paper_trading
        old_reuse = safetybot.CFG.paper_m5_wait_reuse_enabled
        old_reuse_age = safetybot.CFG.paper_m5_indicator_reuse_max_age_sec
        old_pull = safetybot.CFG.m5_pull_sec_eco
        try:
            safetybot.CFG.paper_trading = False
            safetybot.CFG.paper_m5_wait_reuse_enabled = True
            safetybot.CFG.paper_m5_indicator_reuse_max_age_sec = 300
            safetybot.CFG.m5_pull_sec_eco = 300

            now_ts = safetybot.time.time()
            bot = _BotStub(now_ts=now_ts, df=self._m5_df())
            bot.cache.last_m5_calc_ts["USDJPY.pro"] = float(now_ts - 10.0)
            bot.last_indicators["USDJPY"] = {
                "close": 158.0,
                "open": 157.0,
                "high": 158.2,
                "low": 156.9,
                "sma": 157.5,
                "adx": 28.0,
                "atr": 0.12,
            }

            ind = safetybot.StandardStrategy.m5_indicators_if_due(bot, "USDJPY.pro", "FX", "ECO")

            self.assertIsNone(ind)
            self.assertEqual(0, bot.engine.calls)
            self.assertIn("M5_PULL_WAIT", bot.skips)
        finally:
            safetybot.CFG.paper_trading = old_paper
            safetybot.CFG.paper_m5_wait_reuse_enabled = old_reuse
            safetybot.CFG.paper_m5_indicator_reuse_max_age_sec = old_reuse_age
            safetybot.CFG.m5_pull_sec_eco = old_pull

    def test_zmq_bar_snapshot_applies_epoch_offset_correction(self):
        old_have = safetybot._MT5_SERVER_EPOCH_OFFSET_HAVE
        old_off = safetybot._MT5_SERVER_EPOCH_OFFSET_SEC
        old_log_ts = safetybot._MT5_SERVER_EPOCH_OFFSET_LAST_LOG_TS
        old_time = safetybot.time.time
        fixed_now = 1_760_000_000.0
        try:
            safetybot._MT5_SERVER_EPOCH_OFFSET_HAVE = False
            safetybot._MT5_SERVER_EPOCH_OFFSET_SEC = 0
            safetybot._MT5_SERVER_EPOCH_OFFSET_LAST_LOG_TS = 0.0
            safetybot.time.time = lambda: fixed_now

            tmp = self._tmpdir()
            store = safetybot.M5BarsStore(tmp)
            self.addCleanup(store.conn.close)

            shifted_epoch = int(fixed_now + 3600.0)
            ok = store.upsert_bar_snapshot(
                "EU50",
                {"time": shifted_epoch, "open": 1.0, "high": 2.0, "low": 0.5, "close": 1.5},
            )
            self.assertTrue(ok)

            row = store.conn.execute(
                "SELECT t_utc FROM m5_bars WHERE symbol=? ORDER BY t_utc DESC LIMIT 1",
                ("EU50",),
            ).fetchone()
            self.assertIsNotNone(row)
            expected = (
                dt.datetime.fromtimestamp(int(fixed_now), tz=safetybot.UTC)
                .replace(microsecond=0)
                .isoformat()
                .replace("+00:00", "Z")
            )
            self.assertEqual(expected, row[0])
        finally:
            safetybot.time.time = old_time
            safetybot._MT5_SERVER_EPOCH_OFFSET_HAVE = old_have
            safetybot._MT5_SERVER_EPOCH_OFFSET_SEC = old_off
            safetybot._MT5_SERVER_EPOCH_OFFSET_LAST_LOG_TS = old_log_ts


if __name__ == "__main__":
    raise SystemExit(unittest.main())
