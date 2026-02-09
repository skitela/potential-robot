from __future__ import annotations

import json
import time
import os
from pathlib import Path

from BIN import scudfab02 as scud


def _now_utc_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def test_tiebreak_fastlane_writes_response(tmp_path: Path) -> None:
    run_dir = tmp_path / "RUN"
    run_dir.mkdir(parents=True, exist_ok=True)

    req = {
        "pv": 2,
        "ts_utc": _now_utc_iso(),
        "rid": "TB-TEST-123456",
        "ttl_sec": 30,
        "cands": ["EURUSD", "GBPUSD"],
        "mode": "PAPER",
        "ctx": {"mode": "PAPER", "note": "test"},
    }
    req_path = run_dir / scud.TIEBREAK_REQ_NAME
    req_path.write_text(json.dumps(req), encoding="utf-8")
    os.utime(req_path, (time.time(), time.time()))

    ranks = [
        {"symbol": "EURUSD", "score": 0.2, "es95": 0.1, "mdd": -0.1, "n": 60},
        {"symbol": "GBPUSD", "score": 0.1, "es95": 0.05, "mdd": -0.2, "n": 60},
    ]

    handled = scud.process_tiebreak_fast(
        run_dir,
        ranks=ranks,
        verdict="GREEN",
        metrics_n=60,
        source="test",
    )

    assert handled is True
    resp_path = run_dir / scud.TIEBREAK_RES_NAME
    assert resp_path.exists()
    data = json.loads(resp_path.read_text(encoding="utf-8"))
    assert data.get("tb") == 1
    assert data.get("pref") in {"EURUSD", "GBPUSD"}
