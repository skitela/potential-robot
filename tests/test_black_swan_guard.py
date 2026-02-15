import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

from black_swan_guard import BlackSwanGuard, BlackSwanPolicy


class TestBlackSwanGuard(unittest.TestCase):
    def test_precaution_threshold(self):
        guard = BlackSwanGuard(BlackSwanPolicy(black_swan_threshold=3.0, precaution_fraction=0.8))
        signal = guard.evaluate(
            current_vols={"EURUSD": 0.031},  # z_vol=4.2 -> stress~2.52
            current_spreads={"EURUSD": 10.0},
        )
        self.assertFalse(signal.black_swan)
        self.assertTrue(signal.precaution)
        self.assertIn("STRESS_PRECAUTION", signal.reasons)

    def test_black_swan_trigger_and_baseline_freeze(self):
        guard = BlackSwanGuard(BlackSwanPolicy(black_swan_threshold=3.0, precaution_fraction=0.8))
        before = guard.baseline.mean_volatility
        signal = guard.evaluate(
            current_vols={"EURUSD": 0.040},  # z_vol=6.0 -> stress~3.6
            current_spreads={"EURUSD": 10.0},
        )
        after = guard.baseline.mean_volatility
        self.assertTrue(signal.black_swan)
        self.assertFalse(signal.precaution)
        self.assertIn("BLACK_SWAN_STRESS", signal.reasons)
        self.assertIn("KILL_SWITCH_BLACK_SWAN_STRESS", signal.reasons)
        self.assertAlmostEqual(before, after, places=12)

    def test_baseline_updates_when_not_black_swan(self):
        guard = BlackSwanGuard(BlackSwanPolicy(black_swan_threshold=3.0, precaution_fraction=0.8, ewma_alpha=0.2))
        before = guard.baseline.mean_volatility
        signal = guard.evaluate(
            current_vols={"EURUSD": 0.018},
            current_spreads={"EURUSD": 11.0},
        )
        after = guard.baseline.mean_volatility
        self.assertFalse(signal.black_swan)
        self.assertNotEqual(before, after)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
