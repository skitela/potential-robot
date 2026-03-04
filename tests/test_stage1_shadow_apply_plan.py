# -*- coding: utf-8 -*-
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


def _write_deployer(path: Path, status: str = "PASS") -> None:
    payload = {
        "schema": "oanda.mt5.stage1_shadow_deployer_plan.v1",
        "run_id": "DEPLOYER_RUN_001",
        "status": status,
        "instruments": [
            {
                "symbol": "EURUSD",
                "decision": "SELECTED_FOR_SHADOW",
                "selected_profile": "SREDNI",
                "thresholds": {"spread_cap_points": 24.0},
            },
            {
                "symbol": "GBPUSD",
                "decision": "HOLD",
                "selected_profile": "BEZPIECZNY",
                "thresholds": {"spread_cap_points": 20.0},
            },
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


class TestStage1ShadowApplyPlan(unittest.TestCase):
    def test_builds_apply_actions_from_deployer(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"
            deployer = lab / "reports" / "stage1" / "stage1_shadow_deployer_latest.json"
            _write_deployer(deployer, status="PASS")

            cmd = [
                sys.executable,
                "TOOLS/stage1_shadow_apply_plan.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
            self.assertIn("status=PASS", proc.stdout or "")

            latest = lab / "reports" / "stage1" / "stage1_shadow_apply_plan_latest.json"
            self.assertTrue(latest.exists())
            rep = json.loads(latest.read_text(encoding="utf-8"))
            self.assertEqual(rep.get("status"), "PASS")
            actions = rep.get("actions", [])
            self.assertEqual(len(actions), 1)
            self.assertEqual(actions[0].get("symbol"), "EURUSD")

    def test_skips_when_deployer_not_ready(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"
            deployer = lab / "reports" / "stage1" / "stage1_shadow_deployer_latest.json"
            _write_deployer(deployer, status="SKIP")

            cmd = [
                sys.executable,
                "TOOLS/stage1_shadow_apply_plan.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
            latest = lab / "reports" / "stage1" / "stage1_shadow_apply_plan_latest.json"
            rep = json.loads(latest.read_text(encoding="utf-8"))
            self.assertEqual(rep.get("status"), "SKIP")
            self.assertEqual(rep.get("reason"), "DEPLOYER_NOT_READY")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
