from __future__ import annotations

import tempfile
from pathlib import Path
import unittest

from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.paths import Paths
from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.readonly_adapter import (
    READ_STATUS_STALE_OR_INCOMPLETE,
    READ_STATUS_STALE_OR_INCOMPLETE_ARTIFACT,
    ReadOnlyDataAdapter,
)
from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.stt_normalization import normalize_stt_term


class TestSafeReadArtifacts(unittest.TestCase):
    def test_incomplete_json_returns_stale_or_incomplete(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            ws = Path(td)
            for rel in ("DB", "LOGS", "META", "EVIDENCE", "RUN"):
                (ws / rel).mkdir(parents=True, exist_ok=True)
            (ws / "OBSERVERS_IMPLEMENTATION_CANDIDATE" / "outputs").mkdir(parents=True, exist_ok=True)
            bad = ws / "RUN" / "live_trade_monitor_status.json"
            bad.write_text('{"broken": ', encoding='utf-8')

            paths = Paths.from_workspace(ws)
            adapter = ReadOnlyDataAdapter(paths)
            snap = adapter.fetch_latest_snapshot("current_system_state")

            self.assertIsNotNone(snap)
            self.assertEqual(READ_STATUS_STALE_OR_INCOMPLETE, snap.read_status)
            self.assertEqual(READ_STATUS_STALE_OR_INCOMPLETE_ARTIFACT, snap.read_status)

    def test_stt_normalization_rules(self) -> None:
        src = "Honda MT5 System i Kodex dla Oranda oraz Zaphotybot i lqm5"
        out = normalize_stt_term(src)
        self.assertIn("OANDA_MT5_SYSTEM", out)
        self.assertIn("Codex", out)
        self.assertIn("OANDA", out)
        self.assertIn("SafetyBot", out)
        self.assertIn("MQL5", out)


if __name__ == "__main__":
    unittest.main()
