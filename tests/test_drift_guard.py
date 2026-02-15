import unittest

from BIN.drift_guard import DriftGuard, DriftPolicy


class TestDriftGuard(unittest.TestCase):
    def test_insufficient_data(self) -> None:
        g = DriftGuard(DriftPolicy(min_samples=10))
        sig = g.evaluate([0.1, 0.2, 0.3])
        self.assertFalse(sig.active)
        self.assertIn("INSUFFICIENT_DATA", sig.reasons)

    def test_positive_edge_collapse(self) -> None:
        g = DriftGuard(
            DriftPolicy(
                min_samples=20,
                baseline_window=12,
                recent_window=8,
                mean_drop_fraction=0.40,
                zscore_threshold=1.0,
            )
        )
        values = [0.30] * 12 + [-0.05, -0.04, -0.06, -0.03, -0.05, -0.04, -0.03, -0.06]
        sig = g.evaluate(values)
        self.assertTrue(sig.active)
        self.assertIn("POSITIVE_EDGE_COLLAPSE", sig.reasons)

    def test_stable_series_no_drift(self) -> None:
        g = DriftGuard(
            DriftPolicy(
                min_samples=20,
                baseline_window=12,
                recent_window=8,
                mean_drop_fraction=0.60,
                zscore_threshold=2.0,
            )
        )
        values = [0.10, 0.12, 0.09, 0.11, 0.10, 0.08, 0.09, 0.11, 0.10, 0.12, 0.09, 0.11,
                  0.10, 0.11, 0.09, 0.10, 0.12, 0.09, 0.10, 0.11]
        sig = g.evaluate(values)
        self.assertFalse(sig.active)
        self.assertIn("DRIFT_OK", sig.reasons)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
