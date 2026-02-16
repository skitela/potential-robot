import shutil
import sqlite3
import sys
import types
import unittest
import uuid
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

if "MetaTrader5" not in sys.modules:
    mt5_stub = types.ModuleType("MetaTrader5")
    mt5_stub.TIMEFRAME_M5 = 5
    mt5_stub.TIMEFRAME_H4 = 16388
    mt5_stub.TIMEFRAME_D1 = 16408
    sys.modules["MetaTrader5"] = mt5_stub

import safetybot


class TestPersistenceJournalFallback(unittest.TestCase):
    def _tmpdir(self) -> Path:
        base = ROOT / "TMP_AUDIT_IO" / "test_persistence_journal_fallback"
        path = base / f"case_{uuid.uuid4().hex}"
        path.mkdir(parents=True, exist_ok=True)
        self.addCleanup(lambda: shutil.rmtree(path, ignore_errors=True))
        return path

    def test_forced_no_delete_uses_journal_off(self) -> None:
        tmp = self._tmpdir()
        db_path = tmp / "fallback.db"
        with mock.patch.object(safetybot.Persistence, "_probe_delete_capability", return_value=False):
            db = safetybot.Persistence(db_path)
        try:
            mode = str(db.conn.execute("PRAGMA journal_mode;").fetchone()[0]).strip().lower()
            self.assertEqual(mode, "off")
        finally:
            db.conn.close()

    def test_disk_io_init_triggers_recovery_and_reconnect(self) -> None:
        tmp = self._tmpdir()
        db_path = tmp / "recovery.db"

        class _FakeConn:
            def __init__(self) -> None:
                self.closed = False

            def close(self) -> None:
                self.closed = True

        conn1 = _FakeConn()
        conn2 = _FakeConn()
        with mock.patch.object(safetybot.Persistence, "_probe_delete_capability", return_value=True):
            with mock.patch.object(safetybot.Persistence, "_connect", side_effect=[conn1, conn2]) as m_connect:
                with mock.patch.object(
                    safetybot.Persistence,
                    "_init_db",
                    side_effect=[sqlite3.OperationalError("disk I/O error"), None],
                ) as m_init:
                    with mock.patch.object(
                        safetybot.Persistence, "_recover_corrupt_sqlite_files"
                    ) as m_recover:
                        db = safetybot.Persistence(db_path)

        self.assertIs(db.conn, conn2)
        self.assertEqual(m_connect.call_count, 2)
        self.assertEqual(m_init.call_count, 2)
        m_recover.assert_called_once()
        self.assertTrue(conn1.closed)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
