from __future__ import annotations

import datetime as dt

import pandas as pd


class _DummyBarsStore:
    def __init__(self, df: pd.DataFrame | None):
        self._df = df

    def read_recent_df(self, base_symbol: str, limit: int):  # noqa: ARG002
        return self._df


class _DummyEngine:
    def __init__(self, bars_store):
        self.bars_store = bars_store
        self.copy_rates_calls = 0

    def copy_rates(self, symbol: str, grp: str, timeframe: int, n: int):  # noqa: ARG002
        self.copy_rates_calls += 1
        return None


class _DummyGov:
    def consume(self, *args, **kwargs):  # noqa: ANN002,ANN003,D401
        return True


def test_inspect_m5_store_readiness_marks_stale_store() -> None:
    from BIN import safetybot as sb

    stale_time = pd.Timestamp("2026-03-06T22:50:00Z").tz_convert(sb.TZ_PL)
    df = pd.DataFrame(
        [
            {"time": stale_time, "open": 1.0, "high": 1.1, "low": 0.9, "close": 1.05},
        ]
        * 120
    )
    state = sb.inspect_m5_store_readiness(
        _DummyBarsStore(df),
        "USDJPY",
        120,
        dt.datetime(2026, 3, 7, 8, 0, tzinfo=dt.timezone.utc).timestamp(),
        timeframe_min=5,
    )
    assert state["rows"] == 120
    assert state["stale"] is True
    assert state["fresh_ok"] is False
    assert float(state["age_s"]) > float(state["max_age_sec"])


def test_m5_indicators_if_due_reports_store_stale_before_copy_rates() -> None:
    from BIN import safetybot as sb

    orig_strict = getattr(sb.CFG, "hybrid_m5_no_fetch_strict", None)
    orig_hard = getattr(sb.CFG, "hybrid_no_mt5_data_fetch_hard", None)
    orig_bar_age = getattr(sb.CFG, "hybrid_snapshot_bar_max_age_sec", None)
    orig_tf = getattr(sb.CFG, "timeframe_trade", None)
    orig_pull = getattr(sb.CFG, "m5_pull_sec_eco", None)

    stale_time = pd.Timestamp("2026-03-06T22:50:00Z").tz_convert(sb.TZ_PL)
    df = pd.DataFrame(
        [
            {"time": stale_time, "open": 1.0, "high": 1.1, "low": 0.9, "close": 1.05},
        ]
        * 120
    )
    engine = _DummyEngine(_DummyBarsStore(df))
    config = type("Cfg", (), {"scheduler": {}})()
    strat = sb.StandardStrategy(
        engine=engine,
        gov=_DummyGov(),
        throttle=object(),
        db=object(),
        config=config,
        risk_manager=object(),
    )

    try:
        sb.CFG.hybrid_m5_no_fetch_strict = True
        sb.CFG.hybrid_no_mt5_data_fetch_hard = True
        sb.CFG.hybrid_snapshot_bar_max_age_sec = 3600
        sb.CFG.timeframe_trade = 5
        sb.CFG.m5_pull_sec_eco = 300

        out = strat.m5_indicators_if_due("USDJPY.pro", "FX", "ECO")
        assert out is None
        assert engine.copy_rates_calls == 0
        assert int(strat._skip_total.get("M5_STORE_STALE", 0)) == 1
        assert int(strat._skip_total.get("M5_DATA_SHORT", 0)) == 0
    finally:
        if orig_strict is not None:
            sb.CFG.hybrid_m5_no_fetch_strict = orig_strict
        if orig_hard is not None:
            sb.CFG.hybrid_no_mt5_data_fetch_hard = orig_hard
        if orig_bar_age is not None:
            sb.CFG.hybrid_snapshot_bar_max_age_sec = orig_bar_age
        if orig_tf is not None:
            sb.CFG.timeframe_trade = orig_tf
        if orig_pull is not None:
            sb.CFG.m5_pull_sec_eco = orig_pull
