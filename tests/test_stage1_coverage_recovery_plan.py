# -*- coding: utf-8 -*-
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


class TestStage1CoverageRecoveryPlan(unittest.TestCase):
    def test_warn_when_hold_symbols_present(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"
            _write_json(
                root / "EVIDENCE" / "learning_coverage" / "rejected_coverage_gate_test.json",
                {
                    "verdict": {"status": "HOLD"},
                    "thresholds": {
                        "min_total_per_symbol": 30,
                        "min_rejects_per_symbol": 10,
                        "min_trade_events_per_symbol": 1,
                    },
                    "symbols": [
                        {
                            "symbol": "EURUSD",
                            "status": "HOLD",
                            "total_events_n": 0,
                            "rejected_candidates_n": 0,
                            "trade_events_n": 0,
                            "reasons": ["TOTAL_LT_MIN:0<30"],
                        }
                    ],
                },
            )
            cmd = [
                sys.executable,
                "TOOLS/stage1_coverage_recovery_plan.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
                "--focus-group",
                "FX",
                "--lookback-hours",
                "24",
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
            self.assertIn("status=WARN", proc.stdout or "")
            rep = json.loads((lab / "reports" / "stage1" / "stage1_coverage_recovery_latest.json").read_text(encoding="utf-8"))
            self.assertEqual(rep.get("status"), "WARN")
            self.assertEqual(len(rep.get("actions_by_symbol", [])), 1)

    def test_pass_when_no_hold_symbols(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"
            _write_json(
                root / "EVIDENCE" / "learning_coverage" / "rejected_coverage_gate_test.json",
                {
                    "verdict": {"status": "PASS"},
                    "thresholds": {
                        "min_total_per_symbol": 30,
                        "min_rejects_per_symbol": 10,
                        "min_trade_events_per_symbol": 1,
                    },
                    "symbols": [
                        {
                            "symbol": "USDJPY",
                            "status": "PASS",
                            "total_events_n": 55,
                            "rejected_candidates_n": 40,
                            "trade_events_n": 15,
                            "reasons": [],
                        }
                    ],
                },
            )
            cmd = [
                sys.executable,
                "TOOLS/stage1_coverage_recovery_plan.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
            self.assertIn("status=PASS", proc.stdout or "")
            rep = json.loads((lab / "reports" / "stage1" / "stage1_coverage_recovery_latest.json").read_text(encoding="utf-8"))
            self.assertEqual(rep.get("status"), "PASS")
            self.assertEqual(len(rep.get("actions_by_symbol", [])), 0)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
