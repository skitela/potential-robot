from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

import numpy as np
import pandas as pd

from .economics import compute_trade_result, make_broker_economics
from .io_utils import ensure_dir, find_optional_file, normalize_ts, read_parquet_window, read_table, safe_float
from .paths import CompatPaths
from .registry import build_broker_economics_table, load_active_symbols


@dataclass(slots=True)
class LoadedSources:
    candidates: pd.DataFrame
    runtime: pd.DataFrame
    learning: pd.DataFrame
    qdm: pd.DataFrame
    ping: pd.DataFrame
    runtime_feedback: pd.DataFrame
    broker_economics: pd.DataFrame
    symbols: list[str]


def load_sources(paths: CompatPaths) -> LoadedSources:
    symbols = load_active_symbols(paths)

    candidates = read_table(paths.candidate_signals_norm_latest)
    runtime = read_table(paths.onnx_observations_norm_latest)
    learning = read_table(paths.learning_observations_v2_norm_latest)
    ping = read_table(paths.execution_ping_contract_csv)

    feedback_path = find_optional_file(paths.common_state_root, "paper_live_feedback_latest.json")
    runtime_feedback = read_table(feedback_path) if feedback_path else None

    candidates = candidates if candidates is not None else pd.DataFrame()
    runtime = runtime if runtime is not None else pd.DataFrame()
    learning = learning if learning is not None else pd.DataFrame()
    ping = ping if ping is not None else pd.DataFrame()
    runtime_feedback = runtime_feedback if runtime_feedback is not None else pd.DataFrame()

    for frame in (candidates, runtime, learning):
        if not frame.empty and "ts" in frame.columns:
            frame["ts"] = normalize_ts(frame["ts"])

    qdm = pd.DataFrame()
    if not candidates.empty and "ts" in candidates.columns:
        candidate_window_min = candidates["ts"].min() - pd.Timedelta("1D")
        candidate_window_max = candidates["ts"].max() + pd.Timedelta("1D")
        qdm = read_parquet_window(
            paths.qdm_minute_bars_latest,
            columns=[
                "symbol_alias",
                "bar_minute",
                "tick_count",
                "spread_mean",
                "spread_max",
                "mid_range_1m",
                "mid_return_1m",
            ],
            symbol_aliases=symbols,
            ts_col="bar_minute",
            ts_min=candidate_window_min,
            ts_max=candidate_window_max,
        )
    else:
        qdm = read_parquet_window(
            paths.qdm_minute_bars_latest,
            columns=[
                "symbol_alias",
                "bar_minute",
                "tick_count",
                "spread_mean",
                "spread_max",
                "mid_range_1m",
                "mid_return_1m",
            ],
            symbol_aliases=symbols,
        )
    if not qdm.empty and "bar_minute" in qdm.columns:
        qdm["bar_minute"] = normalize_ts(qdm["bar_minute"])
    if not ping.empty:
        ping = normalize_ping_contract(ping)

    broker_economics = build_broker_economics_table(paths, symbols)

    return LoadedSources(
        candidates=candidates,
        runtime=runtime,
        learning=learning,
        qdm=qdm,
        ping=ping,
        runtime_feedback=runtime_feedback,
        broker_economics=broker_economics,
        symbols=symbols,
    )


def normalize_ping_contract(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    rename_map = {
        "symbol": "symbol_alias",
        "operational_ping_ms": "server_operational_ping_ms",
        "paper_operational_ping_ms": "server_operational_ping_ms",
        "terminal_ping_ms": "server_terminal_ping_ms",
        "local_latency_us_avg": "server_local_latency_us_avg",
        "local_latency_us_max": "server_local_latency_us_max",
        "enabled": "server_ping_contract_enabled",
    }
    for src, dst in rename_map.items():
        if src in out.columns and dst not in out.columns:
            out[dst] = out[src]
    if "symbol_alias" not in out.columns:
        out["symbol_alias"] = "_global"
    if "ts" in out.columns:
        out["ts"] = normalize_ts(out["ts"])
    return out


def build_server_parity_tail_bridge(paths: CompatPaths) -> tuple[pd.DataFrame, dict[str, Any]]:
    src = load_sources(paths)
    candidates = src.candidates.copy()
    qdm = src.qdm.copy()
    base = pd.DataFrame({"symbol_alias": src.symbols})

    if not candidates.empty and "ts" in candidates.columns:
        candidates["candidate_minute"] = candidates["ts"].dt.floor("min")
        cwin = (
            candidates
            .groupby("symbol_alias", observed=True)["candidate_minute"]
            .agg(candidate_minute_min="min", candidate_minute_max="max")
            .reset_index()
        )
    else:
        cwin = pd.DataFrame(columns=["symbol_alias", "candidate_minute_min", "candidate_minute_max"])

    if not qdm.empty and "bar_minute" in qdm.columns:
        qdm["bar_minute"] = normalize_ts(qdm["bar_minute"]).dt.floor("min")
        qwin = (
            qdm
            .groupby("symbol_alias", observed=True)["bar_minute"]
            .max()
            .rename("qdm_minute_max")
            .reset_index()
        )
    else:
        qwin = pd.DataFrame(columns=["symbol_alias", "qdm_minute_max"])

    out = base.merge(cwin, on="symbol_alias", how="left").merge(qwin, on="symbol_alias", how="left")
    out["tail_state"] = "OK"
    out.loc[out["qdm_minute_max"].isna(), "tail_state"] = "BRAK_QDM"
    out.loc[out["qdm_minute_max"].notna() & out["candidate_minute_min"].isna(), "tail_state"] = "BRAK_KANDYDATOW"
    out.loc[
        out["qdm_minute_max"].notna()
        & out["candidate_minute_min"].notna()
        & (out["qdm_minute_max"] < out["candidate_minute_min"]),
        "tail_state",
    ] = "BRAK_SWIEZEGO_OGONA"
    ensure_dir(paths.server_parity_tail_bridge_latest.parent)
    out.to_parquet(paths.server_parity_tail_bridge_latest, index=False)
    missing_qdm_count = int((out["tail_state"] == "BRAK_QDM").sum())
    stale_tail_count = int((out["tail_state"] == "BRAK_SWIEZEGO_OGONA").sum())
    missing_candidate_count = int((out["tail_state"] == "BRAK_KANDYDATOW").sum())
    return out, {
        "rows": int(len(out)),
        "expected_symbols": src.symbols,
        "symbols_present": out["symbol_alias"].tolist(),
        "missing_tail_count": missing_qdm_count + stale_tail_count,
        "missing_qdm_count": missing_qdm_count,
        "stale_tail_count": stale_tail_count,
        "missing_candidate_count": missing_candidate_count,
        "symbols_without_candidates": out.loc[out["tail_state"] == "BRAK_KANDYDATOW", "symbol_alias"].tolist(),
        "output_path": str(paths.server_parity_tail_bridge_latest),
    }


def _merge_runtime_features(candidates: pd.DataFrame, runtime: pd.DataFrame) -> pd.DataFrame:
    if candidates.empty or runtime.empty:
        out = candidates.copy()
        if "runtime_latency_us" not in out.columns:
            out["runtime_latency_us"] = 0.0
        return out

    left = candidates.copy()
    right = runtime.copy()

    if "feedback_key" in left.columns and "feedback_key" in right.columns:
        keep = [c for c in right.columns if c in {
            "feedback_key", "runtime_channel", "teacher_score", "symbol_score",
            "latency_us", "teacher_available", "teacher_used", "available", "signal_valid"
        }]
        dedup = right.sort_values("ts").drop_duplicates("feedback_key", keep="last")
        out = left.merge(dedup[keep], on="feedback_key", how="left")
    else:
        out = left.copy()

    if "latency_us" not in out.columns or out["latency_us"].isna().any():
        keep = [c for c in right.columns if c in {
            "ts", "symbol_alias", "runtime_channel", "teacher_score", "symbol_score",
            "latency_us", "teacher_available", "teacher_used", "available", "signal_valid"
        }]
        right2 = right[keep].copy().sort_values("ts")
        pieces = []
        for symbol, grp in out.groupby("symbol_alias", sort=False, observed=True):
            lgrp = grp.sort_values("ts").copy()
            rgrp = right2.loc[right2["symbol_alias"] == symbol].sort_values("ts").copy()
            if rgrp.empty:
                pieces.append(lgrp)
                continue
            merged = pd.merge_asof(
                lgrp,
                rgrp,
                on="ts",
                by="symbol_alias",
                direction="nearest",
                tolerance=pd.Timedelta("90s"),
                suffixes=("", "_rt2"),
            )
            for col in ("runtime_channel", "teacher_score", "symbol_score", "latency_us", "teacher_available", "teacher_used", "available", "signal_valid"):
                alt = f"{col}_rt2"
                if alt in merged.columns:
                    if col in merged.columns:
                        merged[col] = merged[col].combine_first(merged[alt])
                    else:
                        merged[col] = merged[alt]
            merged = merged[[c for c in merged.columns if not c.endswith("_rt2")]]
            pieces.append(merged)
        out = pd.concat(pieces, ignore_index=True)

    rename_map = {
        "latency_us": "runtime_latency_us",
        "teacher_score": "teacher_runtime_score",
        "symbol_score": "symbol_runtime_score",
    }
    for src, dst in rename_map.items():
        if src in out.columns and dst not in out.columns:
            out[dst] = out[src]

    return out


def _merge_ping_features(frame: pd.DataFrame, ping: pd.DataFrame) -> pd.DataFrame:
    out = frame.copy()
    if ping.empty:
        out["server_operational_ping_ms"] = out.get("server_operational_ping_ms", 0.0)
        out["server_terminal_ping_ms"] = out.get("server_terminal_ping_ms", 0.0)
        out["server_local_latency_us_avg"] = out.get("server_local_latency_us_avg", 0.0)
        out["server_local_latency_us_max"] = out.get("server_local_latency_us_max", 0.0)
        out["server_ping_contract_enabled"] = out.get("server_ping_contract_enabled", 0)
        return out

    keep = [c for c in ping.columns if c in {
        "symbol_alias", "ts", "server_operational_ping_ms", "server_terminal_ping_ms",
        "server_local_latency_us_avg", "server_local_latency_us_max", "server_ping_contract_enabled"
    }]
    ping = ping[keep].copy()
    if "ts" in ping.columns:
        pieces = []
        for symbol, grp in out.groupby("symbol_alias", sort=False, observed=True):
            g = grp.sort_values("ts").copy()
            p = ping.loc[(ping["symbol_alias"] == symbol) | (ping["symbol_alias"] == "_global")].copy()
            if p.empty:
                g["server_ping_contract_enabled"] = 0
                pieces.append(g)
                continue

            if p["symbol_alias"].nunique() == 1 and p["symbol_alias"].iloc[0] == "_global":
                p = p.sort_values("ts").drop(columns=["symbol_alias"])
                merged = pd.merge_asof(
                    g,
                    p,
                    on="ts",
                    direction="nearest",
                    tolerance=pd.Timedelta("10min"),
                    suffixes=("", "_ping"),
                )
            else:
                p = p.sort_values("ts")
                merged = pd.merge_asof(
                    g,
                    p,
                    on="ts",
                    by="symbol_alias",
                    direction="nearest",
                    tolerance=pd.Timedelta("10min"),
                    suffixes=("", "_ping"),
                )
            if "server_ping_contract_enabled" not in merged.columns:
                merged["server_ping_contract_enabled"] = 1
            pieces.append(merged)
        out = pd.concat(pieces, ignore_index=True)
    else:
        p = ping.sort_values("symbol_alias").drop_duplicates("symbol_alias", keep="last")
        out = out.merge(p, on="symbol_alias", how="left")
    def _series_or_default(name: str, default: float) -> pd.Series:
        if name not in out.columns:
            return pd.Series([default] * len(out), index=out.index)
        return pd.to_numeric(out[name], errors="coerce").fillna(default)

    for col in ("server_operational_ping_ms", "server_terminal_ping_ms", "server_local_latency_us_avg", "server_local_latency_us_max"):
        out[col] = _series_or_default(col, 0.0)
    out["server_ping_contract_enabled"] = _series_or_default("server_ping_contract_enabled", 0).astype(int)
    return out


def _merge_qdm_features(frame: pd.DataFrame, qdm: pd.DataFrame) -> pd.DataFrame:
    out = frame.copy()
    if qdm.empty:
        out["qdm_data_present"] = 0
        out["qdm_tick_count"] = 0
        out["qdm_spread_mean"] = 0.0
        out["qdm_spread_max"] = 0.0
        out["qdm_mid_range_1m"] = 0.0
        out["qdm_mid_return_1m"] = 0.0
        return out

    qdm = qdm.copy()
    qdm["bar_minute"] = normalize_ts(qdm["bar_minute"]).dt.floor("min")
    out["candidate_minute"] = normalize_ts(out["ts"]).dt.floor("min")
    qdm["bar_minute_key"] = qdm["bar_minute"].astype("int64")
    out["candidate_minute_key"] = out["candidate_minute"].astype("int64")

    pieces = []
    qdm_keep = ["bar_minute_key", "bar_minute", "symbol_alias", "tick_count", "spread_mean", "spread_max", "mid_range_1m", "mid_return_1m"]
    for symbol, grp in out.groupby("symbol_alias", sort=False, observed=True):
        lgrp = grp.sort_values("candidate_minute_key", kind="mergesort").copy()
        rgrp = qdm.loc[qdm["symbol_alias"] == symbol, qdm_keep].sort_values("bar_minute_key", kind="mergesort")
        if rgrp.empty:
            lgrp["qdm_data_present"] = 0
            pieces.append(lgrp)
            continue
        merged = pd.merge_asof(
            lgrp,
            rgrp,
            left_on="candidate_minute_key",
            right_on="bar_minute_key",
            by="symbol_alias",
            direction="backward",
            tolerance=int(pd.Timedelta("10min").value),
            suffixes=("", "_qdm"),
        )
        merged["qdm_data_present"] = merged["bar_minute"].notna().astype(int)
        pieces.append(merged)
    out = pd.concat(pieces, ignore_index=True)
    out["qdm_tick_count"] = pd.to_numeric(out.get("tick_count"), errors="coerce").fillna(0).astype(int)
    out["qdm_spread_mean"] = pd.to_numeric(out.get("spread_mean"), errors="coerce").fillna(0.0)
    out["qdm_spread_max"] = pd.to_numeric(out.get("spread_max"), errors="coerce").fillna(0.0)
    out["qdm_mid_range_1m"] = pd.to_numeric(out.get("mid_range_1m"), errors="coerce").fillna(0.0)
    out["qdm_mid_return_1m"] = pd.to_numeric(out.get("mid_return_1m"), errors="coerce").fillna(0.0)
    return out.drop(columns=[c for c in ("bar_minute", "bar_minute_key", "candidate_minute", "candidate_minute_key", "tick_count", "spread_mean", "spread_max", "mid_range_1m", "mid_return_1m") if c in out.columns])


def _merge_outcomes(frame: pd.DataFrame, learning: pd.DataFrame, feedback: pd.DataFrame) -> pd.DataFrame:
    out = frame.copy()

    if not learning.empty:
        keep = [c for c in learning.columns if c in {"outcome_key", "advisory_match_key", "pnl", "close_reason", "ts"}]
        learn = learning[keep].copy()

        if "outcome_key" in out.columns and "outcome_key" in learn.columns:
            dedup = learn.sort_values("ts").drop_duplicates("outcome_key", keep="last")
            out = out.merge(dedup[[c for c in dedup.columns if c != "ts"]], on="outcome_key", how="left", suffixes=("", "_learn"))
        if ("pnl" not in out.columns or out["pnl"].isna().any()) and "advisory_match_key" in out.columns and "advisory_match_key" in learn.columns:
            dedup_adv = learn.sort_values("ts").drop_duplicates("advisory_match_key", keep="last")
            merged = out.merge(
                dedup_adv[[c for c in dedup_adv.columns if c in {"advisory_match_key", "pnl", "close_reason"}]],
                on="advisory_match_key",
                how="left",
                suffixes=("", "_adv"),
            )
            for col in ("pnl", "close_reason"):
                alt = f"{col}_adv"
                if alt in merged.columns:
                    if col in merged.columns:
                        merged[col] = merged[col].combine_first(merged[alt])
                    else:
                        merged[col] = merged[alt]
            merged = merged[[c for c in merged.columns if not c.endswith("_adv")]]
            out = merged

    if not feedback.empty and "feedback_key" in out.columns and "feedback_key" in feedback.columns:
        keep_fb = [c for c in feedback.columns if c in {
            "feedback_key", "net_pln", "gross_pln", "pnl", "commission_pln", "swap_pln", "extra_fee_pln",
            "spread_cost_pln", "slippage_cost_pln", "close_reason", "slippage_points_actual",
            "commission_account_ccy", "swap_account_ccy", "extra_fee_account_ccy", "fx_to_pln"
        }]
        if keep_fb:
            dedup_fb = feedback.drop_duplicates("feedback_key", keep="last")
            out = out.merge(dedup_fb[keep_fb], on="feedback_key", how="left", suffixes=("", "_fb"))

    return out


def build_master_training_frame(paths: CompatPaths) -> tuple[pd.DataFrame, dict[str, Any], LoadedSources]:
    src = load_sources(paths)
    candidates = src.candidates.copy()
    if candidates.empty:
        return pd.DataFrame(), {
            "rows": 0,
            "symbols": [],
            "expected_symbols": src.symbols,
            "candidate_symbols": [],
            "symbols_without_candidates": src.symbols,
            "symbols_without_rows": src.symbols,
            "symbols_without_labeled": src.symbols,
            "labeled_rows": 0,
        }, src

    candidates = candidates.loc[candidates["symbol_alias"].isin(src.symbols)].copy()
    candidates["ts"] = normalize_ts(candidates["ts"])
    candidate_symbols = sorted(candidates["symbol_alias"].dropna().unique().tolist())

    merged = _merge_qdm_features(candidates, src.qdm)
    merged = _merge_runtime_features(merged, src.runtime)
    merged = _merge_ping_features(merged, src.ping)
    merged = _merge_outcomes(merged, src.learning, src.runtime_feedback)
    if src.broker_economics is not None and not src.broker_economics.empty:
        broker_lookup = src.broker_economics.drop_duplicates("symbol_alias", keep="last").set_index("symbol_alias")
        broker_frame = pd.DataFrame(index=merged.index)
        for column in broker_lookup.columns:
            broker_frame[column] = merged["symbol_alias"].map(broker_lookup[column])
        merged = pd.concat([merged, broker_frame], axis=1)

    if "side_normalized" not in merged.columns and "side" in merged.columns:
        merged["side_normalized"] = merged["side"]

    def _num(name: str, default: float = 0.0) -> pd.Series:
        if name not in merged.columns:
            return pd.Series([default] * len(merged), index=merged.index, dtype=float)
        return pd.to_numeric(merged[name], errors="coerce").fillna(default)

    merged["lots"] = _num("lots", 1.0)
    merged["risk_multiplier"] = _num("risk_multiplier", 1.0)
    merged["spread_points"] = _num("spread_points", 0.0)
    merged["runtime_latency_us"] = _num("runtime_latency_us", 0.0)
    merged["teacher_runtime_score"] = _num("teacher_runtime_score", 0.0)
    merged["symbol_runtime_score"] = _num("symbol_runtime_score", 0.0)
    merged["pnl_account_ccy"] = _num("pnl", np.nan)
    merged["fx_to_pln"] = _num("fx_to_pln", np.nan).fillna(_num("fx_to_pln_default", 1.0))
    merged["held_minutes"] = _num("held_minutes", 1).astype(int)

    tick_value = _num("tick_value_account_ccy", 1.0)
    fx_to_pln = _num("fx_to_pln", 1.0)
    lots = _num("lots", 1.0)
    modeled_slip = _num("slippage_points_modeled", 0.0)
    commission_per_lot = _num("commission_per_lot_account_ccy", 0.0)

    merged["expected_cost_pln"] = ((merged["spread_points"].clip(lower=0) + modeled_slip.clip(lower=0)) * tick_value * lots * fx_to_pln) + commission_per_lot * lots * fx_to_pln

    price_motion_proxy_points = (_num("qdm_mid_range_1m", 0.0) * 10000.0).abs()
    raw_edge = _num("score", 0.0) * _num("confidence_score", 0.0) * price_motion_proxy_points * 0.0001 * tick_value * lots * fx_to_pln
    merged["pretrade_edge_estimate_pln"] = raw_edge - merged["expected_cost_pln"]

    net_known = _num("net_pln", np.nan)
    merged["outcome_known"] = (merged["pnl_account_ccy"].notna() | net_known.notna()).astype(int)

    ledger_cols = [
        "gross_pln",
        "spread_cost_pln",
        "slippage_cost_pln",
        "commission_pln",
        "swap_pln",
        "extra_fee_pln",
        "net_pln",
        "edge_after_cost_pln",
        "edge_after_cost_bps",
    ]
    ledger_df = pd.DataFrame(index=merged.index, columns=ledger_cols, dtype=float)

    known_mask = merged["outcome_known"] == 1
    explicit_mask = known_mask & merged.get("net_pln", pd.Series(index=merged.index, dtype=float)).notna()
    if explicit_mask.any():
        explicit_df = merged.loc[explicit_mask].copy()
        explicit_df["gross_pln"] = pd.to_numeric(explicit_df.get("gross_pln"), errors="coerce").fillna(pd.to_numeric(explicit_df.get("pnl"), errors="coerce").fillna(0.0) * pd.to_numeric(explicit_df.get("fx_to_pln"), errors="coerce").fillna(1.0))
        explicit_df["spread_cost_pln"] = pd.to_numeric(explicit_df.get("spread_cost_pln"), errors="coerce").fillna(0.0)
        explicit_df["slippage_cost_pln"] = pd.to_numeric(explicit_df.get("slippage_cost_pln"), errors="coerce").fillna(0.0)
        explicit_df["commission_pln"] = pd.to_numeric(explicit_df.get("commission_pln"), errors="coerce").fillna(0.0)
        explicit_df["swap_pln"] = pd.to_numeric(explicit_df.get("swap_pln"), errors="coerce").fillna(0.0)
        explicit_df["extra_fee_pln"] = pd.to_numeric(explicit_df.get("extra_fee_pln"), errors="coerce").fillna(0.0)
        explicit_df["net_pln"] = pd.to_numeric(explicit_df.get("net_pln"), errors="coerce").fillna(0.0)
        denom = (
            explicit_df["gross_pln"].abs()
            + explicit_df["spread_cost_pln"]
            + explicit_df["slippage_cost_pln"]
            + explicit_df["commission_pln"]
            + explicit_df["swap_pln"]
            + explicit_df["extra_fee_pln"]
        ).clip(lower=1.0)
        explicit_df["edge_after_cost_pln"] = explicit_df["net_pln"]
        explicit_df["edge_after_cost_bps"] = (explicit_df["net_pln"] / denom) * 10000.0
        ledger_df.loc[explicit_df.index, ledger_cols] = explicit_df[ledger_cols]

    calc_mask = known_mask & ~explicit_mask
    if calc_mask.any():
        calc_df = merged.loc[calc_mask].copy()
        def _col(name: str, default: float = 0.0) -> pd.Series:
            if name not in calc_df.columns:
                return pd.Series([default] * len(calc_df), index=calc_df.index, dtype=float)
            return pd.to_numeric(calc_df[name], errors="coerce").fillna(default)

        lots_s = _col("lots", 1.0)
        tick_value_s = _col("tick_value_account_ccy", 1.0)
        fx_s = _col("fx_to_pln", np.nan).fillna(_col("fx_to_pln_default", 1.0))
        pnl_ccy_s = _col("pnl_account_ccy", np.nan)
        spread_entry_s = _col("spread_points", np.nan).fillna(_col("spread_points_modeled", 0.0))
        spread_exit_s = _col("spread_points_exit", 0.0)
        slippage_s = _col("slippage_points_actual", np.nan).fillna(_col("slippage_points_modeled", 0.0))
        commission_ccy_s = _col("commission_account_ccy", np.nan).fillna(_col("commission_per_lot_account_ccy", 0.0) * lots_s)
        held_minutes_s = _col("held_minutes", 1.0)
        swap_long_s = _col("swap_long_account_ccy", 0.0)
        swap_short_s = _col("swap_short_account_ccy", 0.0)
        extra_fee_ccy_s = _col("extra_fee_account_ccy", 0.0)
        side_s = calc_df.get("side_normalized", calc_df.get("side", pd.Series(["BUY"] * len(calc_df), index=calc_df.index))).astype(str).str.upper()
        swap_default_s = np.where(side_s == "BUY", swap_long_s, swap_short_s) * np.maximum(1.0, held_minutes_s / 1440.0)
        swap_ccy_s = _col("swap_account_ccy", np.nan).fillna(pd.Series(swap_default_s, index=calc_df.index))

        gross_pln_s = pnl_ccy_s.fillna(0.0) * fx_s
        spread_cost_pln_s = (spread_entry_s + spread_exit_s) * tick_value_s * lots_s * fx_s
        slippage_cost_pln_s = slippage_s * tick_value_s * lots_s * fx_s
        commission_pln_s = commission_ccy_s * fx_s
        swap_pln_s = swap_ccy_s * fx_s
        extra_fee_pln_s = extra_fee_ccy_s * fx_s
        total_cost_pln_s = spread_cost_pln_s + slippage_cost_pln_s + commission_pln_s + swap_pln_s + extra_fee_pln_s
        net_pln_s = gross_pln_s - total_cost_pln_s
        denom_s = (gross_pln_s.abs() + total_cost_pln_s).clip(lower=1.0)

        calc_ledger = pd.DataFrame(
            {
                "gross_pln": gross_pln_s,
                "spread_cost_pln": spread_cost_pln_s,
                "slippage_cost_pln": slippage_cost_pln_s,
                "commission_pln": commission_pln_s,
                "swap_pln": swap_pln_s,
                "extra_fee_pln": extra_fee_pln_s,
                "net_pln": net_pln_s,
                "edge_after_cost_pln": net_pln_s,
                "edge_after_cost_bps": (net_pln_s / denom_s) * 10000.0,
            },
            index=calc_df.index,
        )
        ledger_df.loc[calc_df.index, ledger_cols] = calc_ledger[ledger_cols]

    merged = pd.concat([merged, ledger_df], axis=1)

    merged.loc[merged["outcome_known"] == 0, ["gross_pln", "spread_cost_pln", "slippage_cost_pln", "commission_pln", "swap_pln", "extra_fee_pln", "net_pln", "edge_after_cost_pln", "edge_after_cost_bps"]] = np.nan

    merged_symbols = sorted(merged["symbol_alias"].dropna().unique().tolist())
    labeled_symbols = sorted(merged.loc[merged["outcome_known"] == 1, "symbol_alias"].dropna().unique().tolist())
    summary = {
        "rows": int(len(merged)),
        "symbols": merged_symbols,
        "expected_symbols": src.symbols,
        "candidate_symbols": candidate_symbols,
        "symbols_without_candidates": sorted(set(src.symbols) - set(candidate_symbols)),
        "symbols_without_rows": sorted(set(src.symbols) - set(merged_symbols)),
        "symbols_without_labeled": sorted(set(src.symbols) - set(labeled_symbols)),
        "labeled_rows": int(merged["outcome_known"].sum()),
        "candidate_rows": int(len(candidates)),
        "runtime_rows": int(len(src.runtime)),
        "learning_rows": int(len(src.learning)),
    }
    return merged, summary, src


def build_broker_net_ledger(paths: CompatPaths) -> tuple[pd.DataFrame, dict[str, Any]]:
    frame, summary, _ = build_master_training_frame(paths)
    if frame.empty:
        out = pd.DataFrame()
        ensure_dir(paths.broker_net_ledger_latest.parent)
        out.to_parquet(paths.broker_net_ledger_latest, index=False)
        return out, {
            "rows": 0,
            "labeled_rows": 0,
            "expected_symbols": summary.get("expected_symbols", []),
            "symbols": [],
            "symbols_without_rows": summary.get("symbols_without_rows", []),
            "symbols_without_candidates": summary.get("symbols_without_candidates", []),
            "output_path": str(paths.broker_net_ledger_latest),
        }

    ledger_cols = [
        "ts", "symbol_alias", "side", "side_normalized", "lots", "score", "confidence_score",
        "spread_points", "close_reason", "outcome_key", "feedback_key",
        "gross_pln", "spread_cost_pln", "slippage_cost_pln", "commission_pln", "swap_pln", "extra_fee_pln",
        "net_pln", "edge_after_cost_pln", "edge_after_cost_bps", "outcome_known"
    ]
    available = [c for c in ledger_cols if c in frame.columns]
    ledger = frame[available].copy()
    if "slippage_cost_pln" in ledger.columns and "slippage_pln" not in ledger.columns:
        ledger["slippage_pln"] = ledger["slippage_cost_pln"]
    if "net_pln" in ledger.columns and "net_pln_broker_full" not in ledger.columns:
        ledger["net_pln_broker_full"] = ledger["net_pln"]
    ensure_dir(paths.broker_net_ledger_latest.parent)
    ledger.to_parquet(paths.broker_net_ledger_latest, index=False)
    labeled_mask = (ledger.get("outcome_known", 0) == 1)
    return ledger, {
        "rows": int(len(ledger)),
        "labeled_rows": int(labeled_mask.sum()),
        "spread_rows": int(ledger.get("spread_cost_pln", pd.Series(dtype=float)).notna().sum()) if "spread_cost_pln" in ledger.columns else 0,
        "slippage_rows": int(ledger.get("slippage_cost_pln", pd.Series(dtype=float)).notna().sum()) if "slippage_cost_pln" in ledger.columns else 0,
        "commission_rows": int(ledger.get("commission_pln", pd.Series(dtype=float)).notna().sum()) if "commission_pln" in ledger.columns else 0,
        "swap_rows": int(ledger.get("swap_pln", pd.Series(dtype=float)).notna().sum()) if "swap_pln" in ledger.columns else 0,
        "net_rows": int(ledger.get("net_pln", pd.Series(dtype=float)).notna().sum()) if "net_pln" in ledger.columns else 0,
        "output_path": str(paths.broker_net_ledger_latest),
        "expected_symbols": summary.get("expected_symbols", []),
        "symbols": summary["symbols"],
        "symbols_without_rows": summary.get("symbols_without_rows", []),
        "symbols_without_candidates": summary.get("symbols_without_candidates", []),
    }
