# -*- coding: utf-8 -*-
import unittest

from BIN import learner_offline


class TestTrainingQuality(unittest.TestCase):
    def test_streak_stats(self):
        pnls = [1.0, -1.0, -2.0, -3.0, 2.0, 3.0, -1.0, -1.0, -1.0, -1.0]
        st = learner_offline._streak_stats(pnls)
        self.assertEqual(int(st.get("max_loss_streak")), 4)
        self.assertEqual(int(st.get("max_win_streak")), 2)
        self.assertGreaterEqual(float(st.get("loss_streak_p3")), 0.5)

    def test_chop_risk_bucket(self):
        edges_high = [0.1, -0.1] * 20
        edges_low = [0.2] * 30
        self.assertEqual(learner_offline._chop_risk_bucket(edges_high), "HIGH")
        self.assertEqual(learner_offline._chop_risk_bucket(edges_low), "LOW")

    def test_rank_corr(self):
        a = {"A": 3.0, "B": 2.0, "C": 1.0, "D": 0.0, "E": -1.0}
        b = {"A": 3.0, "B": 2.0, "C": 1.0, "D": 0.0, "E": -1.0}
        c = {"A": -1.0, "B": 0.0, "C": 1.0, "D": 2.0, "E": 3.0}
        self.assertAlmostEqual(float(learner_offline._rank_corr(a, b)), 1.0, places=6)
        self.assertAlmostEqual(float(learner_offline._rank_corr(a, c)), -1.0, places=6)

    def test_score_delta_mean(self):
        a = {"A": 2.0, "B": 1.0, "C": 0.0, "D": -1.0, "E": -2.0}
        b = {"A": 1.0, "B": 1.0, "C": 1.0, "D": 1.0, "E": 1.0}
        d = learner_offline._score_delta_mean(a, b)
        self.assertAlmostEqual(float(d), -1.0, places=6)

    def test_topk_churn_and_hits(self):
        topk = [
            ["A", "B", "C"],
            ["A", "C", "D"],
        ]
        churn = learner_offline._topk_churn(topk)
        self.assertAlmostEqual(float(churn), 0.5, places=6)
        hits = learner_offline._topk_hit_rates(topk)
        hit_map = {h["symbol"]: h["hit_rate"] for h in hits}
        self.assertAlmostEqual(float(hit_map.get("A", 0.0)), 1.0, places=6)
        self.assertAlmostEqual(float(hit_map.get("B", 0.0)), 0.5, places=6)


if __name__ == "__main__":
    unittest.main()
