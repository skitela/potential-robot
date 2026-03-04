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


class TestStage1OperatorPopup(unittest.TestCase):
    def test_no_gui_review_required_decision_saved(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"
            stage1 = lab / "reports" / "stage1"
            _write_json(
                stage1 / "stage1_shadow_gonogo_latest.json",
                {"verdict": "REVIEW_REQUIRED", "status": "WARN", "reason": "CHECKS_WITH_WARNINGS"},
            )
            _write_json(
                stage1 / "stage1_coverage_recovery_latest.json",
                {"status": "WARN", "reason": "COVERAGE_GAPS_FOUND", "actions_by_symbol": [{"symbol": "EURUSD"}]},
            )
            _write_json(stage1 / "stage1_iteration_audit_latest.json", {"J": {"werdykt_koncowy": "REVIEW_REQUIRED"}})

            cmd = [
                sys.executable,
                "TOOLS/stage1_operator_popup.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
                "--no-gui",
                "--auto-action",
                "WSTRZYMAJ_I_DOZBIERAJ_DANE",
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
            self.assertIn("status=PASS", proc.stdout or "")
            latest = lab / "run" / "operator_decisions" / "stage1_operator_decision_latest.json"
            data = json.loads(latest.read_text(encoding="utf-8"))
            self.assertEqual(data.get("selected_action"), "WSTRZYMAJ_I_DOZBIERAJ_DANE")

    def test_invalid_auto_action_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"
            stage1 = lab / "reports" / "stage1"
            _write_json(stage1 / "stage1_shadow_gonogo_latest.json", {"verdict": "PASS", "status": "PASS"})
            _write_json(stage1 / "stage1_coverage_recovery_latest.json", {"status": "PASS", "reason": "COVERAGE_OK"})

            cmd = [
                sys.executable,
                "TOOLS/stage1_operator_popup.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
                "--no-gui",
                "--auto-action",
                "NIEISTNIEJACA_AKCJA",
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 2)
            self.assertIn("INVALID_AUTO_ACTION", proc.stdout or "")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
