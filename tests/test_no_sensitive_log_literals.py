from __future__ import annotations

import ast
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN_DIRS = ("BIN", "TOOLS")

# Guard against accidental leakage of sensitive fields in logs/prints.
FORBIDDEN_SNIPPETS = (
    "MT5_PASSWORD",
    "OPENAI_API_KEY",
    "GEMINI_API_KEY",
    "API_KEY=",
    "PASSWORD=",
    "SECRET=",
    "TOKEN=",
    "BEARER ",
)


def _is_log_or_print_call(node: ast.Call) -> bool:
    fn = node.func
    if isinstance(fn, ast.Name) and fn.id == "print":
        return True
    if isinstance(fn, ast.Attribute) and isinstance(fn.value, ast.Name):
        if fn.value.id == "logging":
            return fn.attr in {"debug", "info", "warning", "error", "critical", "exception"}
    return False


def _extract_literal_arg(node: ast.Call) -> str:
    if not node.args:
        return ""
    arg0 = node.args[0]
    if isinstance(arg0, ast.Constant) and isinstance(arg0.value, str):
        return arg0.value
    return ""


class TestNoSensitiveLogLiterals(unittest.TestCase):
    def test_no_sensitive_literals_in_logs_or_prints(self) -> None:
        findings: list[str] = []
        for rel_dir in SCAN_DIRS:
            base = ROOT / rel_dir
            if not base.exists():
                continue
            for path in sorted(base.rglob("*.py")):
                text = path.read_text(encoding="utf-8", errors="ignore")
                try:
                    tree = ast.parse(text, filename=str(path))
                except SyntaxError:
                    continue
                for node in ast.walk(tree):
                    if not isinstance(node, ast.Call):
                        continue
                    if not _is_log_or_print_call(node):
                        continue
                    literal = _extract_literal_arg(node).upper()
                    if not literal:
                        continue
                    for snippet in FORBIDDEN_SNIPPETS:
                        if snippet in literal:
                            findings.append(
                                f"{path.relative_to(ROOT).as_posix()}:{int(getattr(node, 'lineno', 0))}:{snippet}"
                            )
                            break
        self.assertEqual([], findings)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
