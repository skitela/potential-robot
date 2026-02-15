from __future__ import annotations

import re
from pathlib import Path
import unittest


class TestForbiddenExceptPass(unittest.TestCase):
    def test_no_forbidden_except_pass_in_sources(self) -> None:
        root = Path(__file__).resolve().parents[1]
        scan_dirs = [root / "BIN", root / "TOOLS"]
        rx1 = re.compile(r"^\s*except\s+Exception\s*:\s*pass\s*$", re.M)
        rx2 = re.compile(r"^\s*except\s+Exception\s*:\s*\n\s*pass\s*$", re.M)
        offenders: list[str] = []

        for base in scan_dirs:
            if not base.exists():
                continue
            for path in base.rglob("*.py"):
                txt = path.read_text(encoding="utf-8", errors="replace")
                if rx1.search(txt) or rx2.search(txt):
                    offenders.append(str(path.relative_to(root)).replace("\\", "/"))

        self.assertEqual([], offenders, f"Forbidden except-pass found: {offenders}")


if __name__ == "__main__":
    unittest.main()
