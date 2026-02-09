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
