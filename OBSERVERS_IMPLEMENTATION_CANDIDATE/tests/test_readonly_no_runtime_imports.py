from __future__ import annotations

import ast
from pathlib import Path
import unittest

from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.boundaries import FORBIDDEN_RUNTIME_IMPORT_PREFIXES


class TestNoRuntimeImports(unittest.TestCase):
    def test_no_forbidden_runtime_imports(self) -> None:
        root = Path(__file__).resolve().parents[1]
        py_files = [p for p in root.rglob("*.py") if "tests" not in p.parts]
        violations: list[str] = []
        for py in py_files:
            tree = ast.parse(py.read_text(encoding="utf-8"), filename=str(py))
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    for alias in node.names:
                        if alias.name.startswith(FORBIDDEN_RUNTIME_IMPORT_PREFIXES):
                            violations.append(f"{py}: import {alias.name}")
                elif isinstance(node, ast.ImportFrom):
                    module = node.module or ""
                    if module.startswith(FORBIDDEN_RUNTIME_IMPORT_PREFIXES):
                        violations.append(f"{py}: from {module} import ...")
        self.assertEqual([], violations, f"Forbidden runtime imports found: {violations}")
