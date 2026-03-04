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


class TestStage1ShadowGoNoGo(unittest.TestCase):
    def test_verdict_pass_when_all_checks_pass(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"

            _write_json(root / "EVIDENCE" / "learning_dataset_quality" / "stage1_dataset_quality_test.json", {"verdict": "PASS"})
            _write_json(root / "EVIDENCE" / "learning_coverage" / "rejected_coverage_gate_test.json", {"verdict": "PASS"})
            _write_json(lab / "reports" / "stage1" / "stage1_profile_pack_eval_latest.json", {"status": "PASS"})
            _write_json(
                lab / "reports" / "stage1" / "stage1_shadow_deployer_latest.json",
                {"schema": "oanda.mt5.stage1_shadow_deployer_plan.v1", "status": "PASS", "reason": "SHADOW_PLAN_READY"},
            )
            _write_json(lab / "reports" / "stage1" / "stage1_shadow_apply_plan_latest.json", {"status": "PASS", "reason": "APPLY_PLAN_READY"})

            cmd = [
                sys.executable,
                "TOOLS/stage1_shadow_gonogo.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
            self.assertIn("verdict=PASS", proc.stdout or "")
            rep = json.loads((lab / "reports" / "stage1" / "stage1_shadow_gonogo_latest.json").read_text(encoding="utf-8"))
            self.assertEqual(rep.get("verdict"), "PASS")

    def test_verdict_review_required_on_manual_gate(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"

            _write_json(root / "EVIDENCE" / "learning_dataset_quality" / "stage1_dataset_quality_test.json", {"verdict": "PASS"})
            _write_json(root / "EVIDENCE" / "learning_coverage" / "rejected_coverage_gate_test.json", {"verdict": "HOLD"})
            _write_json(lab / "reports" / "stage1" / "stage1_profile_pack_eval_latest.json", {"status": "PASS"})
            _write_json(
                lab / "reports" / "stage1" / "stage1_shadow_deployer_latest.json",
                {"schema": "oanda.mt5.stage1_shadow_deployer_plan.v1", "status": "SKIP", "reason": "HUMAN_APPROVAL_REQUIRED"},
            )
            _write_json(lab / "reports" / "stage1" / "stage1_shadow_apply_plan_latest.json", {"status": "SKIP", "reason": "DEPLOYER_NOT_READY"})

            cmd = [
                sys.executable,
                "TOOLS/stage1_shadow_gonogo.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
            self.assertIn("verdict=REVIEW_REQUIRED", proc.stdout or "")
            rep = json.loads((lab / "reports" / "stage1" / "stage1_shadow_gonogo_latest.json").read_text(encoding="utf-8"))
            self.assertEqual(rep.get("verdict"), "REVIEW_REQUIRED")
            self.assertIn("manual_approval", rep.get("operator_decisions_required", []))

    def test_verdict_nogo_when_dataset_quality_fail(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"

            _write_json(root / "EVIDENCE" / "learning_dataset_quality" / "stage1_dataset_quality_test.json", {"verdict": "HOLD"})
            _write_json(root / "EVIDENCE" / "learning_coverage" / "rejected_coverage_gate_test.json", {"verdict": "PASS"})
            _write_json(lab / "reports" / "stage1" / "stage1_profile_pack_eval_latest.json", {"status": "PASS"})
            _write_json(
                lab / "reports" / "stage1" / "stage1_shadow_deployer_latest.json",
                {"schema": "oanda.mt5.stage1_shadow_deployer_plan.v1", "status": "PASS", "reason": "SHADOW_PLAN_READY"},
            )
            _write_json(lab / "reports" / "stage1" / "stage1_shadow_apply_plan_latest.json", {"status": "PASS", "reason": "APPLY_PLAN_READY"})

            cmd = [
                sys.executable,
                "TOOLS/stage1_shadow_gonogo.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("verdict=NO-GO", proc.stdout or "")
            rep = json.loads((lab / "reports" / "stage1" / "stage1_shadow_gonogo_latest.json").read_text(encoding="utf-8"))
            self.assertEqual(rep.get("verdict"), "NO-GO")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
