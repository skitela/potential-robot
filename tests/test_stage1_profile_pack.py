# -*- coding: utf-8 -*-
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


def _write_strategy(path: Path) -> None:
    payload = {
        "fx_spread_cap_points_default": 24.0,
        "metal_spread_cap_points_default": 120.0,
        "fx_signal_score_threshold": 64.0,
        "metal_signal_score_threshold": 66.0,
        "bridge_trade_timeout_ms": 1400,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _write_cf_summary(path: Path) -> None:
    payload = {
        "schema": "oanda.mt5.stage1_counterfactual_summary.v1",
        "aggregates": {
            "by_symbol": [
                {
                    "symbol": "EURUSD",
                    "samples_n": 40,
                    "saved_loss_n": 20,
                    "missed_opportunity_n": 8,
                    "neutral_timeout_n": 12,
                    "counterfactual_pnl_points_total": -80.0,
                    "counterfactual_pnl_points_avg": -2.0,
                },
                {
                    "symbol": "GBPUSD",
                    "samples_n": 12,
                    "saved_loss_n": 2,
                    "missed_opportunity_n": 7,
                    "neutral_timeout_n": 3,
                    "counterfactual_pnl_points_total": 24.0,
                    "counterfactual_pnl_points_avg": 2.0,
                },
            ]
        },
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _write_runtime_advice(path: Path) -> None:
    payload = {
        "schema": "oanda_mt5.unified_learning_advice.v1",
        "global": {
            "qa_light": "YELLOW",
        },
        "instruments": {
            "EURUSD": {
                "advisory_bias": "SUPPRESS",
                "consensus_score": -0.42,
                "counterfactual": {
                    "recommendation": "DOCISKAJ_FILTRY",
                    "samples_n": 120,
                },
            },
            "GBPUSD": {
                "advisory_bias": "PROMOTE",
                "consensus_score": 0.31,
                "counterfactual": {
                    "recommendation": "ROZWAZ_LUZOWANIE_W_SHADOW",
                    "samples_n": 80,
                },
            },
        },
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


class TestStage1ProfilePack(unittest.TestCase):
    def test_builds_three_profiles_per_symbol(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"
            summary = lab / "reports" / "stage1" / "stage1_counterfactual_summary_test.json"
            strategy = root / "CONFIG" / "strategy.json"
            runtime_advice = root / "META" / "unified_learning_advice.json"
            _write_cf_summary(summary)
            _write_strategy(strategy)
            _write_runtime_advice(runtime_advice)

            cmd = [
                sys.executable,
                "TOOLS/stage1_profile_pack.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
                "--counterfactual-summary",
                str(summary),
                "--strategy-path",
                str(strategy),
                "--runtime-advice-path",
                str(runtime_advice),
                "--min-samples",
                "30",
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
            self.assertIn("status=PASS", proc.stdout or "")

            reports = sorted((lab / "reports" / "stage1").glob("stage1_profile_pack_*.json"))
            self.assertTrue(reports)
            rep = json.loads(reports[-1].read_text(encoding="utf-8"))
            self.assertEqual(rep.get("status"), "PASS")
            rows = rep.get("profiles_by_symbol", [])
            self.assertEqual(len(rows), 2)

            eur = [x for x in rows if str(x.get("symbol")) == "EURUSD"]
            self.assertEqual(len(eur), 1)
            eur_profiles = eur[0].get("profiles") or {}
            self.assertIn("bezpieczny", eur_profiles)
            self.assertIn("sredni", eur_profiles)
            self.assertIn("odwazniejszy", eur_profiles)
            self.assertTrue((eur[0].get("recommendation_for_tomorrow") or {}).get("human_decision_required"))
            eur_bal = eur_profiles["sredni"]
            eur_thr = eur_bal.get("thresholds") or {}
            self.assertLess(float(eur_thr.get("spread_cap_points") or 0.0), 24.0)
            self.assertGreater(float(eur_thr.get("signal_score_threshold") or 0.0), 64.0)
            self.assertTrue((eur_bal.get("adaptive_overlay") or {}).get("enabled"))

            gbp = [x for x in rows if str(x.get("symbol")) == "GBPUSD"]
            self.assertEqual(len(gbp), 1)
            aggr = ((gbp[0].get("profiles") or {}).get("odwazniejszy") or {})
            elig = aggr.get("eligibility") or {}
            self.assertEqual(str(elig.get("status") or ""), "HOLD_LOW_SAMPLES")
            gbp_bal = ((gbp[0].get("profiles") or {}).get("sredni") or {})
            gbp_thr = gbp_bal.get("thresholds") or {}
            self.assertGreater(float(gbp_thr.get("spread_cap_points") or 0.0), 24.0)
            self.assertLess(float(gbp_thr.get("signal_score_threshold") or 999.0), 64.0)

            latest = lab / "reports" / "stage1" / "stage1_profile_pack_latest.json"
            self.assertTrue(latest.exists())


if __name__ == "__main__":
    raise SystemExit(unittest.main())
