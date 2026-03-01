#!/usr/bin/env python3
from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Any, Dict, Iterable, List


def connect_registry(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path), timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=10000;")
    conn.execute("PRAGMA journal_mode=WAL;")
    return conn


def init_registry_schema(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS experiment_runs (
            run_id TEXT PRIMARY KEY,
            ts_utc TEXT NOT NULL,
            dataset_hash TEXT NOT NULL,
            config_hash TEXT NOT NULL,
            score REAL NOT NULL,
            readiness TEXT NOT NULL,
            reason TEXT NOT NULL,
            type_primary TEXT NOT NULL,
            type_change TEXT NOT NULL,
            review_required INTEGER NOT NULL,
            touches_hot_path INTEGER NOT NULL,
            evidence_paths_json TEXT NOT NULL,
            report_path TEXT NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS candidate_scores (
            run_id TEXT NOT NULL,
            rank_no INTEGER NOT NULL,
            window_id TEXT NOT NULL,
            symbol TEXT NOT NULL,
            lab_score REAL NOT NULL,
            readiness TEXT NOT NULL,
            lab_action TEXT NOT NULL,
            reason TEXT NOT NULL,
            strict_trades INTEGER NOT NULL,
            explore_trades INTEGER NOT NULL,
            PRIMARY KEY (run_id, rank_no),
            FOREIGN KEY (run_id) REFERENCES experiment_runs(run_id)
        )
        """
    )
    conn.commit()


def insert_experiment_run(conn: sqlite3.Connection, payload: Dict[str, Any]) -> None:
    conn.execute(
        """
        INSERT OR REPLACE INTO experiment_runs (
            run_id, ts_utc, dataset_hash, config_hash, score, readiness, reason,
            type_primary, type_change, review_required, touches_hot_path,
            evidence_paths_json, report_path
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            str(payload.get("run_id") or ""),
            str(payload.get("ts_utc") or ""),
            str(payload.get("dataset_hash") or ""),
            str(payload.get("config_hash") or ""),
            float(payload.get("score") or 0.0),
            str(payload.get("readiness") or "HOLD"),
            str(payload.get("reason") or "UNKNOWN"),
            str(payload.get("type_primary") or "HYBRID"),
            str(payload.get("type_change") or "H"),
            1 if bool(payload.get("review_required")) else 0,
            1 if bool(payload.get("touches_hot_path")) else 0,
            str(payload.get("evidence_paths_json") or "[]"),
            str(payload.get("report_path") or ""),
        ],
    )
    conn.commit()


def insert_candidate_scores(conn: sqlite3.Connection, run_id: str, rows: Iterable[Dict[str, Any]]) -> None:
    conn.executemany(
        """
        INSERT OR REPLACE INTO candidate_scores (
            run_id, rank_no, window_id, symbol, lab_score, readiness, lab_action, reason, strict_trades, explore_trades
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            [
                str(run_id),
                int(row.get("rank") or 0),
                str(row.get("window_id") or "NONE"),
                str(row.get("symbol") or "UNKNOWN"),
                float(row.get("lab_score") or 0.0),
                str(row.get("promotion_status") or "NOT_READY"),
                str(row.get("lab_action") or "TRZYMAJ"),
                str((row.get("source_shadow_recommendation") or {}).get("reason_code") or "UNKNOWN"),
                int((row.get("strict") or {}).get("trades") or 0),
                int((row.get("explore") or {}).get("trades") or 0),
            ]
            for row in rows
        ],
    )
    conn.commit()


def fetch_latest_runs(conn: sqlite3.Connection, *, limit: int = 10) -> List[Dict[str, Any]]:
    rows = conn.execute(
        """
        SELECT run_id, ts_utc, dataset_hash, config_hash, score, readiness, reason, type_primary, type_change
        FROM experiment_runs
        ORDER BY ts_utc DESC
        LIMIT ?
        """,
        [max(1, int(limit))],
    ).fetchall()
    return [dict(r) for r in rows]
