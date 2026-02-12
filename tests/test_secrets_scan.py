import json
import shutil
import unittest
import uuid
from pathlib import Path

from TOOLS import secrets_scan


class TestSecretsScan(unittest.TestCase):
    @staticmethod
    def _mkroot() -> Path:
        base = Path("TMP_AUDIT_IO") / "test_secrets_scan"
        base.mkdir(parents=True, exist_ok=True)
        root = base / f"case_{uuid.uuid4().hex}"
        root.mkdir(parents=True, exist_ok=False)
        return root

    def test_clean_repo_pass(self) -> None:
        root = self._mkroot()
        try:
            (root / "a.py").write_text("print('ok')\n", encoding="utf-8")
            report = secrets_scan.scan_roots([root])
            self.assertEqual(report["status"], "PASS")
            self.assertEqual(report["totals"]["findings"], 0)
        finally:
            shutil.rmtree(root, ignore_errors=True)

    def test_fake_token_fails_without_leak(self) -> None:
        root = self._mkroot()
        fake_sk = "sk-" + "TESTTOKEN1234567890"
        try:
            (root / "bad.txt").write_text(f"api_key={fake_sk}\n", encoding="utf-8")
            report = secrets_scan.scan_roots([root])
            self.assertEqual(report["status"], "FAIL")
            self.assertGreater(report["totals"]["findings"], 0)
            finding = report["findings"][0]
            self.assertIn("file", finding)
            self.assertIn("line", finding)
            self.assertIn("pattern", finding)
            self.assertNotIn("match", finding)
            body = json.dumps(report, ensure_ascii=False)
            self.assertNotIn(fake_sk, body)
        finally:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
