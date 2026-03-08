from __future__ import annotations

from pathlib import Path

from TOOLS.safetybot_hotpath_map import (
    HOT,
    OWNER_MQL5_KERNEL,
    OWNER_PY_SUPERVISOR,
    SLOW,
    WARM,
    _infer_bucket,
    _render_txt,
    build_hotpath_map,
)


def test_infer_bucket_honors_critical_overrides() -> None:
    bucket, owner, _ = _infer_bucket("scan_once")
    assert bucket == HOT
    assert owner == OWNER_MQL5_KERNEL

    bucket, owner, _ = _infer_bucket("_emit_policy_runtime")
    assert bucket == SLOW
    assert owner == OWNER_PY_SUPERVISOR

    bucket, owner, _ = _infer_bucket("_runtime_maintenance_step")
    assert bucket == WARM
    assert owner == OWNER_PY_SUPERVISOR


def test_build_hotpath_map_on_real_safetybot_contains_core_methods() -> None:
    report = build_hotpath_map(Path("BIN/safetybot.py").resolve())
    assert report["schema"] == "oanda.mt5.safetybot.hotpath_map.v1"
    assert report["summary"]["methods_total"] > 0

    by_name = {row["name"]: row for row in report["rows"]}
    assert by_name["scan_once"]["bucket"] == HOT
    assert by_name["scan_once"]["owner_target"] == OWNER_MQL5_KERNEL
    assert by_name["_emit_policy_runtime"]["bucket"] == SLOW
    assert by_name["run"]["bucket"] == WARM


def test_render_txt_has_summary_and_rows() -> None:
    report = {
        "schema": "x",
        "generated_at_utc": "2026-03-08T00:00:00Z",
        "source_path": "BIN/safetybot.py",
        "source_sha256": "abc",
        "summary": {
            "methods_total": 2,
            "bucket_counts": {HOT: 1, WARM: 1, SLOW: 0},
            "owner_target_counts": {
                OWNER_MQL5_KERNEL: 1,
                "MQL5_WARM_PATH": 1,
                OWNER_PY_SUPERVISOR: 0,
            },
        },
        "rows": [
            {
                "line": 1,
                "name": "scan_once",
                "bucket": HOT,
                "owner_now": "PYTHON_RUNTIME",
                "owner_target": OWNER_MQL5_KERNEL,
                "reason": "x",
            }
        ],
    }
    txt = _render_txt(report)
    assert "METHODS_TOTAL: 2" in txt
    assert "BUCKET_COUNTS:" in txt
    assert "name=scan_once" in txt
