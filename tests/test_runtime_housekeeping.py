import shutil
import unittest
from pathlib import Path

from TOOLS.runtime_housekeeping import run_housekeeping


class TestRuntimeHousekeeping(unittest.TestCase):
    def test_apply_removes_safe_artifacts(self) -> None:
        workspace = Path(__file__).resolve().parents[1]
        tmp_root = (workspace / "tests" / "_tmp_housekeeping").resolve()
        shutil.rmtree(tmp_root, ignore_errors=True)
        tmp_root.mkdir(parents=True, exist_ok=True)
        try:
            (tmp_root / "__pycache__").mkdir(parents=True, exist_ok=True)
            (tmp_root / "__pycache__" / "a.pyc").write_bytes(b"x")
            (tmp_root / "RUN").mkdir(parents=True, exist_ok=True)
            (tmp_root / "RUN" / "infobot.lock").write_text("1", encoding="utf-8")
            (tmp_root / "LOGS").mkdir(parents=True, exist_ok=True)
            (tmp_root / "LOGS" / "sample.log").write_text("abc", encoding="utf-8")

            report = run_housekeeping(tmp_root, apply=True, keep_runs=5, max_single_log_mb=1)
            self.assertEqual(report["status"], "PASS")
            self.assertGreaterEqual(int(report["summary"]["actions_total"]), 1)
            self.assertIn("actions_failed", report["summary"])
        finally:
            shutil.rmtree(tmp_root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
