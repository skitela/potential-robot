from __future__ import annotations

from TOOLS.mql5_cutover_readiness import build_readiness


def test_readiness_flags_no_parity_data_as_review_required() -> None:
    report = {
        "summary": {"parity_rows": 0, "parity_mismatch": 0, "parity_mismatch_ratio": None, "state_rows": 40},
        "counts": {"parity_by_window": {}, "parity_mismatch_by_window": {}},
    }
    ready = build_readiness(report, min_parity_rows=100, max_mismatch_ratio=0.02)
    assert ready["status"] == "REVIEW_REQUIRED"
    assert "NO_PARITY_DATA" in ready["reasons"]


def test_readiness_flags_high_mismatch_as_no_go() -> None:
    report = {
        "summary": {"parity_rows": 500, "parity_mismatch": 40, "parity_mismatch_ratio": 0.08, "state_rows": 600},
        "counts": {
            "parity_by_window": {"FX_AM": 250, "METAL_PM": 250},
            "parity_mismatch_by_window": {"FX_AM": 10, "METAL_PM": 30},
        },
    }
    ready = build_readiness(report, min_parity_rows=100, max_mismatch_ratio=0.02)
    assert ready["status"] == "NO_GO"
    assert "PARITY_MISMATCH_RATIO_HIGH" in ready["reasons"]


def test_readiness_pass_for_good_sample_and_ratio() -> None:
    report = {
        "summary": {"parity_rows": 600, "parity_mismatch": 2, "parity_mismatch_ratio": 0.003, "state_rows": 1200},
        "counts": {
            "parity_by_window": {"FX_AM": 300, "METAL_PM": 300},
            "parity_mismatch_by_window": {"FX_AM": 1, "METAL_PM": 1},
        },
    }
    ready = build_readiness(report, min_parity_rows=100, max_mismatch_ratio=0.02)
    assert ready["status"] == "PASS"
    assert ready["reasons"] == []


def test_readiness_flags_window_coverage_too_low() -> None:
    report = {
        "summary": {"parity_rows": 300, "parity_mismatch": 3, "parity_mismatch_ratio": 0.01, "state_rows": 600},
        "counts": {
            "parity_by_window": {"OFF": 300},
            "parity_mismatch_by_window": {"OFF": 3},
        },
    }
    ready = build_readiness(report, min_parity_rows=100, max_mismatch_ratio=0.02, min_active_windows=1)
    assert ready["status"] == "REVIEW_REQUIRED"
    assert "WINDOW_COVERAGE_TOO_LOW" in ready["reasons"]


def test_readiness_flags_window_mismatch_ratio_high() -> None:
    report = {
        "summary": {"parity_rows": 400, "parity_mismatch": 8, "parity_mismatch_ratio": 0.02, "state_rows": 700},
        "counts": {
            "parity_by_window": {"FX_AM": 200, "METAL_PM": 200},
            "parity_mismatch_by_window": {"FX_AM": 1, "METAL_PM": 20},
        },
    }
    ready = build_readiness(
        report,
        min_parity_rows=100,
        max_mismatch_ratio=0.05,
        min_active_windows=1,
        min_window_parity_rows=20,
        max_window_mismatch_ratio=0.05,
    )
    assert ready["status"] == "NO_GO"
    assert "WINDOW_MISMATCH_RATIO_HIGH" in ready["reasons"]
