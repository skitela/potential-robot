from __future__ import annotations

from pathlib import Path

from BIN import scudfab02 as scud


def test_shadowb_idempotent(tmp_path: Path) -> None:
    root = tmp_path
    (root / "META").mkdir(parents=True, exist_ok=True)

    record = {
        "event_id": "evt-001",
        "ts_utc": "2026-01-01T00:00:00Z",
        "end_ts_utc": "2026-01-01T00:10:00Z",
        "symbol": "EURUSD",
        "verdict_light": "GREEN",
        "reqs_trade": 10,
        "pnl_net": 1.0,
        "edge_fuel": 0.1,
    }

    appended_1 = scud.append_shadowb(root, [record])
    appended_2 = scud.append_shadowb(root, [record])

    path = root / "META" / "scout_shadowb.jsonl"
    lines = path.read_text(encoding="utf-8").splitlines()

    assert appended_1 == 1
    assert appended_2 == 0
    assert len(lines) == 1
