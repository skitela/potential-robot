# -*- coding: utf-8 -*-
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class TestBudgetContractVE(unittest.TestCase):
    def test_budget_log_contains_required_fields(self):
        p = ROOT / "BIN" / "safetybot.py"
        txt = p.read_text(encoding="utf-8", errors="replace")

        # Locate the BUDGET log block in scan_once and verify required tokens are present within that block.
        anchor = 'f"BUDGET day_ny='
        i = txt.find(anchor)
        self.assertNotEqual(i, -1, "Missing BUDGET log line anchor in SafetyBot.scan_once")

        # Take a window that should cover the entire logging.info(...) call.
        window = txt[i:i+1200]

        required = [
            "BUDGET",
            "day_ny=",
            "utc_day=",
            "price_requests_day=",
            "order_actions_day=",
            "sys_requests_day=",
            "price_budget=",
            "order_budget=",
            "sys_budget=",
            "eco=",
        ]
        for token in required:
            self.assertIn(token, window, f"Missing token in BUDGET log block: {token}")

    def test_cfg_budget_defaults_explicit(self):
        p = ROOT / "BIN" / "safetybot.py"
        txt = p.read_text(encoding="utf-8", errors="replace")
        # Explicit internal budgets required by Contract E
        self.assertIn("price_budget_day: int = 400", txt)
        self.assertIn("order_budget_day: int = 400", txt)
        self.assertIn("sys_budget_day: int = 400", txt)
        self.assertIn("eco_threshold_pct: float = 0.80", txt)
        # Appendix 3 warning/cutoff must be correct
        self.assertIn("oanda_price_warning_per_day: int = 1000", txt)
        self.assertIn("oanda_price_cutoff_per_day: int = 5000", txt)

if __name__ == "__main__":
    unittest.main()
