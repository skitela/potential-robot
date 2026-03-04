# -*- coding: utf-8 -*-
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


def _write_profile_pack(path: Path) -> None:
    payload = {
        "schema": "oanda.mt5.stage1_profile_pack.v1",
        "profiles_by_symbol": [
            {
                "symbol": "EURUSD",
                "profiles": {
                    "bezpieczny": {"profile_name": "BEZPIECZNY", "evaluation": {"score_estimate": 0.12}},
                    "sredni": {"profile_name": "SREDNI", "evaluation": {"score_estimate": 0.16}},
                    "odwazniejszy": {"profile_name": "ODWAZNIEJSZY", "evaluation": {"score_estimate": 0.22}},
                },
            }
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _write_shadow_report(path: Path) -> None:
    payload = {
        "schema": "oanda_mt5.shadow_policy_daily_report.v1",
        "status": "PASS",
        "results_per_day_window_symbol": {
            "explore": [
                {"symbol": "EURUSD", "trades": 3, "net_pips_sum": -18.0, "net_pips_per_trade": -6.0},
                {"symbol": "EURUSD", "trades": 3, "net_pips_sum": -12.0, "net_pips_per_trade": -4.0},
            ]
        },
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


class TestStage1ProfilePackEvaluate(unittest.TestCase):
    def test_evaluates_profiles_and_writes_latest(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"
            stage1 = lab / "reports" / "stage1"
            shadow = lab / "reports" / "shadow_policy"
            profile_pack = stage1 / "stage1_profile_pack_test.json"
            shadow_report = shadow / "shadow_policy_baseline_test.json"

            _write_profile_pack(profile_pack)
            _write_shadow_report(shadow_report)

            cmd = [
                sys.executable,
                "TOOLS/stage1_profile_pack_evaluate.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
                "--profile-pack",
                str(profile_pack),
                "--shadow-report",
                str(shadow_report),
                "--min-shadow-trades",
                "3",
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
            self.assertIn("status=PASS", proc.stdout or "")

            reports = sorted(stage1.glob("stage1_profile_pack_eval_*.json"))
            self.assertTrue(reports)
            rep = json.loads(reports[-1].read_text(encoding="utf-8"))
            self.assertEqual(rep.get("status"), "PASS")
            rows = rep.get("evaluation_by_symbol", [])
            self.assertEqual(len(rows), 1)
            rec = ((rows[0].get("recommendation_for_tomorrow") or {}).get("recommended_profile") or "")
            self.assertNotEqual(rec, "ODWAZNIEJSZY")

            latest = stage1 / "stage1_profile_pack_eval_latest.json"
            self.assertTrue(latest.exists())


if __name__ == "__main__":
    raise SystemExit(unittest.main())
