from __future__ import annotations

from TOOLS.mql5_cutover_readiness import build_readiness


def test_readiness_flags_no_parity_data_as_review_required() -> None:
    report = {"summary": {"parity_rows": 0, "parity_mismatch": 0, "parity_mismatch_ratio": None, "state_rows": 40}}
    ready = build_readiness(report, min_parity_rows=100, max_mismatch_ratio=0.02)
    assert ready["status"] == "REVIEW_REQUIRED"
    assert "NO_PARITY_DATA" in ready["reasons"]


def test_readiness_flags_high_mismatch_as_no_go() -> None:
    report = {"summary": {"parity_rows": 500, "parity_mismatch": 40, "parity_mismatch_ratio": 0.08, "state_rows": 600}}
    ready = build_readiness(report, min_parity_rows=100, max_mismatch_ratio=0.02)
    assert ready["status"] == "NO_GO"
    assert "PARITY_MISMATCH_RATIO_HIGH" in ready["reasons"]


def test_readiness_pass_for_good_sample_and_ratio() -> None:
    report = {"summary": {"parity_rows": 600, "parity_mismatch": 2, "parity_mismatch_ratio": 0.003, "state_rows": 1200}}
    ready = build_readiness(report, min_parity_rows=100, max_mismatch_ratio=0.02)
    assert ready["status"] == "PASS"
    assert ready["reasons"] == []
