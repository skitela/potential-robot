import datetime as dt
import sys
import types
import unittest
from pathlib import Path
from zoneinfo import ZoneInfo

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


def _utc_from_local(year: int, month: int, day: int, hour: int, minute: int, tz_name: str) -> dt.datetime:
    local = dt.datetime(year, month, day, hour, minute, tzinfo=ZoneInfo(tz_name))
    return local.astimezone(dt.timezone.utc)


class TestTradeWindowExtensionsV1(unittest.TestCase):
    def test_trade_window_next_ctx_simple(self) -> None:
        tw = {
            "FX_AM": {"group": "FX", "anchor_tz": "Europe/Warsaw", "start_hm": (9, 0), "end_hm": (12, 0)},
            "METAL_PM": {"group": "METAL", "anchor_tz": "Europe/Warsaw", "start_hm": (14, 0), "end_hm": (17, 0)},
        }
        now_utc = _utc_from_local(2026, 2, 24, 10, 0, "Europe/Warsaw")  # inside FX_AM
        nxt = safetybot.trade_window_next_ctx(now_utc, trade_windows=tw)
        self.assertIsNotNone(nxt)
        self.assertEqual(nxt["window_id"], "METAL_PM")
        self.assertEqual(nxt["group"], "METAL")
        self.assertGreater(float(nxt["minutes_to_start"]), 0.0)

    def test_trade_window_next_ctx_overnight(self) -> None:
        tw = {
            "CRYPTO_NIGHT": {"group": "CRYPTO", "anchor_tz": "Europe/Warsaw", "start_hm": (23, 0), "end_hm": (9, 0)},
            "FX_AM": {"group": "FX", "anchor_tz": "Europe/Warsaw", "start_hm": (9, 0), "end_hm": (12, 0)},
        }

        # 08:00 local -> CRYPTO_NIGHT is active from previous day, next start should be 09:00 (FX_AM)
        now_utc = _utc_from_local(2026, 2, 24, 8, 0, "Europe/Warsaw")
        nxt = safetybot.trade_window_next_ctx(now_utc, trade_windows=tw)
        self.assertIsNotNone(nxt)
        self.assertEqual(nxt["window_id"], "FX_AM")
        self.assertEqual(nxt["group"], "FX")

        # 08:30 local -> still next is FX_AM
        now_utc = _utc_from_local(2026, 2, 24, 8, 30, "Europe/Warsaw")
        nxt = safetybot.trade_window_next_ctx(now_utc, trade_windows=tw)
        self.assertIsNotNone(nxt)
        self.assertEqual(nxt["window_id"], "FX_AM")

        # 23:30 local -> CRYPTO_NIGHT active (started today), next start should be FX_AM tomorrow
        now_utc = _utc_from_local(2026, 2, 24, 23, 30, "Europe/Warsaw")
        nxt = safetybot.trade_window_next_ctx(now_utc, trade_windows=tw)
        self.assertIsNotNone(nxt)
        self.assertEqual(nxt["window_id"], "FX_AM")
        self.assertGreater(float(nxt["minutes_to_start"]), 0.0)

    def test_fx_rotation_bucket_deterministic(self) -> None:
        syms = ["EURUSD", "GBPUSD", "USDJPY", "USDCHF", "USDCAD", "AUDUSD", "NZDUSD", "EURGBP"]
        idx0, bucket0, count0 = safetybot.fx_rotation_bucket(syms, now_ts=0, bucket_size=4, period_sec=180)
        idx1, bucket1, count1 = safetybot.fx_rotation_bucket(syms, now_ts=180, bucket_size=4, period_sec=180)
        self.assertEqual(count0, 2)
        self.assertEqual(count1, 2)
        self.assertEqual(idx0, 0)
        self.assertEqual(idx1, 1)
        self.assertNotEqual(bucket0, bucket1)
        self.assertEqual(len(bucket0), 4)
        self.assertEqual(len(bucket1), 4)


if __name__ == "__main__":
    raise SystemExit(unittest.main())

