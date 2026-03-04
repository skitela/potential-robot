# -*- coding: utf-8 -*-
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


def _write_eval(path: Path) -> None:
    payload = {
        "schema": "oanda.mt5.stage1_profile_pack_eval.v1",
        "evaluation_by_symbol": [
            {
                "symbol": "EURUSD",
                "recommendation_for_tomorrow": {"recommended_profile": "SREDNI"},
            }
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _write_pack(path: Path) -> None:
    payload = {
        "schema": "oanda.mt5.stage1_profile_pack.v1",
        "profiles_by_symbol": [
            {
                "symbol": "EURUSD",
                "profiles": {
                    "bezpieczny": {
                        "profile_name": "BEZPIECZNY",
                        "thresholds": {
                            "spread_cap_points": 21.12,
                            "signal_score_threshold": 68.0,
                            "max_latency_ms": 850.0,
                            "min_tradeability_score": 0.62,
                            "min_setup_quality_score": 0.62,
                        },
                    },
                    "sredni": {
                        "profile_name": "SREDNI",
                        "thresholds": {
                            "spread_cap_points": 24.0,
                            "signal_score_threshold": 64.0,
                            "max_latency_ms": 950.0,
                            "min_tradeability_score": 0.55,
                            "min_setup_quality_score": 0.55,
                        },
                    },
                },
            }
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _write_approval(path: Path, approved: bool = True) -> None:
    payload = {
        "schema": "oanda.mt5.stage1_manual_approval.v1",
        "generated_at_utc": "2026-03-04T00:00:00Z",
        "approved": bool(approved),
        "ticket": "MANUAL-001",
        "instruments": {"EURUSD": "AUTO"},
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


class TestStage1ShadowDeployer(unittest.TestCase):
    def test_requires_human_approval_when_file_missing(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"
            eval_path = lab / "reports" / "stage1" / "stage1_profile_pack_eval_latest.json"
            pack_path = lab / "reports" / "stage1" / "stage1_profile_pack_latest.json"
            _write_eval(eval_path)
            _write_pack(pack_path)

            cmd = [
                sys.executable,
                "TOOLS/stage1_shadow_deployer.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
            self.assertIn("status=SKIP", proc.stdout or "")

            latest = lab / "reports" / "stage1" / "stage1_shadow_deployer_latest.json"
            self.assertTrue(latest.exists())
            rep = json.loads(latest.read_text(encoding="utf-8"))
            self.assertEqual(rep.get("status"), "SKIP")
            self.assertEqual(rep.get("reason"), "HUMAN_APPROVAL_REQUIRED")
            self.assertTrue(rep.get("human_decision_required"))

    def test_selects_profile_when_approved(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"
            eval_path = lab / "reports" / "stage1" / "stage1_profile_pack_eval_latest.json"
            pack_path = lab / "reports" / "stage1" / "stage1_profile_pack_latest.json"
            approval = lab / "run" / "stage1_manual_approval.json"
            _write_eval(eval_path)
            _write_pack(pack_path)
            _write_approval(approval, approved=True)

            cmd = [
                sys.executable,
                "TOOLS/stage1_shadow_deployer.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
                "--cooldown-minutes",
                "30",
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
            self.assertIn("status=PASS", proc.stdout or "")

            latest = lab / "reports" / "stage1" / "stage1_shadow_deployer_latest.json"
            self.assertTrue(latest.exists())
            rep = json.loads(latest.read_text(encoding="utf-8"))
            self.assertEqual(rep.get("status"), "PASS")
            rows = rep.get("instruments", [])
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0].get("decision"), "SELECTED_FOR_SHADOW")
            self.assertEqual(rows[0].get("selected_profile"), "SREDNI")
            self.assertFalse(rep.get("human_decision_required"))

            state = lab / "run" / "stage1_shadow_deployer_state.json"
            self.assertTrue(state.exists())
            st = json.loads(state.read_text(encoding="utf-8"))
            row = ((st.get("instruments") or {}).get("EURUSD") or {})
            self.assertEqual(str(row.get("active_profile") or ""), "SREDNI")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
