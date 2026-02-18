import unittest
import uuid
import shutil
from pathlib import Path

from TOOLS import dependency_hygiene as dh

ROOT = Path(__file__).resolve().parents[1]


class TestDependencyHygieneLinks(unittest.TestCase):
    def _tmpdir(self) -> Path:
        base = ROOT / "TMP_AUDIT_IO" / "test_dependency_hygiene_links"
        path = base / f"case_{uuid.uuid4().hex}"
        path.mkdir(parents=True, exist_ok=True)
        self.addCleanup(lambda: shutil.rmtree(path, ignore_errors=True))
        return path

    def test_local_links_detects_unresolved_import(self) -> None:
        root = self._tmpdir()
        (root / "BIN").mkdir(parents=True, exist_ok=True)
        (root / "BIN" / "__init__.py").write_text("", encoding="utf-8")
        (root / "BIN" / "a.py").write_text(
            "import BIN.missing_module\n",
            encoding="utf-8",
        )
        report = dh.analyze_local_links(root)
        self.assertEqual(1, report["unresolved_total"])
        unresolved = report["unresolved"][0]
        self.assertEqual("BIN.a", unresolved["src"])
        self.assertEqual("BIN.missing_module", unresolved["import"])

    def test_local_links_accepts_existing_package_import(self) -> None:
        root = self._tmpdir()
        (root / "BIN").mkdir(parents=True, exist_ok=True)
        (root / "BIN" / "__init__.py").write_text("", encoding="utf-8")
        (root / "BIN" / "a.py").write_text(
            "from BIN import b\n",
            encoding="utf-8",
        )
        (root / "BIN" / "b.py").write_text("X = 1\n", encoding="utf-8")
        report = dh.analyze_local_links(root)
        self.assertEqual(0, report["unresolved_total"])
        self.assertGreaterEqual(report["edges_total"], 1)

    def test_local_links_resolves_relative_import(self) -> None:
        root = self._tmpdir()
        (root / "BIN").mkdir(parents=True, exist_ok=True)
        (root / "BIN" / "__init__.py").write_text("", encoding="utf-8")
        (root / "BIN" / "a.py").write_text(
            "from . import b\n",
            encoding="utf-8",
        )
        (root / "BIN" / "b.py").write_text("Y = 2\n", encoding="utf-8")
        report = dh.analyze_local_links(root)
        self.assertEqual(0, report["unresolved_total"])


if __name__ == "__main__":
    raise SystemExit(unittest.main())
