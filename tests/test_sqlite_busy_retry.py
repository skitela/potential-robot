from __future__ import annotations

import sqlite3
import threading
import time
from pathlib import Path

from BIN import learner_offline as learner


def test_sqlite_busy_retry_releases_lock(tmp_path: Path) -> None:
    db_path = tmp_path / "test.db"
    conn1 = sqlite3.connect(str(db_path), check_same_thread=False)
    conn1.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)")
    conn1.execute("INSERT INTO t (v) VALUES ('x')")
    conn1.commit()

    # Hold an exclusive lock briefly
    conn1.execute("BEGIN EXCLUSIVE")

    def _release():
        time.sleep(0.2)
        conn1.execute("COMMIT")
        conn1.close()

    t = threading.Thread(target=_release)
    t.start()

    conn2 = sqlite3.connect(str(db_path), timeout=0.1)
    rows = learner.sqlite_fetchall_retry(conn2, "SELECT v FROM t", (), tries=6, base_sleep=0.1)
    conn2.close()
    t.join()

    assert rows == [("x",)]
