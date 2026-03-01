from __future__ import annotations

from TOOLS.lab_daily_pipeline import KeyStats, compute_lab_score, decide_lab_action, evaluate_lab_to_shadow_gate


def _sample_gates() -> dict:
    return {
        "min_days_covered": 10,
        "min_explore_trades": 120,
        "min_strict_trades": 40,
        "min_explore_win_rate": 0.52,
        "min_explore_net_pips_per_trade": 0.25,
        "min_strict_net_pips_per_trade": 0.05,
        "max_explore_loss_day_ratio": 0.4,
        "max_explore_cost_share": 0.65,
    }


def _sample_weights() -> dict:
    return {
        "net_pips_per_trade": 0.45,
        "win_rate": 0.2,
        "sample_size": 0.15,
        "loss_day_penalty": 0.1,
        "cost_share_penalty": 0.1,
    }


def test_lab_to_shadow_gate_ready() -> None:
    explore = KeyStats(window_id="FX_AM", symbol="EURUSD")
    explore.days = {f"2026-02-{d:02d}" for d in range(1, 13)}
    explore.trades = 140
    explore.wins = 78
    explore.losses = 52
    explore.net_pips_sum = 45.0
    explore.gross_pips_sum = 150.0
    explore.cost_pips_sum = 70.0
    explore.negative_days = 4

    strict = KeyStats(window_id="FX_AM", symbol="EURUSD")
    strict.days = {f"2026-02-{d:02d}" for d in range(1, 13)}
    strict.trades = 60
    strict.wins = 33
    strict.losses = 21
    strict.net_pips_sum = 9.0
    strict.gross_pips_sum = 55.0
    strict.cost_pips_sum = 18.0
    strict.negative_days = 3

    ready, checks, failed = evaluate_lab_to_shadow_gate(explore=explore, strict=strict, gates=_sample_gates())
    assert ready is True
    assert failed == []
    assert all(checks.values())


def test_lab_to_shadow_gate_not_ready_on_sample_and_edge() -> None:
    explore = KeyStats(window_id="FX_ASIA", symbol="USDJPY")
    explore.days = {"2026-02-01", "2026-02-02"}
    explore.trades = 12
    explore.wins = 5
    explore.losses = 6
    explore.net_pips_sum = -4.0
    explore.gross_pips_sum = 22.0
    explore.cost_pips_sum = 18.0
    explore.negative_days = 2

    strict = KeyStats(window_id="FX_ASIA", symbol="USDJPY")
    strict.days = {"2026-02-01", "2026-02-02"}
    strict.trades = 3
    strict.wins = 1
    strict.losses = 2
    strict.net_pips_sum = -1.0
    strict.gross_pips_sum = 4.0
    strict.cost_pips_sum = 3.0
    strict.negative_days = 2

    ready, checks, failed = evaluate_lab_to_shadow_gate(explore=explore, strict=strict, gates=_sample_gates())
    assert ready is False
    assert "min_explore_trades" in failed
    assert "min_explore_net_pips_per_trade" in failed
    assert checks["min_explore_trades"] is False


def test_score_prefers_better_edge_with_other_factors_similar() -> None:
    e1 = KeyStats(window_id="FX_AM", symbol="EURUSD")
    e1.days = {f"2026-02-{d:02d}" for d in range(1, 13)}
    e1.trades = 120
    e1.wins = 68
    e1.losses = 45
    e1.net_pips_sum = 60.0
    e1.gross_pips_sum = 170.0
    e1.cost_pips_sum = 72.0
    e1.negative_days = 4

    e2 = KeyStats(window_id="FX_AM", symbol="GBPUSD")
    e2.days = set(e1.days)
    e2.trades = 120
    e2.wins = 66
    e2.losses = 47
    e2.net_pips_sum = 24.0
    e2.gross_pips_sum = 145.0
    e2.cost_pips_sum = 70.0
    e2.negative_days = 4

    strict = KeyStats(window_id="FX_AM", symbol="EURUSD")
    strict.days = set(e1.days)
    strict.trades = 50
    strict.wins = 28
    strict.losses = 19
    strict.net_pips_sum = 6.0
    strict.gross_pips_sum = 40.0
    strict.cost_pips_sum = 16.0
    strict.negative_days = 3

    s1 = compute_lab_score(explore=e1, strict=strict, weights=_sample_weights())
    s2 = compute_lab_score(explore=e2, strict=strict, weights=_sample_weights())
    assert s1 > s2


def test_action_selection() -> None:
    explore = KeyStats(window_id="FX_AM", symbol="EURUSD")
    strict = KeyStats(window_id="FX_AM", symbol="EURUSD")

    explore.trades = 20
    assert decide_lab_action(False, explore, strict, ["min_explore_trades"]) == "ZBIERAJ_DANE"

    explore.trades = 200
    explore.net_pips_sum = -2.0
    assert decide_lab_action(False, explore, strict, ["min_explore_net_pips_per_trade"]) == "DOCIŚNIJ"

    explore.trades = 200
    explore.net_pips_sum = 100.0
    strict.trades = 0
    assert decide_lab_action(False, explore, strict, ["min_strict_trades"]) == "POLUZUJ_TESTOWO"

    assert decide_lab_action(True, explore, strict, []) == "KANDYDAT_SHADOW"
