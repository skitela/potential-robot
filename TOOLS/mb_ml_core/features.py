from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

import numpy as np
import pandas as pd


LEAKAGE_COLUMNS = {
    "net_pln",
    "gross_pln",
    "spread_cost_pln",
    "slippage_cost_pln",
    "commission_pln",
    "swap_pln",
    "extra_fee_pln",
    "pnl",
    "pnl_account_ccy",
    "outcome_pnl",
    "realized_pnl",
    "target_gate_positive",
    "y_gate",
    "y_edge_reg",
    "y_fill",
    "y_slippage_reg",
}

BASE_NUMERIC_FEATURES = [
    "score",
    "confidence_score",
    "risk_multiplier",
    "lots",
    "spread_points",
    "candle_score",
    "renko_score",
    "renko_run_length",
    "renko_reversal_flag",
    "runtime_latency_us",
    "server_operational_ping_ms",
    "server_terminal_ping_ms",
    "server_local_latency_us_avg",
    "server_local_latency_us_max",
    "qdm_spread_mean",
    "qdm_spread_max",
    "qdm_mid_range_1m",
    "qdm_mid_return_1m",
    "qdm_tick_count",
    "qdm_data_present",
    "server_ping_contract_enabled",
    "pretrade_edge_estimate_pln",
    "expected_cost_pln",
    "teacher_global_score",
    "teacher_runtime_score",
    "symbol_runtime_score",
]

BASE_CATEGORICAL_FEATURES = [
    "symbol_alias",
    "setup_type",
    "side_normalized",
    "market_regime",
    "spread_regime",
    "execution_regime",
    "confidence_bucket",
    "candle_bias",
    "candle_quality_grade",
    "renko_bias",
    "renko_quality_grade",
    "session_profile",
    "runtime_channel",
]


@dataclass(slots=True)
class FeatureContract:
    numeric_features: list[str]
    categorical_features: list[str]
    all_features: list[str]


def normalize_runtime_columns(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    rename_map = {
        "latency_us": "runtime_latency_us",
        "paper_operational_ping_ms": "server_operational_ping_ms",
        "operational_ping_ms": "server_operational_ping_ms",
        "terminal_ping_ms": "server_terminal_ping_ms",
        "local_latency_us_avg": "server_local_latency_us_avg",
        "local_latency_us_max": "server_local_latency_us_max",
        "teacher_score": "teacher_runtime_score",
        "symbol_score": "symbol_runtime_score",
    }
    for src, dst in rename_map.items():
        if src in out.columns and dst not in out.columns:
            out[dst] = out[src]
    if "side_normalized" not in out.columns and "side" in out.columns:
        out["side_normalized"] = out["side"]
    return out


def build_feature_frame(df: pd.DataFrame, ts_col: str = "ts") -> tuple[pd.DataFrame, FeatureContract]:
    out = normalize_runtime_columns(df)
    out = out.copy()
    out[ts_col] = pd.to_datetime(out[ts_col], utc=True, errors="coerce")

    if "hour" not in out.columns:
        out["hour"] = out[ts_col].dt.hour.fillna(0).astype(int)
    if "day_of_week" not in out.columns:
        out["day_of_week"] = out[ts_col].dt.dayofweek.fillna(0).astype(int)
    if "session_profile" not in out.columns:
        out["session_profile"] = np.select(
            [
                out["hour"].between(0, 6),
                out["hour"].between(7, 12),
                out["hour"].between(13, 17),
            ],
            ["ASIA", "LONDON_OPEN", "US_OVERLAP"],
            default="QUIET",
        )

    for col in BASE_NUMERIC_FEATURES:
        if col not in out.columns:
            out[col] = 0.0

    out["hour_sin"] = np.sin(2.0 * np.pi * out["hour"] / 24.0)
    out["hour_cos"] = np.cos(2.0 * np.pi * out["hour"] / 24.0)
    out["dow_sin"] = np.sin(2.0 * np.pi * out["day_of_week"] / 7.0)
    out["dow_cos"] = np.cos(2.0 * np.pi * out["day_of_week"] / 7.0)
    out["spread_x_score"] = out["spread_points"] * out["score"]
    out["latency_x_spread"] = out["runtime_latency_us"] * out["spread_points"]
    out["score_x_confidence"] = out["score"] * out["confidence_score"]
    out["qdm_pressure_proxy"] = out["qdm_spread_max"].abs() * (1.0 + out["qdm_tick_count"].abs())
    out["chaos_proxy"] = out["spread_points"].abs() + out["qdm_mid_range_1m"].abs() + out["qdm_spread_max"].abs()

    numeric_features = BASE_NUMERIC_FEATURES + [
        "hour_sin",
        "hour_cos",
        "dow_sin",
        "dow_cos",
        "spread_x_score",
        "latency_x_spread",
        "score_x_confidence",
        "qdm_pressure_proxy",
        "chaos_proxy",
        "hour",
        "day_of_week",
    ]
    categorical_features = BASE_CATEGORICAL_FEATURES.copy()

    numeric_features = [f for f in numeric_features if f in out.columns and f not in LEAKAGE_COLUMNS]
    categorical_features = [f for f in categorical_features if f in out.columns and f not in LEAKAGE_COLUMNS]
    all_features = categorical_features + numeric_features

    return out, FeatureContract(numeric_features=numeric_features, categorical_features=categorical_features, all_features=all_features)


def assert_no_target_leakage(features: Iterable[str]) -> None:
    overlap = sorted(set(features).intersection(LEAKAGE_COLUMNS))
    if overlap:
        raise ValueError(f"Wykryto przeciek celu do cech: {overlap}")
