import re
import unittest
from pathlib import Path

class TestRiskPolicyDefaults(unittest.TestCase):
    def test_cfg_defaults_are_stable(self):
        p = Path(__file__).resolve().parents[1] / "BIN" / "safetybot.py"
        src = p.read_text(encoding="utf-8", errors="replace")

        expected = {
            "calendar_day_policy": '"PL_WARSAW"',
            "daily_loss_soft_pct": "0.02",
            "daily_loss_hard_pct": "0.03",
            "black_swan_threshold": "3.0",
            "black_swan_precaution_fraction": "0.8",
            "kill_switch_on_black_swan_stress": "True",
            "kill_switch_black_swan_multiplier": "1.0",
            "self_heal_enabled": "True",
            "self_heal_lookback_sec": "10800",
            "self_heal_min_deals_in_window": "3",
            "self_heal_loss_streak_trigger": "3",
            "self_heal_max_net_loss_abs": "0.0",
            "self_heal_backoff_s": "900",
            "self_heal_symbol_cooldown_s": "600",
            "self_heal_recent_deals_limit": "64",
            "canary_rollout_enabled": "True",
            "canary_lookback_sec": "86400",
            "canary_promote_min_deals": "15",
            "canary_promote_min_net_pnl": "0.0",
            "canary_pause_loss_streak": "3",
            "canary_pause_net_loss_abs": "0.0",
            "canary_max_error_incidents": "3",
            "canary_max_symbols_per_iter": "1",
            "canary_backoff_s": "900",
            "drift_guard_enabled": "True",
            "drift_min_samples": "30",
            "drift_baseline_window": "30",
            "drift_recent_window": "15",
            "drift_mean_drop_fraction": "0.40",
            "drift_zscore_threshold": "1.8",
            "drift_backoff_s": "900",
            "learner_qa_gate_enabled": "True",
            "learner_qa_red_to_eco": "True",
            "learner_qa_yellow_symbol_cap": "1",
            "risk_per_trade_max_pct": "0.015",
            "risk_scalp_pct": "0.003",
            "risk_scalp_min_pct": "0.002",
            "risk_scalp_max_pct": "0.004",
            "risk_swing_pct": "0.01",
            "risk_swing_min_pct": "0.008",
            "risk_swing_max_pct": "0.015",
            "max_open_risk_pct": "0.018",
            "max_positions_parallel": "5",
            "max_positions_per_symbol": "1",
            "spread_gate_hot_factor": "1.25",
            "spread_gate_warm_factor": "1.75",
            "spread_gate_eco_factor": "2.00",
        }

        missing = []
        for k, v in expected.items():
            if str(v).startswith(("'", '"')):
                vv = re.escape(str(v))
                pat = re.compile(rf"\b{k}\b\s*(?::\s*[A-Za-z_][A-Za-z0-9_\[\]]*)?\s*=\s*{vv}")
            else:
                pat = re.compile(rf"\b{k}\b\s*(?::\s*[A-Za-z_][A-Za-z0-9_\[\]]*)?\s*=\s*{v}\b")
            if not pat.search(src):
                missing.append(f"{k}={v}")

        self.assertFalse(missing, f"Risk defaults missing/changed: {missing}")

if __name__ == "__main__":
    raise SystemExit(unittest.main())
