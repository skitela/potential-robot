import shutil
import unittest
import uuid
from pathlib import Path

from BIN.incident_guard import IncidentJournal, classify_retcode


class TestIncidentGuard(unittest.TestCase):
    def _tmpdir(self) -> Path:
        base = Path("TMP_AUDIT_IO") / "test_incident_guard"
        path = base / f"case_{uuid.uuid4().hex}"
        path.mkdir(parents=True, exist_ok=True)
        self.addCleanup(lambda: shutil.rmtree(path, ignore_errors=True))
        return path

    def test_classify_retcode(self) -> None:
        self.assertEqual(classify_retcode(10009), ("ok", "INFO"))
        self.assertEqual(classify_retcode(10031)[0], "system")
        self.assertEqual(classify_retcode(10019), ("risk", "CRITICAL"))

    def test_journal_counts(self) -> None:
        tmp = self._tmpdir()
        j = IncidentJournal(tmp)
        j.note_retcode(symbol="EURUSD", retcode_num=10031, retcode_name="TRADE_RETCODE_CONNECTION")
        j.note_retcode(symbol="EURUSD", retcode_num=10009, retcode_name="TRADE_RETCODE_DONE")
        j.note_guard(guard="self_heal", reason="LOSS_STREAK", category="model", severity="WARN")
        c = j.recent_counts(lookback_sec=600)
        self.assertGreaterEqual(int(c.get("total") or 0), 3)
        self.assertGreaterEqual(int(c.get("error_or_worse") or 0), 1)
        self.assertGreaterEqual(int(c.get("model") or 0), 1)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
