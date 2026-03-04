# -*- coding: utf-8 -*-
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class TestStage1Approve(unittest.TestCase):
    def test_writes_approval_file_with_overrides(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"
            (root / "LAB" / "CONFIG").mkdir(parents=True, exist_ok=True)
            tmpl = root / "LAB" / "CONFIG" / "stage1_manual_approval.template.json"
            tmpl.write_text(
                json.dumps(
                    {
                        "schema": "oanda.mt5.stage1_manual_approval.v1",
                        "generated_at_utc": "2026-03-04T00:00:00Z",
                        "approved": False,
                        "ticket": "TMP",
                        "comment": "",
                        "instruments": {"EURUSD": "AUTO"},
                    },
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )

            cmd = [
                sys.executable,
                "TOOLS/stage1_approve.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
                "--approved",
                "true",
                "--ticket",
                "MANUAL-123",
                "--instrument-profile",
                "EURUSD=SREDNI",
                "--instrument-profile",
                "GBPUSD=BEZPIECZNY",
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
            self.assertIn("status=PASS", proc.stdout or "")

            approval = lab / "run" / "stage1_manual_approval.json"
            self.assertTrue(approval.exists())
            data = json.loads(approval.read_text(encoding="utf-8"))
            self.assertTrue(bool(data.get("approved")))
            self.assertEqual(str(data.get("ticket") or ""), "MANUAL-123")
            self.assertEqual(((data.get("instruments") or {}).get("EURUSD") or ""), "SREDNI")
            self.assertEqual(((data.get("instruments") or {}).get("GBPUSD") or ""), "BEZPIECZNY")

    def test_rejects_invalid_profile(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"
            (root / "LAB" / "CONFIG").mkdir(parents=True, exist_ok=True)
            (root / "LAB" / "CONFIG" / "stage1_manual_approval.template.json").write_text("{}", encoding="utf-8")

            cmd = [
                sys.executable,
                "TOOLS/stage1_approve.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
                "--instrument-profile",
                "EURUSD=LIVE_NOW",
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("INVALID_INSTRUMENT_PROFILE", proc.stdout or "")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
