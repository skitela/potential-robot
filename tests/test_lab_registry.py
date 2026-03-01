from __future__ import annotations

import json
from pathlib import Path

from TOOLS import lab_registry as lr


def test_registry_insert_and_fetch(tmp_path: Path) -> None:
    db = tmp_path / "registry.sqlite"
    conn = lr.connect_registry(db)
    try:
        lr.init_registry_schema(conn)
        lr.insert_experiment_run(
            conn,
            {
                "run_id": "LAB_20260302T000000Z",
                "ts_utc": "2026-03-02T00:00:00Z",
                "dataset_hash": "a" * 64,
                "config_hash": "b" * 64,
                "score": 12.34,
                "readiness": "HOLD",
                "reason": "NO_READY_CANDIDATES",
                "type_primary": "HYBRID",
                "type_change": "H",
                "review_required": True,
                "touches_hot_path": False,
                "evidence_paths_json": json.dumps(["C:/x.json"]),
                "report_path": "C:/x.json",
            },
        )
        lr.insert_candidate_scores(
            conn,
            "LAB_20260302T000000Z",
            [
                {
                    "rank": 1,
                    "window_id": "FX_AM",
                    "symbol": "EURUSD",
                    "lab_score": 11.11,
                    "promotion_status": "NOT_READY",
                    "lab_action": "TRZYMAJ",
                    "source_shadow_recommendation": {"reason_code": "LOW_SAMPLE"},
                    "strict": {"trades": 10},
                    "explore": {"trades": 20},
                }
            ],
        )
        rows = lr.fetch_latest_runs(conn, limit=3)
    finally:
        conn.close()

    assert len(rows) == 1
    assert rows[0]["run_id"] == "LAB_20260302T000000Z"
    assert rows[0]["readiness"] == "HOLD"
