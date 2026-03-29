from __future__ import annotations

import argparse
import json
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
    out = df.copy()
    for col in cols:
        if col in out.columns:
            out[col] = pd.to_datetime(out[col], errors="coerce", utc=True)
    return out


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


def _build_symbol_summary(
    pretrade: "pd.DataFrame",
    execution: "pd.DataFrame",
    merged: "pd.DataFrame",
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

        precheck_rows = int(len(p))
        precheck_ok_rows = int(p["check_function_ok"].sum()) if "check_function_ok" in p.columns else 0
        precheck_block_rows = precheck_rows - precheck_ok_rows
        execution_rows = int(len(e))
        deal_rows = int((e["deal_ticket"].fillna(0) > 0).sum()) if "deal_ticket" in e.columns else 0
        outcome_rows = int(e["net_observed"].notna().sum()) if "net_observed" in e.columns else 0
        positive_rows = int((e["net_observed"].fillna(0) > 0).sum()) if "net_observed" in e.columns else 0
        negative_rows = int((e["net_observed"].fillna(0) < 0).sum()) if "net_observed" in e.columns else 0
        merged_rows = int(len(m))

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


def build(project_root: Path, research_root: Path, common_state_root: Path | None, spool_root: Path | None) -> dict[str, object]:
    compat = CompatPaths.create(project_root=project_root, research_root=research_root, common_state_root=common_state_root)
    effective_spool_root = Path(spool_root) if spool_root is not None else compat.common_state_root / "spool"
    output_root = compat.contracts_dir / "mt5_truth"
    ensure_dir(output_root)

    pretrade_folder = effective_spool_root / "pretrade_truth"
    execution_folder = effective_spool_root / "execution_truth"
    if not _folder_has_csvs(pretrade_folder) and not _folder_has_csvs(execution_folder):
        summary = {
            "schema_version": "1.0",
            "project_root": str(project_root),
            "research_root": str(research_root),
            "common_state_root": str(compat.common_state_root),
            "spool_root": str(effective_spool_root),
            "output_root": str(output_root),
            "pretrade_rows": 0,
            "execution_rows": 0,
            "merged_rows": 0,
            "symbols_count": 0,
            "symbols_seen": [],
            "outputs": {},
            "dormant_reason": "NO_TRUTH_SPOOL_FILES",
        }
        summary_path = output_root / "mt5_execution_truth_summary_latest.json"
        summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        return summary

    pd = _import_pandas()
    pretrade = _normalize_pretrade(_safe_read_csvs(pretrade_folder))
    execution = _normalize_execution(_safe_read_csvs(execution_folder))
    merged = _merge_truth(pretrade, execution)
    by_symbol = _build_symbol_summary(pretrade, execution, merged)

    outputs = {
        "pretrade_truth_latest": _write_dataframe(pretrade, output_root / "mt5_pretrade_truth_latest"),
        "execution_truth_latest": _write_dataframe(execution, output_root / "mt5_execution_truth_latest"),
        "execution_truth_merged_latest": _write_dataframe(merged, output_root / "mt5_execution_truth_merged_latest"),
        "execution_truth_by_symbol_latest": _write_dataframe(by_symbol, output_root / "mt5_execution_truth_by_symbol_latest"),
    }

    summary = {
        "schema_version": "1.0",
        "project_root": str(project_root),
        "research_root": str(research_root),
        "common_state_root": str(compat.common_state_root),
        "spool_root": str(effective_spool_root),
        "output_root": str(output_root),
        "pretrade_rows": int(len(pretrade)),
        "execution_rows": int(len(execution)),
        "merged_rows": int(len(merged)),
        "symbols_count": int(len(by_symbol)),
        "symbols_seen": by_symbol.get("symbol_alias", pd.Series(dtype=str)).astype(str).tolist() if not by_symbol.empty else [],
        "outputs": outputs,
    }

    summary_path = output_root / "mt5_execution_truth_summary_latest.json"
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
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
