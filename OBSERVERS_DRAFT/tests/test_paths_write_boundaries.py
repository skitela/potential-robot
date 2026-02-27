from __future__ import annotations

from pathlib import Path
import unittest

from OBSERVERS_DRAFT.common.paths import Paths


class TestPathsWriteBoundaries(unittest.TestCase):
    def test_allow_write_inside_outputs_only(self) -> None:
        paths = Paths.from_workspace(Path("C:/OANDA_MT5_SYSTEM"))
        good = paths.outputs_root / "reports" / "agent_x" / "report.json"
        bad = paths.workspace_root / "CONFIG" / "strategy.json"

        paths.ensure_write_allowed(good)
        with self.assertRaises(PermissionError):
            paths.ensure_write_allowed(bad)

