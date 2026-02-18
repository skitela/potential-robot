from __future__ import annotations

import unittest
from pathlib import Path

from TOOLS import dependency_hygiene as dh


ROOT = Path(__file__).resolve().parents[1]


class TestDependencyHygieneRepo(unittest.TestCase):
    def test_repo_has_no_missing_requirements(self) -> None:
        rep = dh.detect_hygiene(ROOT, dh.REQUIREMENT_FILES_DEFAULT)
        self.assertEqual([], rep.get("missing_requirements"))

    def test_repo_has_no_unresolved_local_links(self) -> None:
        rep = dh.detect_hygiene(ROOT, dh.REQUIREMENT_FILES_DEFAULT)
        self.assertEqual(0, int(rep.get("local_unresolved_total", -1)))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
