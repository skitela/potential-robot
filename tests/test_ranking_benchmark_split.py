from TOOLS.ranking_benchmark_strict_overlay import _split_latency_profile


def test_split_latency_profile_separates_trading_and_orchestration() -> None:
    stress_report = {
        "workers": {
            "scud_once": {"ok_runs": 10, "latency_p50_sec": 0.4, "latency_p95_sec": 0.6},
            "db_writer": {"ok_runs": 20, "latency_p50_sec": 0.1, "latency_p95_sec": 0.2},
            "dyrygent_trace": {"ok_runs": 15, "latency_p50_sec": 0.05, "latency_p95_sec": 0.08},
            "dyrygent_external": {"ok_runs": 5, "latency_p50_sec": 2.6, "latency_p95_sec": 2.9},
            "dyrygent_scan": {"ok_runs": 5, "latency_p50_sec": 2.5, "latency_p95_sec": 2.8},
            "learner_once": {"ok_runs": 5, "latency_p50_sec": 0.3, "latency_p95_sec": 0.4},
        }
    }
    out = _split_latency_profile(stress_report)
    trading = out["trading_path"]
    orchestration = out["orchestration_path"]
    assert float(trading["latency_p95_sec_max"]) < 1.0
    assert float(orchestration["latency_p95_sec_max"]) > 2.0
