# -*- coding: utf-8 -*-
import tempfile
import unittest
from pathlib import Path

from TOOLS import safetybot_cfg_inventory as inv


class TestSafetybotCfgInventory(unittest.TestCase):
    def test_build_inventory_finds_cfg_and_categories(self) -> None:
        root = Path(__file__).resolve().parents[1]
        payload = inv.build_inventory(root)
        self.assertEqual(str(payload.get("schema") or ""), "oanda.mt5.safetybot_cfg_inventory.v1")
        fields = payload.get("fields") or []
        self.assertTrue(fields)
        names = {str(x.get("name") or ""): x for x in fields}
        self.assertIn("risk_per_trade_max_pct", names)
        self.assertIn("fx_signal_score_threshold", names)
        self.assertIn("self_heal_enabled", names)
        self.assertEqual(
            str((names.get("risk_per_trade_max_pct") or {}).get("category") or ""),
            "NIENARUSZALNE_KAPITAL_I_BEZPIECZENSTWO",
        )
        self.assertEqual(
            str((names.get("fx_signal_score_threshold") or {}).get("category") or ""),
            "MIEKKIE_PROGI_DO_UCZENIA",
        )
        self.assertEqual(
            str((names.get("self_heal_enabled") or {}).get("category") or ""),
            "ADAPTACYJNE_RUNTIME",
        )

    def test_main_outputs_inventory_files(self) -> None:
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as td:
            out_dir = Path(td)
            payload = inv.build_inventory(root)
            out_json = out_dir / "safetybot_cfg_inventory_latest.json"
            out_md = out_dir / "safetybot_cfg_inventory_latest.md"
            out_json.write_text(__import__("json").dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            out_md.write_text(inv._render_markdown(payload), encoding="utf-8")
            self.assertTrue(out_json.exists())
            self.assertTrue(out_md.exists())


if __name__ == "__main__":
    raise SystemExit(unittest.main())
