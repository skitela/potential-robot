import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Test2RPreflightAndDrift(unittest.TestCase):
    def test_generate_asia_preflight_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "RUN").mkdir(parents=True, exist_ok=True)
            (root / "EVIDENCE").mkdir(parents=True, exist_ok=True)
            sample = {
                "details": {
                    "symbols": [
                        {"name": "USDJPY.pro", "select": True, "visible": True, "trade_mode": 4},
                        {"name": "GOLD.pro", "select": True, "visible": True, "trade_mode": 4},
                    ]
                }
            }
            (root / "RUN" / "symbols_audit_now.json").write_text(
                json.dumps(sample, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            script = ROOT / "TOOLS" / "generate_asia_preflight_evidence.py"
            out = root / "EVIDENCE" / "asia_symbol_preflight.json"
            proc = subprocess.run(
                [sys.executable, str(script), "--root", str(root), "--out", str(out.relative_to(root))],
                cwd=str(ROOT),
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(0, proc.returncode, msg=proc.stderr)
            self.assertTrue(out.exists())
            obj = json.loads(out.read_text(encoding="utf-8"))
            self.assertIn("rows", obj)
            self.assertGreaterEqual(int(obj.get("sample_size_n", 0)), 1)

    def test_no_strategy_drift_check_script(self) -> None:
        script = ROOT / "TOOLS" / "no_strategy_drift_check.py"
        out = ROOT / "EVIDENCE" / "no_strategy_drift_check_test.json"
        proc = subprocess.run(
            [sys.executable, str(script), "--root", str(ROOT), "--out", str(out.relative_to(ROOT))],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, proc.returncode, msg=proc.stderr)
        self.assertTrue(out.exists())
        obj = json.loads(out.read_text(encoding="utf-8"))
        self.assertIn("no_strategy_drift_check", obj)
        verdict = str((obj["no_strategy_drift_check"] or {}).get("verdict", ""))
        self.assertIn(verdict, {"PASS", "REVIEW_REQUIRED"})
        try:
            out.unlink(missing_ok=True)
        except Exception:
            pass


if __name__ == "__main__":
    raise SystemExit(unittest.main())
