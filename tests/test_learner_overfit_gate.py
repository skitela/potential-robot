import unittest

from BIN import learner_offline


class TestLearnerOverfitGate(unittest.TestCase):
    def test_gate_red_for_low_n(self) -> None:
        light, reasons = learner_offline._anti_overfit_light(
            n_total=20,
            rank_corr_half=0.9,
            topk_churn=0.8,
            loss_streak_p5=0.0,
            stress_pnl_mean_2x=0.1,
        )
        self.assertEqual(light, "RED")
        self.assertIn("N_TOO_LOW", reasons)

    def test_gate_green_when_stable(self) -> None:
        light, reasons = learner_offline._anti_overfit_light(
            n_total=120,
            rank_corr_half=0.45,
            topk_churn=0.55,
            loss_streak_p5=0.05,
            stress_pnl_mean_2x=0.2,
        )
        self.assertEqual(light, "GREEN")
        self.assertIn("STABLE", reasons)

    def test_gate_yellow_single_warning(self) -> None:
        light, reasons = learner_offline._anti_overfit_light(
            n_total=90,
            rank_corr_half=0.04,
            topk_churn=0.35,
            loss_streak_p5=0.05,
            stress_pnl_mean_2x=0.2,
        )
        self.assertEqual(light, "YELLOW")
        self.assertIn("RANK_UNSTABLE", reasons)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
