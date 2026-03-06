# -*- coding: utf-8 -*-
import unittest

from BIN.safetybot import resolve_unified_learning_family_adjustment, resolve_unified_learning_rank_adjustment


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
                    "source_feedback": {
                        "leader": "LEARNING",
                        "learning_weight": 1.18,
                    },
                    "window_advisory": [
                        {
                            "window": "FX_PM|ACTIVE",
                            "samples_n": 50,
                            "recommendation": "ROZWAZ_LUZOWANIE_W_SHADOW",
                            "counterfactual_pnl_points_avg": 7.0,
                            "source_feedback": {
                                "leader": "LEARNING",
                                "learning_weight": 1.18,
                            },
                        }
                    ],
                    "strategy_family_advisory": [
                        {
                            "window": "FX_PM|ACTIVE",
                            "strategy_family": "RANGE_PULLBACK",
                            "samples_n": 44,
                            "recommendation": "ROZWAZ_LUZOWANIE_W_SHADOW",
                            "counterfactual_pnl_points_avg": 11.0,
                            "source_feedback": {
                                "leader": "LEARNING",
                                "learning_weight": 1.18,
                            },
                        }
                    ],
                }
            },
            "raw": {
                "global": {
                    "source_feedback": {
                        "leader": "LEARNING",
                        "learning_weight": 1.10,
                    }
                }
            },
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
        self.assertGreater(float(out.get("feedback_weight") or 1.0), 1.0)

    def test_rank_adjustment_uses_feedback_weight(self) -> None:
        payload = {
            "instruments": {
                "EURUSD": {
                    "advisory_bias": "PROMOTE",
                    "consensus_score": 0.32,
                    "source_feedback": {
                        "leader": "LEARNING",
                        "learning_weight": 1.22,
                    },
                    "window_advisory": [
                        {
                            "window": "FX_AM|ACTIVE",
                            "samples_n": 48,
                            "recommendation": "ROZWAZ_LUZOWANIE_W_SHADOW",
                            "avg_points": 6.5,
                            "source_feedback": {
                                "leader": "LEARNING",
                                "learning_weight": 1.20,
                            },
                        }
                    ],
                }
            },
            "raw": {
                "global": {
                    "source_feedback": {
                        "leader": "LEARNING",
                        "learning_weight": 1.10,
                    }
                }
            },
        }
        out = resolve_unified_learning_rank_adjustment(
            unified=payload,
            symbol="EURUSD",
            window_id="FX_AM",
            window_phase="ACTIVE",
            min_samples=20,
            max_bonus_pct=0.08,
        )
        self.assertGreater(float(out.get("pct_bonus") or 0.0), 0.0)
        self.assertGreater(float(out.get("prio_multiplier") or 1.0), 1.0)
        self.assertGreater(float(out.get("feedback_weight") or 1.0), 1.0)
        self.assertEqual(str(out.get("feedback_leader") or ""), "LEARNING")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
