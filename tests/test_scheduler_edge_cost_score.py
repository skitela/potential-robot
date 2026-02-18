import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

from scheduler import ActivityController


class _DB:
    def __init__(self, req: int, pnl: float, spread: float):
        self._req = req
        self._pnl = pnl
        self._spread = spread

    def price_req_for_hour(self, grp: str, symbol: str, ny_hour: int, lookback_days: int = 14) -> int:
        return int(self._req)

    def pnl_net_for_hour(self, grp: str, symbol: str, ny_hour: int, lookback_days: int = 14) -> float:
        return float(self._pnl)

    def get_p80_spread(self, symbol: str) -> float:
        return float(self._spread)


class TestSchedulerEdgeCostScore(unittest.TestCase):
    def _ctrl(self, db: _DB) -> ActivityController:
        cfg = SimpleNamespace(
            strategy={
                "score_spread_penalty_weight": 0.03,
                "score_edge_scale": 2.0,
                "score_req_soft_cap": 120,
                "score_req_penalty_weight": 0.10,
            },
            index_profile_map={},
            scheduler={},
        )
        return ActivityController(db, cfg)

    def test_score_penalizes_high_spread(self) -> None:
        low_spread = self._ctrl(_DB(req=200, pnl=40.0, spread=8.0)).score_factor("FX", "EURUSD")
        high_spread = self._ctrl(_DB(req=200, pnl=40.0, spread=35.0)).score_factor("FX", "EURUSD")
        self.assertGreater(low_spread, high_spread)

    def test_score_penalizes_request_pressure(self) -> None:
        low_req = self._ctrl(_DB(req=40, pnl=12.0, spread=10.0)).score_factor("FX", "EURUSD")
        high_req = self._ctrl(_DB(req=400, pnl=12.0, spread=10.0)).score_factor("FX", "EURUSD")
        self.assertGreater(low_req, high_req)


if __name__ == "__main__":
    raise SystemExit(unittest.main())

