# -*- coding: utf-8 -*-
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class TestRuntimeMinesVF(unittest.TestCase):
    def test_request_governor_group_methods_exist(self):
        p = ROOT / "BIN" / "safetybot.py"
        txt = p.read_text(encoding="utf-8", errors="replace")
        self.assertIn("def _group_price_cap", txt)
        self.assertIn("def _group_borrow_allowance", txt)

    def test_set_cooldown_is_not_blocked_by_mt5(self):
        p = ROOT / "BIN" / "safetybot.py"
        txt = p.read_text(encoding="utf-8", errors="replace")
        start = txt.find("def set_cooldown")
        self.assertNotEqual(start, -1)
        window = txt[start:start+450]
        self.assertNotIn("if mt5 is None", window)
        self.assertNotIn("return None", window)

    def test_order_throttle_can_trade_returns_bool(self):
        p = ROOT / "BIN" / "safetybot.py"
        txt = p.read_text(encoding="utf-8", errors="replace")
        anchor = "def can_trade(self) -> bool:"
        i = txt.find(anchor)
        self.assertNotEqual(i, -1)
        window = txt[i:i+220]
        self.assertIn("return False", window)
        self.assertNotIn("return None", window)
