import sqlite3
import tempfile
from pathlib import Path

from TOOLS.sqlite_maintenance import run_maintenance


def test_run_maintenance_passes_on_temp_db() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        db_path = Path(tmp) / "t.db"
        conn = sqlite3.connect(str(db_path))
        try:
            conn.execute("CREATE TABLE IF NOT EXISTS t(id INTEGER PRIMARY KEY, v TEXT)")
            conn.execute("INSERT INTO t(v) VALUES('x')")
            conn.commit()
        finally:
            conn.close()

        out = run_maintenance(
            db_path,
            busy_timeout_ms=2000,
            ensure_wal=True,
            checkpoint_mode="PASSIVE",
            run_optimize=True,
        )
        assert str(out.get("status")) == "PASS"
        assert out.get("wal_checkpoint") is not None
