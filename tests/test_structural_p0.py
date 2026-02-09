import ast
import unittest
from pathlib import Path

def _get_class(tree, name: str):
    for n in tree.body:
        if isinstance(n, ast.ClassDef) and n.name == name:
            return n
    return None

def _get_method_names(cls: ast.ClassDef):
    return {n.name for n in cls.body if isinstance(n, ast.FunctionDef)}

class TestStructuralP0(unittest.TestCase):
    def _parse(self):
        p = Path(__file__).resolve().parents[1] / "BIN" / "safetybot.py"
        src = p.read_text(encoding="utf-8")
        return ast.parse(src)

    def test_request_governor_has_day_state(self):
        tree = self._parse()
        cls = _get_class(tree, "RequestGovernor")
        self.assertIsNotNone(cls, "RequestGovernor class missing")
        methods = _get_method_names(cls)
        self.assertIn("day_state", methods, "RequestGovernor.day_state missing (indentation or definition error)")

    def test_mt5client_has_order_send(self):
        tree = self._parse()
        cls = _get_class(tree, "MT5Client")
        self.assertIsNotNone(cls, "MT5Client class missing")
        methods = _get_method_names(cls)
        self.assertIn("order_send", methods, "MT5Client.order_send missing (indentation or definition error)")
