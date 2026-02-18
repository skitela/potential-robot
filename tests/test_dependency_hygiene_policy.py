from __future__ import annotations

import unittest

from TOOLS import dependency_hygiene as dh


class TestDependencyHygienePolicy(unittest.TestCase):
    def test_no_failures_when_flags_off(self) -> None:
        rep = {
            "missing_requirements": ["x"],
            "local_unresolved_total": 2,
        }
        got = dh.evaluate_failures(
            rep,
            fail_on_missing_requirements=False,
            fail_on_local_unresolved=False,
        )
        self.assertEqual([], got)

    def test_missing_requirements_failure(self) -> None:
        rep = {
            "missing_requirements": ["x", "y"],
            "local_unresolved_total": 0,
        }
        got = dh.evaluate_failures(
            rep,
            fail_on_missing_requirements=True,
            fail_on_local_unresolved=False,
        )
        self.assertEqual(["MISSING_REQUIREMENTS:2"], got)

    def test_local_unresolved_failure(self) -> None:
        rep = {
            "missing_requirements": [],
            "local_unresolved_total": 3,
        }
        got = dh.evaluate_failures(
            rep,
            fail_on_missing_requirements=False,
            fail_on_local_unresolved=True,
        )
        self.assertEqual(["LOCAL_UNRESOLVED:3"], got)

    def test_both_failures(self) -> None:
        rep = {
            "missing_requirements": ["x"],
            "local_unresolved_total": 1,
        }
        got = dh.evaluate_failures(
            rep,
            fail_on_missing_requirements=True,
            fail_on_local_unresolved=True,
        )
        self.assertEqual(["MISSING_REQUIREMENTS:1", "LOCAL_UNRESOLVED:1"], got)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
