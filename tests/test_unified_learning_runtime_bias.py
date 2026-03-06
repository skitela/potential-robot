# -*- coding: utf-8 -*-
import unittest

from BIN.safetybot import resolve_unified_learning_family_adjustment


class TestUnifiedLearningRuntimeBias(unittest.TestCase):
    def test_exact_window_and_family_can_suppress(self) -> None:
        payload = {
            "instruments": {
                "EURUSD": {
                    "advisory_bias": "SUPPRESS",
                    "window_advisory": [
                        {
                            "window": "FX_AM|ACTIVE",
                            "samples_n": 40,
                            "recommendation": "DOCISKAJ_FILTRY",
                            "counterfactual_pnl_points_avg": -6.0,
                        }
                    ],
                    "strategy_family_advisory": [
                        {
                            "window": "FX_AM|ACTIVE",
                            "strategy_family": "TREND_CONTINUATION",
                            "samples_n": 35,
                            "recommendation": "DOCISKAJ_FILTRY",
                            "counterfactual_pnl_points_avg": -9.0,
                        }
                    ],
                }
            }
        }
        out = resolve_unified_learning_family_adjustment(
            unified=payload,
            symbol="EURUSD",
            window_id="FX_AM",
            window_phase="ACTIVE",
            strategy_family="TREND_CONTINUATION",
            min_samples=20,
            max_abs_delta=6,
        )
        self.assertLess(int(out.get("score_delta") or 0), 0)
        self.assertEqual(str(out.get("advisory_bias") or ""), "SUPPRESS")

    def test_exact_window_and_family_can_promote(self) -> None:
        payload = {
            "instruments": {
                "GBPUSD": {
                    "advisory_bias": "PROMOTE",
                    "window_advisory": [
                        {
                            "window": "FX_PM|ACTIVE",
                            "samples_n": 50,
                            "recommendation": "ROZWAZ_LUZOWANIE_W_SHADOW",
                            "counterfactual_pnl_points_avg": 7.0,
                        }
                    ],
                    "strategy_family_advisory": [
                        {
                            "window": "FX_PM|ACTIVE",
                            "strategy_family": "RANGE_PULLBACK",
                            "samples_n": 44,
                            "recommendation": "ROZWAZ_LUZOWANIE_W_SHADOW",
                            "counterfactual_pnl_points_avg": 11.0,
                        }
                    ],
                }
            }
        }
        out = resolve_unified_learning_family_adjustment(
            unified=payload,
            symbol="GBPUSD",
            window_id="FX_PM",
            window_phase="ACTIVE",
            strategy_family="RANGE_PULLBACK",
            min_samples=20,
            max_abs_delta=6,
        )
        self.assertGreater(int(out.get("score_delta") or 0), 0)
        self.assertEqual(str(out.get("advisory_bias") or ""), "PROMOTE")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
