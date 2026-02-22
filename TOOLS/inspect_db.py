import sqlite3
from pathlib import Path

db_path = Path("DB/decision_events.sqlite")
if not db_path.exists():
    print(f"Database not found at {db_path}")
    exit(1)

conn = sqlite3.connect(str(db_path))
try:
    total = conn.execute("SELECT COUNT(*) FROM decision_events").fetchone()[0]
    closed = conn.execute("SELECT COUNT(*) FROM decision_events WHERE outcome_closed_ts_utc IS NOT NULL AND outcome_closed_ts_utc != ''").fetchone()[0]
    print(f"Total events: {total}")
    print(f"Closed events: {closed}")
    
    if total > 0:
        print("\nLast 5 events:")
        rows = conn.execute("SELECT event_id, ts_utc, choice_A, signal, outcome_closed_ts_utc FROM decision_events ORDER BY ts_utc DESC LIMIT 5").fetchall()
        for r in rows:
            print(r)
finally:
    conn.close()
