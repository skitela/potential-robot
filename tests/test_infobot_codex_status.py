import unittest

from BIN import infobot


class TestInfobotCodexStatus(unittest.TestCase):
    def test_codex_repair_view(self) -> None:
        text, color = infobot._repair_view("repairing_codex", 0)
        self.assertIn("CODEX", text)
        self.assertEqual(color, "orange")

    def test_internal_repair_view(self) -> None:
        text, color = infobot._repair_view("repairing", 2)
        self.assertIn("PROBA 2/3", text)
        self.assertEqual(color, "orange")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
