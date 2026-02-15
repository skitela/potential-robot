import sys
import unittest
import shutil
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

import safetybot
from oanda_limits_guard import OandaLimitsGuard


class _StubInfo:
    def __init__(self, trade_mode: int = 4):
        self.trade_mode = trade_mode
        self.trade_stops_level = 0
        self.trade_freeze_level = 0
        self.point = 0.0001


class _StubResult:
    def __init__(self, retcode):
        self.retcode = retcode


class _StubOrder:
    def __init__(self, typ):
        self.type = typ


class _StubPosition:
    def __init__(self, sym, typ):
        self.symbol = sym
        self.type = typ


class _StubMT5:
    TRADE_ACTION_DEAL = 1
    ORDER_TYPE_BUY = 0
    ORDER_TYPE_SELL = 1
    ORDER_TYPE_BUY_LIMIT = 2
    ORDER_TYPE_SELL_LIMIT = 3
    ORDER_TYPE_BUY_STOP = 4
    ORDER_TYPE_SELL_STOP = 5
    ORDER_TYPE_BUY_STOP_LIMIT = 6
    ORDER_TYPE_SELL_STOP_LIMIT = 7
    TRADE_RETCODE_DONE = 10009
    TIMEFRAME_M5 = 5
    SYMBOL_TRADE_MODE_DISABLED = 0
    SYMBOL_TRADE_MODE_LONGONLY = 1
    SYMBOL_TRADE_MODE_SHORTONLY = 2
    SYMBOL_TRADE_MODE_CLOSEONLY = 3
    SYMBOL_TRADE_MODE_FULL = 4

    def __init__(self):
        self._positions = []
        self._orders = []
        self._trade_mode = self.SYMBOL_TRADE_MODE_FULL

    def symbol_info(self, _symbol):
        return _StubInfo(trade_mode=self._trade_mode)

    def symbol_info_tick(self, _symbol):
        class _Tick:
            time = 1_000_000
            bid = 1.0
            ask = 1.1
        return _Tick()

    def copy_rates_from_pos(self, _symbol, _timeframe, _start, n):
        return [{"time": 1_000_000, "open": 1.0, "high": 1.0, "low": 1.0, "close": 1.0} for _ in range(n)]

    def positions_get(self):
        return tuple(self._positions)

    def orders_get(self):
        return tuple(self._orders)

    def order_send(self, _request):
        return _StubResult(self.TRADE_RETCODE_DONE)


class TestOandaLimitsIntegration(unittest.TestCase):
    def setUp(self):
        self._orig_mt5 = safetybot.mt5
        self.stub = _StubMT5()
        safetybot.mt5 = self.stub

        self._orig_sqlite_connect = safetybot.sqlite3.connect
        def _connect_in_memory(_path, timeout=5, check_same_thread=False, **kwargs):
            return self._orig_sqlite_connect(":memory:", timeout=timeout, check_same_thread=check_same_thread, **kwargs)
        safetybot.sqlite3.connect = _connect_in_memory

        self._orig_required_exe = getattr(safetybot, "REQUIRED_OANDA_MT5_EXE", None)
        safetybot.REQUIRED_OANDA_MT5_EXE = Path("C:/OANDA_MT5_SYSTEM/DUMMY_MT5.exe")

        self._orig_price_budget = safetybot.CFG.price_budget_day
        self._orig_sys_budget = safetybot.CFG.sys_budget_day
        self._orig_order_budget = safetybot.CFG.order_budget_day
        safetybot.CFG.price_budget_day = 10000
        safetybot.CFG.sys_budget_day = 10000
        safetybot.CFG.order_budget_day = 10000

    def tearDown(self):
        safetybot.mt5 = self._orig_mt5
        safetybot.sqlite3.connect = self._orig_sqlite_connect
        safetybot.CFG.price_budget_day = self._orig_price_budget
        safetybot.CFG.sys_budget_day = self._orig_sys_budget
        safetybot.CFG.order_budget_day = self._orig_order_budget
        if self._orig_required_exe is None:
            delattr(safetybot, "REQUIRED_OANDA_MT5_EXE")
        else:
            safetybot.REQUIRED_OANDA_MT5_EXE = self._orig_required_exe

    def _build_client(
        self,
        tmp_dir: Path,
        warn_day: int = 3,
        hard_stop_day: int = 5,
        orders_per_sec: int = 2,
        positions_pending_limit: int = 4,
    ):
        db_path = tmp_dir / "limits.db"
        db = safetybot.Persistence(db_path)
        gov = safetybot.RequestGovernor(db)
        limits = OandaLimitsGuard(
            db,
            tmp_dir,
            warn_day=warn_day,
            hard_stop_day=hard_stop_day,
            orders_per_sec=orders_per_sec,
            positions_pending_limit=positions_pending_limit,
        )
        client = safetybot.MT5Client({"MT5_LOGIN": "1", "MT5_PASSWORD": "x", "MT5_SERVER": "y"}, gov, limits)
        return client, db

    def _tmpdir(self) -> Path:
        base = ROOT / "TMP_AUDIT_IO" / "test_oanda_limits_integration"
        path = base / f"case_{uuid.uuid4().hex}"
        path.mkdir(parents=True, exist_ok=True)
        self.addCleanup(lambda: shutil.rmtree(path, ignore_errors=True))
        return path

    def test_price_guard_blocks_copy_rates(self):
        tmp = self._tmpdir()
        client, db = self._build_client(tmp)
        try:
            for i in range(5):
                client.limits.note_price_request(now_ts=1000 + i)
            rates = client.copy_rates("EURUSD", "FX", safetybot.mt5.TIMEFRAME_M5 if safetybot.mt5 else 0, 2)
            self.assertIsNone(rates)
        finally:
            db.conn.close()

    def test_positions_pending_limit_blocks_order(self):
        tmp = self._tmpdir()
        client, db = self._build_client(tmp)
        try:
            self.stub._positions = [_StubPosition("EURUSD", self.stub.ORDER_TYPE_BUY) for _ in range(3)]
            self.stub._orders = [_StubOrder(self.stub.ORDER_TYPE_BUY_LIMIT) for _ in range(1)]
            req = {"action": self.stub.TRADE_ACTION_DEAL, "type": self.stub.ORDER_TYPE_BUY, "price": 1.0}
            res = client.order_send("EURUSD", "FX", req)
            self.assertIsNone(res)
        finally:
            db.conn.close()

    def test_order_rate_limit_blocks_submit(self):
        tmp = self._tmpdir()
        client, db = self._build_client(tmp)
        try:
            req = {"action": self.stub.TRADE_ACTION_DEAL, "type": self.stub.ORDER_TYPE_BUY, "price": 1.0}
            self.assertIsNotNone(client.order_send("EURUSD", "FX", req))
            self.assertIsNotNone(client.order_send("EURUSD", "FX", req))
            self.assertIsNone(client.order_send("EURUSD", "FX", req))
        finally:
            db.conn.close()

    def test_trade_mode_closeonly_blocks_open_allows_close(self):
        tmp = self._tmpdir()
        client, db = self._build_client(tmp)
        try:
            self.stub._trade_mode = self.stub.SYMBOL_TRADE_MODE_CLOSEONLY
            req_open = {"action": self.stub.TRADE_ACTION_DEAL, "type": self.stub.ORDER_TYPE_BUY, "price": 1.0}
            req_close = {
                "action": self.stub.TRADE_ACTION_DEAL,
                "type": self.stub.ORDER_TYPE_BUY,
                "price": 1.0,
                "position": 12345,
            }
            self.assertIsNone(client.order_send("EURUSD", "FX", req_open))
            self.assertIsNotNone(client.order_send("EURUSD", "FX", req_close))
        finally:
            db.conn.close()

    def test_trade_mode_longonly_blocks_sell(self):
        tmp = self._tmpdir()
        client, db = self._build_client(tmp)
        try:
            self.stub._trade_mode = self.stub.SYMBOL_TRADE_MODE_LONGONLY
            req_buy = {"action": self.stub.TRADE_ACTION_DEAL, "type": self.stub.ORDER_TYPE_BUY, "price": 1.0}
            req_sell = {"action": self.stub.TRADE_ACTION_DEAL, "type": self.stub.ORDER_TYPE_SELL, "price": 1.0}
            self.assertIsNotNone(client.order_send("EURUSD", "FX", req_buy))
            self.assertIsNone(client.order_send("EURUSD", "FX", req_sell))
        finally:
            db.conn.close()

    def test_trade_mode_shortonly_blocks_buy(self):
        tmp = self._tmpdir()
        client, db = self._build_client(tmp)
        try:
            self.stub._trade_mode = self.stub.SYMBOL_TRADE_MODE_SHORTONLY
            req_buy = {"action": self.stub.TRADE_ACTION_DEAL, "type": self.stub.ORDER_TYPE_BUY, "price": 1.0}
            req_sell = {"action": self.stub.TRADE_ACTION_DEAL, "type": self.stub.ORDER_TYPE_SELL, "price": 1.0}
            self.assertIsNone(client.order_send("EURUSD", "FX", req_buy))
            self.assertIsNotNone(client.order_send("EURUSD", "FX", req_sell))
        finally:
            db.conn.close()

    def test_safe_mode_blocks_order_allows_emergency(self):
        tmp = self._tmpdir()
        client, db = self._build_client(tmp, hard_stop_day=2)
        try:
            client.limits.note_price_request(now_ts=1000)
            client.limits.note_price_request(now_ts=1001)
            req = {"action": self.stub.TRADE_ACTION_DEAL, "type": self.stub.ORDER_TYPE_BUY, "price": 1.0}
            self.assertIsNone(client.order_send("EURUSD", "FX", req))
            self.assertIsNotNone(client.order_send("EURUSD", "FX", req, emergency=True))
        finally:
            db.conn.close()

    def test_trade_mode_disabled_blocks_all(self):
        tmp = self._tmpdir()
        client, db = self._build_client(tmp)
        try:
            self.stub._trade_mode = self.stub.SYMBOL_TRADE_MODE_DISABLED
            req_open = {"action": self.stub.TRADE_ACTION_DEAL, "type": self.stub.ORDER_TYPE_BUY, "price": 1.0}
            req_close = {
                "action": self.stub.TRADE_ACTION_DEAL,
                "type": self.stub.ORDER_TYPE_BUY,
                "price": 1.0,
                "position": 12345,
            }
            self.assertIsNone(client.order_send("EURUSD", "FX", req_open))
            self.assertIsNone(client.order_send("EURUSD", "FX", req_close))
        finally:
            db.conn.close()

    def test_warn_level_and_evidence_state_written(self):
        tmp_path = self._tmpdir()
        client, db = self._build_client(tmp_path, warn_day=2, hard_stop_day=5)
        try:
            self.assertFalse(client.limits.warn_level_reached(now_ts=1000))
            client.limits.note_price_request(now_ts=1000)
            client.limits.note_price_request(now_ts=1001)
            self.assertTrue(client.limits.warn_level_reached(now_ts=1001))
            state_path = tmp_path / "oanda_limits_state.json"
            self.assertTrue(state_path.exists())
            data = state_path.read_text(encoding="utf-8")
            self.assertIn("utc_day_id", data)
            self.assertIn("utc_day_count", data)
        finally:
            db.conn.close()

    def test_positions_pending_limit_emergency_allows(self):
        tmp = self._tmpdir()
        client, db = self._build_client(tmp, positions_pending_limit=3)
        try:
            self.stub._positions = [_StubPosition("EURUSD", self.stub.ORDER_TYPE_BUY) for _ in range(2)]
            self.stub._orders = [_StubOrder(self.stub.ORDER_TYPE_BUY_LIMIT) for _ in range(1)]
            req = {"action": self.stub.TRADE_ACTION_DEAL, "type": self.stub.ORDER_TYPE_BUY, "price": 1.0}
            self.assertIsNotNone(client.order_send("EURUSD", "FX", req, emergency=True))
        finally:
            db.conn.close()


if __name__ == "__main__":
    raise SystemExit(unittest.main())
