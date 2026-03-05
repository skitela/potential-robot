from BIN.cost_guard_runtime import (
    CostGuardMetrics,
    CostGuardThresholds,
    derive_off_threshold,
    evaluate_cost_guard_state,
    update_transition_window,
)


def test_evaluate_cost_guard_state_disabled() -> None:
    out = evaluate_cost_guard_state(
        prev_active=False,
        enabled=False,
        metrics=CostGuardMetrics(100, 20, 20, 0, 0),
        thresholds=CostGuardThresholds(120, 24, 20, 0, 4, 100, 20, 16),
        hysteresis_enabled=True,
    )
    assert out["active"] is False
    assert out["reason"] == "DISABLED_IN_CONFIG"


def test_evaluate_cost_guard_state_hysteresis_hold() -> None:
    out = evaluate_cost_guard_state(
        prev_active=True,
        enabled=True,
        metrics=CostGuardMetrics(110, 24, 20, 0, 0),
        thresholds=CostGuardThresholds(120, 24, 20, 0, 4, 100, 20, 16),
        hysteresis_enabled=True,
    )
    assert out["active"] is True
    assert out["hysteresis_hold"] is True
    assert out["reason"] == "AUTO_RELAX_ACTIVE_HYSTERESIS_HOLD"


def test_evaluate_cost_guard_state_deactivates_when_off_thresholds_fail() -> None:
    out = evaluate_cost_guard_state(
        prev_active=True,
        enabled=True,
        metrics=CostGuardMetrics(90, 18, 10, 0, 0),
        thresholds=CostGuardThresholds(120, 24, 20, 0, 4, 100, 20, 16),
        hysteresis_enabled=True,
    )
    assert out["active"] is False
    assert str(out["reason"]).startswith("WAIT_")


def test_derive_off_threshold_clamps_ratio() -> None:
    assert derive_off_threshold(120, 0.8) == 96
    assert derive_off_threshold(120, 5.0) == 120
    assert derive_off_threshold(120, -1.0) == 1


def test_update_transition_window_tracks_changes() -> None:
    history, count = update_transition_window(
        history_ts=[100.0, 200.0, 290.0],
        now_ts=300.0,
        window_sec=120,
        changed=True,
    )
    assert history == [200.0, 290.0, 300.0]
    assert count == 3
