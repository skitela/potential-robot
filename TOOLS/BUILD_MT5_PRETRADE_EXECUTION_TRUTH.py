from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import TYPE_CHECKING, Iterable

from mb_ml_core.io_utils import ensure_dir
from mb_ml_core.paths import CompatPaths

if TYPE_CHECKING:
    import pandas as pd


def _import_pandas():
    import pandas as pd  # type: ignore

    return pd


def _folder_has_csvs(folder: Path) -> bool:
    return folder.exists() and any(folder.glob("*.csv"))


def _safe_read_csvs(folder: Path) -> "pd.DataFrame":
    pd = _import_pandas()

    if not folder.exists():
        return pd.DataFrame()

    files = sorted(folder.glob("*.csv"))
    if not files:
        return pd.DataFrame()

    frames: list[pd.DataFrame] = []
    for path in files:
        frame = pd.read_csv(path, sep=";", dtype=str, keep_default_na=False)
        frame["__source_file"] = str(path)
        frames.append(frame)
    return pd.concat(frames, ignore_index=True)


def _to_numeric(df: "pd.DataFrame", cols: Iterable[str]) -> "pd.DataFrame":
    pd = _import_pandas()
    out = df.copy()
    for col in cols:
        if col in out.columns:
            out[col] = pd.to_numeric(out[col], errors="coerce")
    return out


def _to_datetime(df: "pd.DataFrame", cols: Iterable[str]) -> "pd.DataFrame":
    pd = _import_pandas()
    out = df.copy()
    for col in cols:
        if col in out.columns:
            out[col] = pd.to_datetime(out[col], errors="coerce", utc=True)
    return out


def _safe_read_parquet(path: Path, columns: list[str] | None = None) -> "pd.DataFrame":
    pd = _import_pandas()

    if not path.exists():
        return pd.DataFrame()

    try:
        return pd.read_parquet(path, columns=columns)
    except Exception:
        return pd.DataFrame()


def _normalize_pretrade(df: "pd.DataFrame") -> "pd.DataFrame":
    if df.empty:
        return df

    out = _to_numeric(
        df,
        [
            "requested_volume",
            "requested_price",
            "requested_sl",
            "requested_tp",
            "digits",
            "point",
            "tick_size",
            "volume_min",
            "volume_max",
            "volume_step",
            "bid",
            "ask",
            "spread_points",
            "check_retcode",
            "margin_required",
            "margin_free",
            "margin_level",
            "equity",
            "balance",
            "profit_if_tp",
            "profit_if_sl",
        ],
    )
    out = _to_datetime(out, ["server_time", "utc_time"])
    if "check_function_ok" in out.columns:
        out["check_function_ok"] = out["check_function_ok"].astype(str).str.strip().str.lower().isin({"1", "true", "yes", "on"})
    return out


def _normalize_execution(df: "pd.DataFrame") -> "pd.DataFrame":
    if df.empty:
        return df

    out = _to_numeric(
        df,
        [
            "result_retcode",
            "order_ticket",
            "deal_ticket",
            "position_ticket",
            "request_volume",
            "request_price",
            "execution_volume",
            "execution_price",
            "bid",
            "ask",
            "point",
            "digits",
            "spread_points",
            "slippage_points",
            "commission",
            "swap",
            "fee",
            "profit",
            "net_observed",
            "time_msc",
        ],
    )
    out = _to_datetime(out, ["server_time"])
    return out


def _latest_pretrade_per_candidate(pretrade: "pd.DataFrame") -> "pd.DataFrame":
    if pretrade.empty:
        return pretrade

    work = pretrade.copy()
    sort_cols = [col for col in ["server_time", "utc_time"] if col in work.columns]
    if sort_cols:
        work = work.sort_values(sort_cols)
    if {"symbol_alias", "candidate_id"}.issubset(work.columns):
        work = work.drop_duplicates(subset=["symbol_alias", "candidate_id"], keep="last")
    return work


def _merge_truth(pretrade: "pd.DataFrame", execution: "pd.DataFrame") -> "pd.DataFrame":
    pd = _import_pandas()

    if execution.empty:
        return pd.DataFrame()
    if pretrade.empty:
        return execution.copy()
    if not {"symbol_alias", "candidate_id"}.issubset(pretrade.columns) or not {"symbol_alias", "candidate_id"}.issubset(execution.columns):
        return execution.copy()
    latest_pretrade = _latest_pretrade_per_candidate(pretrade)
    return execution.merge(latest_pretrade, how="left", on=["symbol_alias", "candidate_id"], suffixes=("_exec", "_pre"))


def _extract_candidate_ts(candidate_id: object) -> int | None:
    if candidate_id is None:
        return None

    token = str(candidate_id).strip()
    if not token:
        return None

    match = re.search(r"(\d{9,12})", token)
    if not match:
        return None

    try:
        return int(match.group(1))
    except Exception:
        return None


def _normalize_contract_ts(df: "pd.DataFrame") -> "pd.DataFrame":
    pd = _import_pandas()

    if df.empty:
        return df

    out = df.copy()
    if "ts" in out.columns:
        out["ts"] = pd.to_numeric(out["ts"], errors="coerce").astype("Int64")
    return out


def _load_contract_inputs(contracts_dir: Path) -> dict[str, "pd.DataFrame"]:
    return {
        "candidate_signals": _normalize_contract_ts(
            _safe_read_parquet(
                contracts_dir / "candidate_signals_norm_latest.parquet",
                columns=[
                    "symbol_alias",
                    "ts",
                    "accepted",
                    "feedback_key",
                    "outcome_key",
                    "advisory_match_key",
                ],
            )
        ),
        "onnx_observations": _normalize_contract_ts(
            _safe_read_parquet(
                contracts_dir / "onnx_observations_norm_latest.parquet",
                columns=[
                    "symbol_alias",
                    "ts",
                    "feedback_key",
                    "runtime_channel",
                    "available",
                    "teacher_used",
                ],
            )
        ),
        "learning_observations": _safe_read_parquet(
            contracts_dir / "learning_observations_v2_norm_latest.parquet",
            columns=[
                "symbol_alias",
                "advisory_match_key",
                "pnl",
                "close_reason",
            ],
        ),
    }


def _build_candidate_contract_summary(candidate_signals: "pd.DataFrame") -> "pd.DataFrame":
    pd = _import_pandas()

    if candidate_signals.empty:
        return pd.DataFrame()

    work = candidate_signals.copy()
    if "accepted" in work.columns:
        work["accepted"] = pd.to_numeric(work["accepted"], errors="coerce").fillna(0)

    grouped = work.groupby(["symbol_alias", "ts"], dropna=False)
    summary = grouped.agg(
        candidate_rows_raw=("symbol_alias", "size"),
        candidate_accept_rows=("accepted", "sum"),
        candidate_feedback_keys=("feedback_key", "nunique"),
        candidate_outcome_keys=("outcome_key", "nunique"),
        candidate_advisory_keys=("advisory_match_key", "nunique"),
    ).reset_index()

    advisory_primary = (
        work.loc[work["advisory_match_key"].astype(str).str.len() > 0, ["symbol_alias", "ts", "advisory_match_key"]]
        .drop_duplicates()
        .groupby(["symbol_alias", "ts"], dropna=False)
        .first()
        .reset_index()
        .rename(columns={"advisory_match_key": "advisory_match_key_primary"})
    )

    feedback_primary = (
        work.loc[work["feedback_key"].astype(str).str.len() > 0, ["symbol_alias", "ts", "feedback_key"]]
        .drop_duplicates()
        .groupby(["symbol_alias", "ts"], dropna=False)
        .first()
        .reset_index()
        .rename(columns={"feedback_key": "feedback_key_primary"})
    )

    out = summary.merge(advisory_primary, how="left", on=["symbol_alias", "ts"])
    out = out.merge(feedback_primary, how="left", on=["symbol_alias", "ts"])
    out["candidate_accept_rate"] = out["candidate_accept_rows"] / out["candidate_rows_raw"].where(out["candidate_rows_raw"] > 0, 1)
    return out


def _build_onnx_contract_summary(onnx_observations: "pd.DataFrame") -> "pd.DataFrame":
    pd = _import_pandas()

    if onnx_observations.empty:
        return pd.DataFrame()

    work = onnx_observations.copy()
    for col in ["available", "teacher_used"]:
        if col in work.columns:
            work[col] = pd.to_numeric(work[col], errors="coerce").fillna(0)

    grouped = work.groupby(["symbol_alias", "ts"], dropna=False)
    summary = grouped.agg(
        onnx_rows=("symbol_alias", "size"),
        onnx_available_rows=("available", "sum"),
        onnx_teacher_used_rows=("teacher_used", "sum"),
        onnx_feedback_keys=("feedback_key", "nunique"),
        onnx_runtime_channels=("runtime_channel", "nunique"),
    ).reset_index()
    summary["onnx_available_rate"] = summary["onnx_available_rows"] / summary["onnx_rows"].where(summary["onnx_rows"] > 0, 1)
    return summary


def _build_learning_contract_summary(learning_observations: "pd.DataFrame") -> "pd.DataFrame":
    pd = _import_pandas()

    if learning_observations.empty:
        return pd.DataFrame()

    work = learning_observations.copy()
    if "pnl" in work.columns:
        work["pnl"] = pd.to_numeric(work["pnl"], errors="coerce")

    summary = (
        work.groupby(["symbol_alias", "advisory_match_key"], dropna=False)
        .agg(
            learning_rows=("symbol_alias", "size"),
            learning_pnl_mean=("pnl", "mean"),
            learning_pnl_sum=("pnl", "sum"),
            learning_positive_rows=("pnl", lambda s: int((s.fillna(0) > 0).sum())),
            learning_negative_rows=("pnl", lambda s: int((s.fillna(0) < 0).sum())),
        )
        .reset_index()
    )

    close_reason_primary = (
        work.loc[work["close_reason"].astype(str).str.len() > 0, ["symbol_alias", "advisory_match_key", "close_reason"]]
        .drop_duplicates()
        .groupby(["symbol_alias", "advisory_match_key"], dropna=False)
        .first()
        .reset_index()
        .rename(columns={"close_reason": "close_reason_primary"})
    )

    return summary.merge(close_reason_primary, how="left", on=["symbol_alias", "advisory_match_key"])


def _build_truth_chain(
    merged_truth: "pd.DataFrame",
    candidate_summary: "pd.DataFrame",
    onnx_summary: "pd.DataFrame",
    learning_summary: "pd.DataFrame",
) -> "pd.DataFrame":
    pd = _import_pandas()

    if merged_truth.empty:
        return pd.DataFrame()

    work = merged_truth.copy()
    work["candidate_ts"] = work.get("candidate_id", pd.Series(dtype=str)).apply(_extract_candidate_ts).astype("Int64")

    if not candidate_summary.empty:
        work = work.merge(
            candidate_summary,
            how="left",
            left_on=["symbol_alias", "candidate_ts"],
            right_on=["symbol_alias", "ts"],
            suffixes=("", "_candidate"),
        )
        if "ts" in work.columns:
            work = work.drop(columns=["ts"])

    if not onnx_summary.empty:
        work = work.merge(
            onnx_summary,
            how="left",
            left_on=["symbol_alias", "candidate_ts"],
            right_on=["symbol_alias", "ts"],
            suffixes=("", "_onnx"),
        )
        if "ts" in work.columns:
            work = work.drop(columns=["ts"])

    if not learning_summary.empty and "advisory_match_key_primary" in work.columns:
        work = work.merge(
            learning_summary,
            how="left",
            left_on=["symbol_alias", "advisory_match_key_primary"],
            right_on=["symbol_alias", "advisory_match_key"],
            suffixes=("", "_learning"),
        )
        if "advisory_match_key" in work.columns:
            work = work.drop(columns=["advisory_match_key"])

    work["candidate_contract_matched"] = work.get("candidate_rows_raw", pd.Series(dtype=float)).fillna(0) > 0
    work["onnx_contract_matched"] = work.get("onnx_rows", pd.Series(dtype=float)).fillna(0) > 0
    work["learning_contract_matched"] = work.get("learning_rows", pd.Series(dtype=float)).fillna(0) > 0
    return work


def _build_symbol_summary(
    pretrade: "pd.DataFrame",
    execution: "pd.DataFrame",
    merged: "pd.DataFrame",
    truth_chain: "pd.DataFrame",
) -> "pd.DataFrame":
    pd = _import_pandas()

    symbols = sorted(
        set(pretrade.get("symbol_alias", pd.Series(dtype=str)).dropna().astype(str).tolist())
        | set(execution.get("symbol_alias", pd.Series(dtype=str)).dropna().astype(str).tolist())
    )
    rows: list[dict[str, object]] = []
    for symbol in symbols:
        p = pretrade.loc[pretrade.get("symbol_alias") == symbol].copy() if not pretrade.empty else pd.DataFrame()
        e = execution.loc[execution.get("symbol_alias") == symbol].copy() if not execution.empty else pd.DataFrame()
        m = merged.loc[merged.get("symbol_alias") == symbol].copy() if not merged.empty else pd.DataFrame()
        chain = truth_chain.loc[truth_chain.get("symbol_alias") == symbol].copy() if not truth_chain.empty else pd.DataFrame()

        precheck_rows = int(len(p))
        precheck_ok_rows = int(p["check_function_ok"].sum()) if "check_function_ok" in p.columns else 0
        precheck_block_rows = precheck_rows - precheck_ok_rows
        execution_rows = int(len(e))
        deal_rows = int((e["deal_ticket"].fillna(0) > 0).sum()) if "deal_ticket" in e.columns else 0
        outcome_rows = int(e["net_observed"].notna().sum()) if "net_observed" in e.columns else 0
        positive_rows = int((e["net_observed"].fillna(0) > 0).sum()) if "net_observed" in e.columns else 0
        negative_rows = int((e["net_observed"].fillna(0) < 0).sum()) if "net_observed" in e.columns else 0
        merged_rows = int(len(m))
        candidate_contract_rows = int(chain["candidate_contract_matched"].fillna(False).sum()) if "candidate_contract_matched" in chain.columns else 0
        onnx_contract_rows = int(chain["onnx_contract_matched"].fillna(False).sum()) if "onnx_contract_matched" in chain.columns else 0
        learning_contract_rows = int(chain["learning_contract_matched"].fillna(False).sum()) if "learning_contract_matched" in chain.columns else 0

        rows.append(
            {
                "symbol_alias": symbol,
                "precheck_rows": precheck_rows,
                "precheck_ok_rows": precheck_ok_rows,
                "precheck_block_rows": precheck_block_rows,
                "precheck_block_rate": (precheck_block_rows / precheck_rows) if precheck_rows else 0.0,
                "execution_rows": execution_rows,
                "deal_rows": deal_rows,
                "fill_rate": (deal_rows / execution_rows) if execution_rows else 0.0,
                "outcome_rows": outcome_rows,
                "positive_rows": positive_rows,
                "negative_rows": negative_rows,
                "merged_rows": merged_rows,
                "candidate_contract_rows": candidate_contract_rows,
                "onnx_contract_rows": onnx_contract_rows,
                "learning_contract_rows": learning_contract_rows,
                "avg_spread_pretrade_points": float(p["spread_points"].dropna().mean()) if "spread_points" in p.columns and not p.empty else 0.0,
                "avg_spread_execution_points": float(e["spread_points"].dropna().mean()) if "spread_points" in e.columns and not e.empty else 0.0,
                "median_slippage_points": float(e["slippage_points"].dropna().median()) if "slippage_points" in e.columns and not e.empty else 0.0,
                "avg_net_observed": float(e["net_observed"].dropna().mean()) if "net_observed" in e.columns and not e.empty else 0.0,
                "sum_net_observed": float(e["net_observed"].dropna().sum()) if "net_observed" in e.columns and not e.empty else 0.0,
            }
        )
    return pd.DataFrame(rows)


def _write_dataframe(df: "pd.DataFrame", base_path: Path) -> dict[str, str]:
    ensure_dir(base_path.parent)
    outputs: dict[str, str] = {}
    csv_path = base_path.with_suffix(".csv")
    df.to_csv(csv_path, index=False, encoding="utf-8")
    outputs["csv"] = str(csv_path)
    try:
        parquet_path = base_path.with_suffix(".parquet")
        df.to_parquet(parquet_path, index=False)
        outputs["parquet"] = str(parquet_path)
    except Exception:
        pass
    return outputs


def _detect_runtime_scope(common_state_root: Path) -> str:
    name = common_state_root.name.upper()
    if name == "MAKRO_I_MIKRO_BOT":
        return "live"
    if name.startswith("MAKRO_I_MIKRO_BOT_TESTER_"):
        return "tester"
    return "custom"


def _write_outputs_for_scope(
    *,
    runtime_scope: str,
    pretrade: "pd.DataFrame",
    execution: "pd.DataFrame",
    merged: "pd.DataFrame",
    truth_chain: "pd.DataFrame",
    by_symbol: "pd.DataFrame",
    output_root: Path,
) -> dict[str, object]:
    scope_outputs = {
        "pretrade_truth_latest": _write_dataframe(pretrade, output_root / f"mt5_pretrade_truth_{runtime_scope}_latest"),
        "execution_truth_latest": _write_dataframe(execution, output_root / f"mt5_execution_truth_{runtime_scope}_latest"),
        "execution_truth_merged_latest": _write_dataframe(merged, output_root / f"mt5_execution_truth_merged_{runtime_scope}_latest"),
        "execution_truth_chain_latest": _write_dataframe(truth_chain, output_root / f"mt5_execution_truth_chain_{runtime_scope}_latest"),
        "execution_truth_by_symbol_latest": _write_dataframe(by_symbol, output_root / f"mt5_execution_truth_by_symbol_{runtime_scope}_latest"),
    }

    generic_outputs: dict[str, dict[str, str]] = {}
    if runtime_scope == "live":
        generic_outputs = {
            "pretrade_truth_latest": _write_dataframe(pretrade, output_root / "mt5_pretrade_truth_latest"),
            "execution_truth_latest": _write_dataframe(execution, output_root / "mt5_execution_truth_latest"),
            "execution_truth_merged_latest": _write_dataframe(merged, output_root / "mt5_execution_truth_merged_latest"),
            "execution_truth_chain_latest": _write_dataframe(truth_chain, output_root / "mt5_execution_truth_chain_latest"),
            "execution_truth_by_symbol_latest": _write_dataframe(by_symbol, output_root / "mt5_execution_truth_by_symbol_latest"),
        }

    return {
        "runtime_scope": runtime_scope,
        "scope_outputs": scope_outputs,
        "generic_outputs": generic_outputs,
    }


def build(project_root: Path, research_root: Path, common_state_root: Path | None, spool_root: Path | None) -> dict[str, object]:
    compat = CompatPaths.create(project_root=project_root, research_root=research_root, common_state_root=common_state_root)
    effective_spool_root = Path(spool_root) if spool_root is not None else compat.common_state_root / "spool"
    output_root = compat.contracts_dir / "mt5_truth"
    ensure_dir(output_root)
    runtime_scope = _detect_runtime_scope(compat.common_state_root)

    pretrade_folder = effective_spool_root / "pretrade_truth"
    execution_folder = effective_spool_root / "execution_truth"
    if not _folder_has_csvs(pretrade_folder) and not _folder_has_csvs(execution_folder):
        summary = {
            "schema_version": "1.0",
            "runtime_scope": runtime_scope,
            "project_root": str(project_root),
            "research_root": str(research_root),
            "common_state_root": str(compat.common_state_root),
            "spool_root": str(effective_spool_root),
            "output_root": str(output_root),
            "pretrade_rows": 0,
            "execution_rows": 0,
            "merged_rows": 0,
            "truth_chain_rows": 0,
            "candidate_contract_matched_rows": 0,
            "onnx_contract_matched_rows": 0,
            "learning_contract_matched_rows": 0,
            "symbols_count": 0,
            "symbols_seen": [],
            "outputs": {},
            "dormant_reason": "NO_TRUTH_SPOOL_FILES",
        }
        summary_path = output_root / f"mt5_execution_truth_summary_{runtime_scope}_latest.json"
        summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        if runtime_scope == "live":
            (output_root / "mt5_execution_truth_summary_latest.json").write_text(
                json.dumps(summary, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
        return summary

    pd = _import_pandas()
    pretrade = _normalize_pretrade(_safe_read_csvs(pretrade_folder))
    execution = _normalize_execution(_safe_read_csvs(execution_folder))
    merged = _merge_truth(pretrade, execution)
    contract_inputs = _load_contract_inputs(compat.contracts_dir)
    candidate_summary = _build_candidate_contract_summary(contract_inputs["candidate_signals"])
    onnx_summary = _build_onnx_contract_summary(contract_inputs["onnx_observations"])
    learning_summary = _build_learning_contract_summary(contract_inputs["learning_observations"])
    truth_chain = _build_truth_chain(merged, candidate_summary, onnx_summary, learning_summary)
    by_symbol = _build_symbol_summary(pretrade, execution, merged, truth_chain)

    outputs = _write_outputs_for_scope(
        runtime_scope=runtime_scope,
        pretrade=pretrade,
        execution=execution,
        merged=merged,
        truth_chain=truth_chain,
        by_symbol=by_symbol,
        output_root=output_root,
    )

    summary = {
        "schema_version": "1.0",
        "runtime_scope": runtime_scope,
        "project_root": str(project_root),
        "research_root": str(research_root),
        "common_state_root": str(compat.common_state_root),
        "spool_root": str(effective_spool_root),
        "output_root": str(output_root),
        "pretrade_rows": int(len(pretrade)),
        "execution_rows": int(len(execution)),
        "merged_rows": int(len(merged)),
        "truth_chain_rows": int(len(truth_chain)),
        "candidate_contract_matched_rows": int(truth_chain["candidate_contract_matched"].fillna(False).sum()) if not truth_chain.empty and "candidate_contract_matched" in truth_chain.columns else 0,
        "onnx_contract_matched_rows": int(truth_chain["onnx_contract_matched"].fillna(False).sum()) if not truth_chain.empty and "onnx_contract_matched" in truth_chain.columns else 0,
        "learning_contract_matched_rows": int(truth_chain["learning_contract_matched"].fillna(False).sum()) if not truth_chain.empty and "learning_contract_matched" in truth_chain.columns else 0,
        "symbols_count": int(len(by_symbol)),
        "symbols_seen": by_symbol.get("symbol_alias", pd.Series(dtype=str)).astype(str).tolist() if not by_symbol.empty else [],
        "outputs": outputs,
    }

    summary_path = output_root / f"mt5_execution_truth_summary_{runtime_scope}_latest.json"
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    if runtime_scope == "live":
        (output_root / "mt5_execution_truth_summary_latest.json").write_text(
            json.dumps(summary, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build MT5 pre-trade and execution truth artifacts.")
    parser.add_argument("--project-root", type=Path, default=Path(r"C:\MAKRO_I_MIKRO_BOT"))
    parser.add_argument("--research-root", type=Path, default=Path(r"C:\TRADING_DATA\RESEARCH"))
    parser.add_argument("--common-state-root", type=Path, default=None)
    parser.add_argument("--spool-root", type=Path, default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    summary = build(
        project_root=args.project_root,
        research_root=args.research_root,
        common_state_root=args.common_state_root,
        spool_root=args.spool_root,
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
