# -*- coding: utf-8 -*-
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


def _write_rows(path: Path) -> None:
    rows = [
        {
            "symbol": "EURUSD",
            "window_id": "FX_AM",
            "window_phase": "ACTIVE",
            "strategy_family": "TREND_CONTINUATION",
            "counterfactual_status": "SAVED_LOSS",
            "counterfactual_pnl_points": -20.0,
        },
        {
            "symbol": "EURUSD",
            "window_id": "FX_AM",
            "window_phase": "ACTIVE",
            "strategy_family": "TREND_CONTINUATION",
            "counterfactual_status": "MISSED_OPPORTUNITY",
            "counterfactual_pnl_points": 12.0,
        },
        {
            "symbol": "GBPUSD",
            "window_id": "FX_PM",
            "window_phase": "ACTIVE",
            "strategy_family": "RANGE_PULLBACK",
            "counterfactual_status": "MISSED_OPPORTUNITY",
            "counterfactual_pnl_points": 15.0,
        },
        {
            "symbol": "GBPUSD",
            "window_id": "FX_PM",
            "window_phase": "ACTIVE",
            "strategy_family": "RANGE_PULLBACK",
            "counterfactual_status": "NEUTRAL_TIMEOUT",
            "counterfactual_pnl_points": -2.0,
        },
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")


class TestStage1CounterfactualSummary(unittest.TestCase):
    def test_summary_builds_per_symbol_and_window(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"
            stage1_dir = lab / "reports" / "stage1"
            stage1_dir.mkdir(parents=True, exist_ok=True)
            rows = stage1_dir / "stage1_counterfactual_rows_test.jsonl"
            _write_rows(rows)

            cmd = [
                sys.executable,
                "TOOLS/stage1_counterfactual_summary.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
                "--rows-jsonl",
                str(rows),
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
            self.assertIn("status=PASS", proc.stdout or "")

            reports = sorted(stage1_dir.glob("stage1_counterfactual_summary_*.json"))
            self.assertTrue(reports)
            rep = json.loads(reports[-1].read_text(encoding="utf-8"))
            self.assertEqual(rep.get("status"), "PASS")
            self.assertEqual(int((rep.get("summary") or {}).get("rows_total") or 0), 4)
            self.assertEqual(int((rep.get("summary") or {}).get("strategy_families_n") or 0), 2)

            by_symbol = rep.get("aggregates", {}).get("by_symbol", [])
            eur = [x for x in by_symbol if str(x.get("symbol")) == "EURUSD"]
            self.assertEqual(len(eur), 1)
            self.assertEqual(int(eur[0].get("saved_loss_n") or 0), 1)
            self.assertEqual(int(eur[0].get("missed_opportunity_n") or 0), 1)

            by_symbol_window_family = rep.get("aggregates", {}).get("by_symbol_window_family", [])
            eur_family = [x for x in by_symbol_window_family if str(x.get("symbol")) == "EURUSD"]
            self.assertEqual(len(eur_family), 1)
            self.assertEqual(str(eur_family[0].get("strategy_family") or ""), "TREND_CONTINUATION")

            latest = stage1_dir / "stage1_counterfactual_summary_latest.json"
            self.assertTrue(latest.exists())


if __name__ == "__main__":
    raise SystemExit(unittest.main())
