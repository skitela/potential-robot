from __future__ import annotations

import json
import shutil
import sqlite3
import time
import unittest
import uuid
from pathlib import Path

from BIN import repair_agent as ra


class TestRepairAgentTradeWatchdog(unittest.TestCase):
    @staticmethod
    def _mkroot() -> Path:
        base = Path("TMP_AUDIT_IO") / "test_repair_agent_trade_watchdog"
        base.mkdir(parents=True, exist_ok=True)
        root = base / f"case_{uuid.uuid4().hex}"
        (root / "RUN").mkdir(parents=True, exist_ok=True)
        (root / "DB").mkdir(parents=True, exist_ok=True)
        (root / "CONFIG").mkdir(parents=True, exist_ok=True)
        (root / "CONFIG" / "strategy.json").write_text("{}", encoding="utf-8")
        return root

    @staticmethod
    def _init_db(root: Path) -> Path:
        dbp = root / "DB" / "decision_events.sqlite"
        conn = sqlite3.connect(str(dbp), timeout=5)
        try:
            conn.execute("PRAGMA busy_timeout=5000")
            conn.execute("PRAGMA journal_mode=MEMORY")
            conn.execute(
                """CREATE TABLE IF NOT EXISTS deals_log (
                    deal_ticket INTEGER PRIMARY KEY,
                    time INTEGER,
                    ny_date TEXT,
                    ny_hour INTEGER,
                    grp TEXT,
                    symbol TEXT,
                    profit REAL,
                    commission REAL,
                    swap REAL
                )"""
            )
            conn.execute(
                """CREATE TABLE IF NOT EXISTS system_state (
                    key TEXT PRIMARY KEY,
                    value TEXT
                )"""
            )
            conn.commit()
        finally:
            conn.close()
        return dbp

    def test_trade_health_detects_symbol_loss_candidates(self) -> None:
        root = self._mkroot()
        self.addCleanup(lambda: shutil.rmtree(root, ignore_errors=True))
        dbp = self._init_db(root)

        now_ts = int(time.time())
        conn = sqlite3.connect(str(dbp), timeout=5)
        try:
            conn.execute("PRAGMA busy_timeout=5000")
            conn.execute("PRAGMA journal_mode=MEMORY")
            rows = [
                (1, now_ts - 30, "2026-02-18", 12, "FX", "EURUSD.pro", -1.0, 0.0, 0.0),
                (2, now_ts - 25, "2026-02-18", 12, "FX", "EURUSD.pro", -0.8, 0.0, 0.0),
                (3, now_ts - 20, "2026-02-18", 12, "FX", "GBPUSD.pro", -0.7, 0.0, 0.0),
                (4, now_ts - 15, "2026-02-18", 12, "FX", "GBPUSD.pro", -0.9, 0.0, 0.0),
            ]
            conn.executemany(
                """INSERT INTO deals_log
                   (deal_ticket, time, ny_date, ny_hour, grp, symbol, profit, commission, swap)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                rows,
            )
            conn.commit()
        finally:
            conn.close()

        saved = (
            ra.TRADE_LOSS_MIN_DEALS_PER_SYMBOL,
            ra.TRADE_GLOBAL_MIN_SYMBOLS,
            ra.TRADE_LOSS_RATIO_TRIGGER,
        )
        try:
            ra.TRADE_LOSS_MIN_DEALS_PER_SYMBOL = 2
            ra.TRADE_GLOBAL_MIN_SYMBOLS = 2
            ra.TRADE_LOSS_RATIO_TRIGGER = 0.5
            snap = ra._trade_health_snapshot(root)
            self.assertTrue(bool(snap.get("ok")))
            self.assertIn("EURUSD", list(snap.get("symbol_shadow_candidates") or []))
            self.assertIn("GBPUSD", list(snap.get("symbol_shadow_candidates") or []))
            self.assertTrue(bool(snap.get("global_loss_all_active")))
        finally:
            (
                ra.TRADE_LOSS_MIN_DEALS_PER_SYMBOL,
                ra.TRADE_GLOBAL_MIN_SYMBOLS,
                ra.TRADE_LOSS_RATIO_TRIGGER,
            ) = saved

    def test_apply_symbol_shadow_mode_writes_cooldown_state(self) -> None:
        root = self._mkroot()
        self.addCleanup(lambda: shutil.rmtree(root, ignore_errors=True))
        dbp = self._init_db(root)

        ok = ra._apply_symbol_shadow_mode(root, "EURUSD", 3600, "shadow_test")
        self.assertTrue(ok)

        conn = sqlite3.connect(str(dbp), timeout=5)
        try:
            cur = conn.cursor()
            cur.execute("SELECT value FROM system_state WHERE key='cooldown_reason:EURUSD'")
            row = cur.fetchone()
            self.assertIsNotNone(row)
            self.assertEqual("shadow_test", str(row[0]))
            cur.execute("SELECT value FROM system_state WHERE key='cooldown_until_ts:EURUSD'")
            row2 = cur.fetchone()
            self.assertIsNotNone(row2)
            self.assertGreater(int(float(row2[0])), int(time.time()))
        finally:
            conn.close()

    def test_health_watchdog_emits_trade_idle_alert(self) -> None:
        root = self._mkroot()
        self.addCleanup(lambda: shutil.rmtree(root, ignore_errors=True))
        dbp = self._init_db(root)

        old_trade = int(time.time()) - 120
        conn = sqlite3.connect(str(dbp), timeout=5)
        try:
            conn.execute("PRAGMA busy_timeout=5000")
            conn.execute("PRAGMA journal_mode=MEMORY")
            conn.execute(
                """INSERT INTO deals_log
                   (deal_ticket, time, ny_date, ny_hour, grp, symbol, profit, commission, swap)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (11, old_trade, "2026-02-18", 10, "FX", "EURUSD.pro", 1.0, 0.0, 0.0),
            )
            conn.commit()
        finally:
            conn.close()

        saved_idle = ra.TRADE_IDLE_ALERT_SEC
        try:
            ra.TRADE_IDLE_ALERT_SEC = 30
            out = ra._health_watchdog_actions(root)
            eid = str(out.get("synthetic_alert_event_id") or "")
            self.assertTrue(eid)
            alert = json.loads((root / "RUN" / "infobot_alert.json").read_text(encoding="utf-8"))
            self.assertEqual(eid, str(alert.get("event_id")))
            self.assertIn("trade_idle", str(alert.get("reason") or ""))
        finally:
            ra.TRADE_IDLE_ALERT_SEC = saved_idle


if __name__ == "__main__":
    raise SystemExit(unittest.main())
