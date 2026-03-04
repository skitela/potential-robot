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


class TestStage1IterationAudit(unittest.TestCase):
    def test_builds_review_required_report(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"

            _write_json(
                root / "EVIDENCE" / "learning_dataset_quality" / "stage1_dataset_quality_test.json",
                {"verdict": {"status": "PASS"}, "summary": {"symbols_total": 4}},
            )
            _write_json(
                root / "EVIDENCE" / "learning_coverage" / "rejected_coverage_gate_test.json",
                {"verdict": {"status": "HOLD", "blockers": ["EURUSD:TOTAL_LT_MIN:0<30"]}},
            )
            _write_json(lab / "reports" / "stage1" / "stage1_profile_pack_eval_latest.json", {"status": "PASS"})
            _write_json(
                lab / "reports" / "stage1" / "stage1_shadow_deployer_latest.json",
                {
                    "status": "PASS",
                    "reason": "SHADOW_PLAN_READY",
                    "mode": "SHADOW_ONLY",
                    "auto_apply": False,
                    "human_decision_required": False,
                },
            )
            _write_json(
                lab / "reports" / "stage1" / "stage1_shadow_apply_plan_latest.json",
                {"status": "PASS", "reason": "APPLY_PLAN_READY", "runtime_mutation": False},
            )
            _write_json(
                lab / "reports" / "stage1" / "stage1_shadow_gonogo_latest.json",
                {"verdict": "REVIEW_REQUIRED", "status": "WARN"},
            )
            _write_json(
                lab / "run" / "stage1_manual_approval.json",
                {"schema": "oanda.mt5.stage1_manual_approval.v1", "approved": True, "instruments": {"EURUSD": "AUTO"}},
            )

            cmd = [
                sys.executable,
                "TOOLS/stage1_iteration_audit.py",
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
            self.assertIn("verdict=REVIEW_REQUIRED", proc.stdout or "")

            latest = lab / "reports" / "stage1" / "stage1_iteration_audit_latest.json"
            self.assertTrue(latest.exists())
            rep = json.loads(latest.read_text(encoding="utf-8"))
            self.assertEqual(((rep.get("J") or {}).get("werdykt_koncowy")), "REVIEW_REQUIRED")
            self.assertEqual(((rep.get("D") or {}).get("status")), "PASS")

    def test_derives_nogo_without_gonogo_file(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"

            _write_json(
                root / "EVIDENCE" / "learning_dataset_quality" / "stage1_dataset_quality_test.json",
                {"verdict": {"status": "HOLD"}},
            )
            _write_json(
                root / "EVIDENCE" / "learning_coverage" / "rejected_coverage_gate_test.json",
                {"verdict": {"status": "PASS"}},
            )
            _write_json(lab / "reports" / "stage1" / "stage1_profile_pack_eval_latest.json", {"status": "PASS"})
            _write_json(
                lab / "reports" / "stage1" / "stage1_shadow_deployer_latest.json",
                {"status": "PASS", "reason": "SHADOW_PLAN_READY", "mode": "SHADOW_ONLY", "auto_apply": False},
            )
            _write_json(
                lab / "reports" / "stage1" / "stage1_shadow_apply_plan_latest.json",
                {"status": "PASS", "reason": "APPLY_PLAN_READY", "runtime_mutation": False},
            )

            cmd = [
                sys.executable,
                "TOOLS/stage1_iteration_audit.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
            self.assertIn("verdict=NO-GO", proc.stdout or "")
            rep = json.loads((lab / "reports" / "stage1" / "stage1_iteration_audit_latest.json").read_text(encoding="utf-8"))
            self.assertEqual(((rep.get("J") or {}).get("werdykt_koncowy")), "NO-GO")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
