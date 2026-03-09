from __future__ import annotations

from TOOLS.mql5_cutover_cycle import evaluate_cycle_status


def test_cycle_status_pass_when_readiness_pass() -> None:
    got = evaluate_cycle_status(
        probe_status="OK",
        readiness_status="PASS",
        parity_rows=500,
    )
    assert got == "PASS"


def test_cycle_status_review_required_when_no_active_peer() -> None:
    got = evaluate_cycle_status(
        probe_status="NO_ACTIVE_PEER",
        readiness_status="REVIEW_REQUIRED",
        parity_rows=0,
    )
    assert got == "REVIEW_REQUIRED"


def test_cycle_status_review_required_when_probe_runtime_missing() -> None:
    got = evaluate_cycle_status(
        probe_status="NO_ZMQ",
        readiness_status="REVIEW_REQUIRED",
        parity_rows=0,
    )
    assert got == "REVIEW_REQUIRED"
