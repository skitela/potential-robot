from __future__ import annotations

import shutil
import subprocess
import sys
import unittest
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "TOOLS" / "dependency_hygiene.py"


class TestDependencyHygieneCli(unittest.TestCase):
    def _tmpdir(self) -> Path:
        base = ROOT / "TMP_AUDIT_IO" / "test_dependency_hygiene_cli"
        path = base / f"case_{uuid.uuid4().hex}"
        path.mkdir(parents=True, exist_ok=True)
        self.addCleanup(lambda: shutil.rmtree(path, ignore_errors=True))
        return path

    def _run(self, root: Path, *extra: str) -> subprocess.CompletedProcess[str]:
        cmd = [sys.executable, str(TOOL), "--root", str(root), *extra]
        return subprocess.run(cmd, capture_output=True, text=True, check=False)

    def test_cli_returns_nonzero_when_fail_flags_and_unresolved(self) -> None:
        root = self._tmpdir()
        (root / "requirements.txt").write_text("requests>=0\n", encoding="utf-8")
        (root / "BIN").mkdir(parents=True, exist_ok=True)
        (root / "BIN" / "__init__.py").write_text("", encoding="utf-8")
        (root / "BIN" / "bad.py").write_text("import BIN.missing_module\n", encoding="utf-8")
        cp = self._run(root, "--fail-on-local-unresolved")
        self.assertEqual(2, int(cp.returncode))
        self.assertIn("DEPENDENCY_HYGIENE_FAIL", str(cp.stdout))

    def test_cli_returns_zero_without_fail_flags(self) -> None:
        root = self._tmpdir()
        (root / "requirements.txt").write_text("requests>=0\n", encoding="utf-8")
        (root / "BIN").mkdir(parents=True, exist_ok=True)
        (root / "BIN" / "__init__.py").write_text("", encoding="utf-8")
        (root / "BIN" / "bad.py").write_text("import BIN.missing_module\n", encoding="utf-8")
        cp = self._run(root)
        self.assertEqual(0, int(cp.returncode))
        self.assertIn("DEPENDENCY_HYGIENE_OK", str(cp.stdout))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
