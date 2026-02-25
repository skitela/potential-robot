from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

FORBIDDEN_PATTERNS = [
    re.compile(r"GLOBALNY HANDEL VER1", re.IGNORECASE),
    re.compile(r"C:\\\\GLOBALNY HANDEL", re.IGNORECASE),
    re.compile(r"C:/GLOBALNY HANDEL", re.IGNORECASE),
    re.compile(r"\bfrom\s+GLOBALNY\b", re.IGNORECASE),
    re.compile(r"\bimport\s+GLOBALNY\b", re.IGNORECASE),
]

SCAN_EXTS = {
    ".py",
    ".mq5",
    ".mqh",
    ".json",
    ".md",
    ".txt",
    ".ps1",
    ".bat",
    ".toml",
    ".yaml",
    ".yml",
}

EXCLUDE_DIRS = {
    ".git",
    ".venv",
    "venv",
    "__pycache__",
    "EVIDENCE",
    "LOGS",
    "META",
    "DB",
    "DB_BACKUPS",
    "TMP_AUDIT_IO",
}


class TestNoCrossRepoLinks(unittest.TestCase):
    def test_no_forbidden_external_repo_paths(self) -> None:
        hits: list[str] = []
        for path in ROOT.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix.lower() not in SCAN_EXTS:
                continue
            rel = path.relative_to(ROOT)
            if any(part in EXCLUDE_DIRS for part in rel.parts):
                continue
            if rel.as_posix() == "tests/test_no_cross_repo_links.py":
                # Avoid self-match: this file contains the forbidden patterns by design.
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="ignore")
            except Exception:
                continue
            for pat in FORBIDDEN_PATTERNS:
                if pat.search(text):
                    hits.append(f"{rel.as_posix()} :: {pat.pattern}")
                    break

        self.assertFalse(hits, "Forbidden cross-repo references found:\n" + "\n".join(hits))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
