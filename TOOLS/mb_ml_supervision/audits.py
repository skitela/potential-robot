from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any
import importlib.util
import json

from .io_utils import (
    dump_json,
    file_age_hours,
    file_modified_iso,
    parquet_count,
    parquet_query_rows,
    parquet_symbol_counts,
    read_json,
    recursive_collect_symbols,
    try_import_lightgbm,
    utc_now_iso,
)
from .paths import OverlayPaths


@dataclass(frozen=True)
class AuditThresholds:
    tail_freshness_hours: float = 12.0
    ledger_freshness_hours: float = 12.0
    package_freshness_hours: float = 24.0
    min_labeled_rows_for_rollout: int = 100
    min_outcome_rows_for_shadow_ready: int = 50
    natural_drop_ratio_floor: float = 0.85


def load_active_registry_symbols(paths: OverlayPaths) -> list[dict[str, Any]]:
    payload = read_json(paths.microbots_registry_path, default={"symbols": []})
    symbols = payload.get("symbols", []) if isinstance(payload, dict) else []
    out: list[dict[str, Any]] = []
    for item in symbols:
        if not isinstance(item, dict):
            continue
        symbol = str(item.get("symbol") or item.get("code_symbol") or "").strip()
        if not symbol:
            continue
        out.append(
            {
                "symbol": symbol,
                "code_symbol": str(item.get("code_symbol") or symbol),
                "expert": str(item.get("expert") or f"MicroBot_{symbol}"),
                "preset": str(item.get("preset") or ""),
                "session_profile": str(item.get("session_profile") or ""),
                "broker_symbol": str(item.get("broker_symbol") or ""),
            }
        )
    return out


def determine_symbol_modes(
    active_symbols: list[str],
    candidate_counts: dict[str, int],
    outcome_counts: dict[str, int],
    runtime_counts: dict[str, int],
    thresholds: AuditThresholds,
) -> dict[str, str]:
    modes: dict[str, str] = {}
    for symbol in active_symbols:
        cand = int(candidate_counts.get(symbol, 0))
        outc = int(outcome_counts.get(symbol, 0))
        runtime = int(runtime_counts.get(symbol, 0))
        if cand <= 0:
            modes[symbol] = "FALLBACK_ONLY"
        elif outc >= thresholds.min_outcome_rows_for_shadow_ready:
            modes[symbol] = "TRAINING_SHADOW_READY"
        elif runtime > 0 or cand > 0:
            modes[symbol] = "LOCAL_TRAINING_LIMITED"
        else:
            modes[symbol] = "FALLBACK_ONLY"
    return modes


def inspect_tail_bridge(paths: OverlayPaths, thresholds: AuditThresholds) -> dict[str, Any]:
    exists = paths.tail_bridge_path.exists()
    rows = parquet_count(paths.tail_bridge_path) if exists else 0
    age_hours = file_age_hours(paths.tail_bridge_path)
    missing_tail_count = 0
    missing_candidate_count = 0
    bad_states: list[str] = []
    candidate_gap_states: list[str] = []
    if exists:
        schema_rows = parquet_query_rows(
            paths.tail_bridge_path,
            "describe select * from read_parquet(?)",
            [str(paths.tail_bridge_path)],
        )
        columns = {str(row.get("column_name") or "") for row in schema_rows}
        state_column = ""
        if "tail_state" in columns:
            state_column = "tail_state"
        elif "state" in columns:
            state_column = "state"

        if state_column:
            result = parquet_query_rows(
                paths.tail_bridge_path,
                f"""
                select
                  coalesce(sum(case when upper(cast({state_column} as varchar)) not in ('OK', 'BRAK_KANDYDATOW') then 1 else 0 end), 0) as bad_rows,
                  coalesce(sum(case when upper(cast({state_column} as varchar)) = 'BRAK_KANDYDATOW' then 1 else 0 end), 0) as candidate_gap_rows,
                  string_agg(distinct cast({state_column} as varchar), ',') as states,
                  string_agg(distinct case when upper(cast({state_column} as varchar)) = 'BRAK_KANDYDATOW' then cast({state_column} as varchar) else null end, ',') as candidate_states
                from read_parquet(?)
                """,
                [str(paths.tail_bridge_path)],
            )
            if result:
                missing_tail_count = int(result[0].get("bad_rows") or 0)
                missing_candidate_count = int(result[0].get("candidate_gap_rows") or 0)
                states_str = str(result[0].get("states") or "")
                bad_states = [item for item in states_str.split(",") if item and item not in {"OK", "BRAK_KANDYDATOW"}]
                candidate_states_str = str(result[0].get("candidate_states") or "")
                candidate_gap_states = [item for item in candidate_states_str.split(",") if item]
        else:
            missing_tail_count = rows if rows > 0 else 0
            bad_states = ["BRAK_KOLUMNY_TAIL_STATE"]
    return {
        "path": str(paths.tail_bridge_path),
        "exists": exists,
        "rows": rows,
        "age_hours": age_hours,
        "modified_at_utc": file_modified_iso(paths.tail_bridge_path),
        "missing_tail_count": missing_tail_count,
        "missing_candidate_count": missing_candidate_count,
        "bad_states": bad_states,
        "candidate_gap_states": candidate_gap_states,
        "ok": bool(exists and rows > 0 and missing_tail_count == 0 and (age_hours is None or age_hours <= thresholds.tail_freshness_hours)),
    }


def inspect_broker_net_ledger(paths: OverlayPaths, thresholds: AuditThresholds) -> dict[str, Any]:
    exists = paths.broker_net_ledger_path.exists()
    rows = 0
    labeled_rows = 0
    sample_symbols: list[str] = []
    active_registry = load_active_registry_symbols(paths)
    active_symbols = sorted({str(item.get("symbol") or "").strip() for item in active_registry if str(item.get("symbol") or "").strip()})
    age_hours = file_age_hours(paths.broker_net_ledger_path)
    read_mode = "missing"
    read_error = None
    if exists:
        try:
            result = parquet_query_rows(
                paths.broker_net_ledger_path,
                """
                select
                  count(*) as rows,
                  coalesce(sum(case when net_pln is not null then 1 else 0 end), 0) as labeled_rows,
                  string_agg(distinct cast(symbol_alias as varchar), ',') as symbols
                from read_parquet(?)
                """,
                [str(paths.broker_net_ledger_path)],
            )
            if result:
                rows = int(result[0].get("rows") or 0)
                labeled_rows = int(result[0].get("labeled_rows") or 0)
                sample_symbols = [item for item in str(result[0].get("symbols") or "").split(",") if item]
            read_mode = "duckdb"
        except Exception as exc:
            read_error = str(exc)
            try:
                import pandas as pd  # type: ignore

                frame = pd.read_parquet(paths.broker_net_ledger_path, columns=["symbol_alias", "net_pln"])
                rows = int(len(frame))
                labeled_rows = int(frame["net_pln"].notna().sum()) if "net_pln" in frame.columns else 0
                if "symbol_alias" in frame.columns:
                    sample_symbols = sorted(frame["symbol_alias"].dropna().astype(str).unique().tolist())
                read_mode = "pandas_fallback"
            except Exception as fallback_exc:
                read_mode = "error"
                read_error = f"{read_error}; fallback={fallback_exc}"
    previous_audit = read_json(paths.overlay_audit_path, default={})
    previous_labeled_rows = None
    natural_drop_flag = False
    if isinstance(previous_audit, dict):
        previous_labeled_rows = (
            previous_audit.get("broker_net_ledger", {}) or {}
        ).get("labeled_rows")
        try:
            previous_labeled_rows = int(previous_labeled_rows) if previous_labeled_rows is not None else None
        except Exception:
            previous_labeled_rows = None
    if previous_labeled_rows and previous_labeled_rows > 0:
        natural_drop_flag = labeled_rows < int(previous_labeled_rows * thresholds.natural_drop_ratio_floor)
    return {
        "path": str(paths.broker_net_ledger_path),
        "exists": exists,
        "rows": rows,
        "labeled_rows": labeled_rows,
        "previous_labeled_rows": previous_labeled_rows,
        "natural_drop_flag": natural_drop_flag,
        "age_hours": age_hours,
        "modified_at_utc": file_modified_iso(paths.broker_net_ledger_path),
        "read_mode": read_mode,
        "read_error": read_error,
        "expected_symbols": active_symbols,
        "symbols_present": sorted(sample_symbols),
        "symbols_without_rows": sorted(set(active_symbols) - set(sample_symbols)),
        "coverage_ratio": (float(len(set(sample_symbols)) / len(active_symbols)) if active_symbols else 1.0),
        "ok": bool(
            exists
            and rows > 0
            and labeled_rows >= thresholds.min_labeled_rows_for_rollout
            and not natural_drop_flag
            and (age_hours is None or age_hours <= thresholds.ledger_freshness_hours)
        ),
    }


def build_outcome_closure_audit(paths: OverlayPaths) -> dict[str, Any]:
    active_registry = load_active_registry_symbols(paths)
    active_symbols = [item["symbol"] for item in active_registry]

    candidate_counts = parquet_symbol_counts(paths.candidate_contract_path)
    runtime_counts = parquet_symbol_counts(paths.onnx_observations_contract_path)
    learning_counts = parquet_symbol_counts(paths.learning_contract_path)

    ledger_rows: list[dict[str, Any]] = []
    if paths.broker_net_ledger_path.exists():
        ledger_rows = parquet_query_rows(
            paths.broker_net_ledger_path,
            """
            select
              cast(symbol_alias as varchar) as symbol_alias,
              count(*) as ledger_rows,
              coalesce(sum(case when outcome_known = 1 then 1 else 0 end), 0) as labeled_rows,
              coalesce(sum(case when spread_cost_pln is not null then 1 else 0 end), 0) as spread_rows,
              coalesce(sum(case when slippage_cost_pln is not null then 1 else 0 end), 0) as slippage_rows,
              coalesce(sum(case when commission_pln is not null then 1 else 0 end), 0) as commission_rows,
              coalesce(sum(case when swap_pln is not null then 1 else 0 end), 0) as swap_rows,
              coalesce(sum(case when net_pln is not null then 1 else 0 end), 0) as net_rows
            from read_parquet(?)
            group by 1
            order by 1
            """,
            [str(paths.broker_net_ledger_path)],
        )
    ledger_by_symbol: dict[str, dict[str, int]] = {}
    for row in ledger_rows:
        symbol = str(row.get("symbol_alias") or "").strip()
        if not symbol:
            continue
        ledger_by_symbol[symbol] = {
            "ledger_rows": _coerce_int(row.get("ledger_rows")),
            "labeled_rows": _coerce_int(row.get("labeled_rows")),
            "spread_rows": _coerce_int(row.get("spread_rows")),
            "slippage_rows": _coerce_int(row.get("slippage_rows")),
            "commission_rows": _coerce_int(row.get("commission_rows")),
            "swap_rows": _coerce_int(row.get("swap_rows")),
            "net_rows": _coerce_int(row.get("net_rows")),
        }

    paper_trading_text = paths.paper_trading_path.read_text(encoding="utf-8", errors="ignore") if paths.paper_trading_path.exists() else ""
    execution_precheck_text = paths.execution_precheck_path.read_text(encoding="utf-8", errors="ignore") if paths.execution_precheck_path.exists() else ""

    paper_tracks_spread = "opened_spread_points" in paper_trading_text
    paper_tracks_commission = "commission" in paper_trading_text
    paper_tracks_swap = "swap" in paper_trading_text
    paper_tracks_broker_net_pnl = any(token in paper_trading_text for token in ("netto", "net_pnl", "account_currency"))
    precheck_models_slippage = "modeled_slippage_points" in execution_precheck_text
    precheck_models_commission = "modeled_commission_points" in execution_precheck_text

    items: list[dict[str, Any]] = []
    state_counts: dict[str, int] = {}
    reason_counts: dict[str, int] = {}
    for registry_row in active_registry:
        symbol = registry_row["symbol"]
        candidate_rows = int(candidate_counts.get(symbol, 0))
        runtime_rows = int(runtime_counts.get(symbol, 0))
        learning_rows = int(learning_counts.get(symbol, 0))
        ledger_row = ledger_by_symbol.get(symbol, {})
        ledger_total_rows = int(ledger_row.get("ledger_rows", 0))
        labeled_rows = int(ledger_row.get("labeled_rows", 0))
        spread_rows = int(ledger_row.get("spread_rows", 0))
        slippage_rows = int(ledger_row.get("slippage_rows", 0))
        commission_rows = int(ledger_row.get("commission_rows", 0))
        swap_rows = int(ledger_row.get("swap_rows", 0))
        net_rows = int(ledger_row.get("net_rows", 0))
        ledger_full_costs = (
            labeled_rows > 0
            and spread_rows >= labeled_rows
            and slippage_rows >= labeled_rows
            and commission_rows >= labeled_rows
            and swap_rows >= labeled_rows
            and net_rows >= labeled_rows
        )

        reasons: list[str] = []
        if candidate_rows <= 0:
            reasons.append("NO_CANDIDATES")
        if candidate_rows > 0 and labeled_rows <= 0:
            reasons.append("NO_OUTCOME_ROWS")
        if runtime_rows > 0 and labeled_rows <= 0:
            reasons.append("RUNTIME_WITHOUT_OUTCOME")
        if labeled_rows > 0 and not ledger_full_costs:
            reasons.append("PARTIAL_LEDGER_COSTS")
        if not paper_tracks_commission:
            reasons.append("PAPER_RUNTIME_NO_COMMISSION")
        if not paper_tracks_swap:
            reasons.append("PAPER_RUNTIME_NO_SWAP")
        if not paper_tracks_broker_net_pnl:
            reasons.append("PAPER_RUNTIME_NO_BROKER_NET")

        if candidate_rows <= 0:
            closure_state = "NO_CANDIDATES"
        elif labeled_rows <= 0:
            closure_state = "OUTCOME_GAP"
        elif ledger_full_costs and paper_tracks_commission and paper_tracks_swap and paper_tracks_broker_net_pnl:
            closure_state = "FULL_BROKER_NET_READY"
        elif ledger_full_costs:
            closure_state = "OUTCOME_READY_PENDING_PAPER_TRUTH"
        else:
            closure_state = "PARTIAL_LEDGER_ONLY"

        items.append(
            {
                "symbol_alias": symbol,
                "broker_symbol": registry_row.get("broker_symbol", ""),
                "session_profile": registry_row.get("session_profile", ""),
                "candidate_rows": candidate_rows,
                "runtime_rows": runtime_rows,
                "learning_rows": learning_rows,
                "ledger_rows": ledger_total_rows,
                "labeled_rows": labeled_rows,
                "spread_rows": spread_rows,
                "slippage_rows": slippage_rows,
                "commission_rows": commission_rows,
                "swap_rows": swap_rows,
                "net_rows": net_rows,
                "ledger_full_costs": ledger_full_costs,
                "closure_state": closure_state,
                "closure_reasons": reasons,
            }
        )
        state_counts[closure_state] = state_counts.get(closure_state, 0) + 1
        for reason in reasons:
            reason_counts[reason] = reason_counts.get(reason, 0) + 1

    items.sort(key=lambda row: (row["closure_state"], row["symbol_alias"]))
    symbols_with_outcome = sum(1 for row in items if row["labeled_rows"] > 0)
    symbols_with_full_ledger_costs = sum(1 for row in items if row["ledger_full_costs"])
    broker_net_pln_ready = bool(
        paper_tracks_commission
        and paper_tracks_swap
        and paper_tracks_broker_net_pnl
        and symbols_with_outcome > 0
        and symbols_with_full_ledger_costs == symbols_with_outcome
    )

    return {
        "schema_version": "1.0",
        "generated_at_utc": utc_now_iso(),
        "active_fleet": {
            "count": len(active_symbols),
            "symbols": active_symbols,
        },
        "summary": {
            "total_symbols": len(active_symbols),
            "candidate_symbols_count": sum(1 for symbol in active_symbols if candidate_counts.get(symbol, 0) > 0),
            "runtime_symbols_count": sum(1 for symbol in active_symbols if runtime_counts.get(symbol, 0) > 0),
            "learning_symbols_count": sum(1 for symbol in active_symbols if learning_counts.get(symbol, 0) > 0),
            "symbols_with_ledger_rows_count": sum(1 for row in items if row["ledger_rows"] > 0),
            "symbols_with_outcome_count": symbols_with_outcome,
            "symbols_without_outcome_count": sum(1 for row in items if row["candidate_rows"] > 0 and row["labeled_rows"] <= 0),
            "symbols_with_full_ledger_costs_count": symbols_with_full_ledger_costs,
            "outcome_gap_count": state_counts.get("OUTCOME_GAP", 0),
            "pending_paper_truth_count": state_counts.get("OUTCOME_READY_PENDING_PAPER_TRUTH", 0),
            "partial_ledger_only_count": state_counts.get("PARTIAL_LEDGER_ONLY", 0),
            "paper_tracks_spread": paper_tracks_spread,
            "paper_tracks_commission": paper_tracks_commission,
            "paper_tracks_swap": paper_tracks_swap,
            "paper_tracks_broker_net_pnl": paper_tracks_broker_net_pnl,
            "precheck_models_slippage": precheck_models_slippage,
            "precheck_models_commission": precheck_models_commission,
            "broker_net_pln_ready": broker_net_pln_ready,
            "closure_state_counts": state_counts,
            "reason_counts": reason_counts,
        },
        "items": items,
    }


def write_outcome_closure_audit(paths: OverlayPaths) -> dict[str, Any]:
    payload = build_outcome_closure_audit(paths)
    dump_json(paths.outcome_closure_audit_path, payload)
    return payload


def _collect_package_symbols(paths: OverlayPaths) -> set[str]:
    package_payload = read_json(paths.package_json_path, default=None)
    symbols: set[str] = set()
    if package_payload is not None:
        symbols.update(recursive_collect_symbols(package_payload))
    if not symbols and paths.symbol_models_dir.exists():
        for child in paths.symbol_models_dir.iterdir():
            if child.is_dir():
                symbols.add(child.name)
    return symbols


def _find_symbol_registry(paths: OverlayPaths) -> Path | None:
    for candidate in paths.onnx_symbol_registry_candidates:
        if candidate.exists():
            return candidate
    return None


def inspect_package(paths: OverlayPaths, thresholds: AuditThresholds) -> dict[str, Any]:
    symbols = _collect_package_symbols(paths)
    package_exists = paths.package_json_path.exists()
    package_age = file_age_hours(paths.package_json_path)
    registry_path = _find_symbol_registry(paths)
    registry_payload = read_json(registry_path, default=None) if registry_path else None
    global_joblib = paths.global_model_joblib_path.exists()
    global_onnx = paths.global_model_onnx_path.exists()
    metrics_exists = paths.global_metrics_path.exists()
    preview_only = package_exists and len(symbols) == 0
    registry_symbols = sorted(recursive_collect_symbols(registry_payload)) if registry_payload is not None else []
    return {
        "path": str(paths.package_json_path),
        "exists": package_exists,
        "modified_at_utc": file_modified_iso(paths.package_json_path),
        "age_hours": package_age,
        "symbols_in_package": sorted(symbols),
        "symbols_count": len(symbols),
        "preview_only": preview_only,
        "global_model_joblib_exists": global_joblib,
        "global_model_onnx_exists": global_onnx,
        "global_metrics_exists": metrics_exists,
        "onnx_symbol_registry_path": str(registry_path) if registry_path else None,
        "onnx_symbol_registry_symbols": registry_symbols,
        "ok": bool(
            package_exists
            and not preview_only
            and global_onnx
            and (package_age is None or package_age <= thresholds.package_freshness_hours)
        ),
    }


def inspect_symbol_models(
    paths: OverlayPaths,
    active_symbols: list[str],
    symbol_modes: dict[str, str],
) -> dict[str, Any]:
    symbols: dict[str, Any] = {}
    missing_models: list[str] = []
    for symbol in active_symbols:
        model_dir = paths.symbol_models_dir / symbol
        onnx_files = sorted(str(path.name) for path in model_dir.glob("*.onnx")) if model_dir.exists() else []
        joblib_files = sorted(str(path.name) for path in model_dir.glob("*.joblib")) if model_dir.exists() else []
        metrics_files = sorted(str(path.name) for path in model_dir.glob("*metrics*.json")) if model_dir.exists() else []
        state = {
            "model_dir": str(model_dir),
            "exists": model_dir.exists(),
            "onnx_files": onnx_files,
            "joblib_files": joblib_files,
            "metrics_files": metrics_files,
            "local_training_mode": symbol_modes.get(symbol, "FALLBACK_ONLY"),
            "model_present": bool(onnx_files or joblib_files),
        }
        if state["local_training_mode"] == "TRAINING_SHADOW_READY" and not state["model_present"]:
            missing_models.append(symbol)
        symbols[symbol] = state
    return {
        "expected_symbols": active_symbols,
        "missing_required_models": missing_models,
        "symbols": symbols,
        "ok": len(missing_models) == 0,
    }


def _load_items_by_symbol(
    path: Path,
    symbol_keys: tuple[str, ...] = ("symbol_alias", "symbol", "code_symbol"),
) -> dict[str, dict[str, Any]]:
    payload = read_json(path, default={})
    if not isinstance(payload, dict):
        return {}
    items = payload.get("items", [])
    if not isinstance(items, list):
        return {}
    by_symbol: dict[str, dict[str, Any]] = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        symbol = ""
        for key in symbol_keys:
            value = str(item.get(key) or "").strip()
            if value:
                symbol = value
                break
        if not symbol:
            continue
        by_symbol[symbol] = item
    return by_symbol


def _get_nested_dict(payload: dict[str, Any], key: str) -> dict[str, Any]:
    value = payload.get(key)
    return value if isinstance(value, dict) else {}


def _coerce_int(*values: Any) -> int:
    for value in values:
        if value is None or value == "":
            continue
        try:
            return int(value)
        except Exception:
            continue
    return 0


def _coerce_bool(value: Any, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    text = str(value).strip().lower()
    if not text:
        return default
    if text in {"1", "true", "yes", "y", "tak"}:
        return True
    if text in {"0", "false", "no", "n", "nie"}:
        return False
    return default


def _extract_promotion(payload: dict[str, Any]) -> dict[str, Any]:
    promotion = payload.get("promotion")
    if not isinstance(promotion, dict):
        return {"approved": False, "reasons": []}
    reasons = promotion.get("reasons", [])
    if not isinstance(reasons, list):
        reasons = [str(reasons)] if reasons else []
    return {
        "approved": _coerce_bool(promotion.get("approved"), default=False),
        "reasons": [str(item).strip() for item in reasons if str(item).strip()],
    }


def _build_symbol_model_state(model_dir: Path) -> dict[str, Any]:
    metrics_path = model_dir / "paper_gate_acceptor_latest_metrics.json"
    report_path = model_dir / "paper_gate_acceptor_report_latest.md"
    metrics_payload = read_json(metrics_path, default={}) if metrics_path.exists() else {}
    if not isinstance(metrics_payload, dict):
        metrics_payload = {}
    artifacts_payload = metrics_payload.get("artifacts")
    if not isinstance(artifacts_payload, dict):
        artifacts_payload = {}

    onnx_files = sorted(model_dir.glob("*.onnx")) if model_dir.exists() else []
    joblib_files = sorted(model_dir.glob("*.joblib")) if model_dir.exists() else []
    student_model_path = str(artifacts_payload.get("student_model_path") or "").strip()
    edge_model_path = str(artifacts_payload.get("edge_model_path") or "").strip()
    fill_model_path = str(artifacts_payload.get("fill_model_path") or "").strip()
    slippage_model_path = str(artifacts_payload.get("slippage_model_path") or "").strip()

    resolved_onnx = student_model_path or (str(onnx_files[0]) if onnx_files else "")
    resolved_joblib = str(joblib_files[0]) if joblib_files else ""
    promotion = _extract_promotion(metrics_payload)
    return {
        "model_dir": str(model_dir),
        "model_dir_exists": model_dir.exists(),
        "metrics_path": str(metrics_path) if metrics_path.exists() else "",
        "report_path": str(report_path) if report_path.exists() else "",
        "metrics_payload": metrics_payload,
        "promotion": promotion,
        "candidate_rows": _coerce_int(metrics_payload.get("candidate_rows")),
        "labeled_rows": _coerce_int(metrics_payload.get("labeled_rows")),
        "runtime_rows": _coerce_int(metrics_payload.get("runtime_rows")),
        "outcome_rows": _coerce_int(metrics_payload.get("outcome_rows")),
        "training_mode": str(metrics_payload.get("training_mode") or "").strip(),
        "onnx_path": resolved_onnx,
        "joblib_path": resolved_joblib,
        "edge_model_path": edge_model_path,
        "fill_model_path": fill_model_path,
        "slippage_model_path": slippage_model_path,
        "student_model_available": bool(resolved_onnx or resolved_joblib),
        "aux_model_count": sum(1 for value in [edge_model_path, fill_model_path, slippage_model_path] if value),
    }


def _collect_package_symbols_filtered(paths: OverlayPaths, active_symbols: set[str]) -> set[str]:
    payload = read_json(paths.package_json_path, default={})
    if not isinstance(payload, dict):
        return set()
    return {symbol for symbol in recursive_collect_symbols(payload) if symbol in active_symbols}


def _collect_runtime_registry_symbols(
    paths: OverlayPaths,
    active_symbols: set[str],
) -> dict[str, dict[str, Any]]:
    payload = read_json(paths.sync_runtime_registry_path, default={})
    if not isinstance(payload, dict):
        return {}
    symbols_payload = payload.get("symbols")
    if not isinstance(symbols_payload, dict):
        return {}
    rows: dict[str, dict[str, Any]] = {}
    for symbol, row in symbols_payload.items():
        symbol_name = str(symbol).strip()
        if not symbol_name or symbol_name not in active_symbols or not isinstance(row, dict):
            continue
        rows[symbol_name] = row
    return rows


def _collect_symbol_registry_rows(
    paths: OverlayPaths,
    active_symbols: set[str],
) -> dict[str, dict[str, Any]]:
    registry_path = _find_symbol_registry(paths)
    payload = read_json(registry_path, default={}) if registry_path else {}
    if not isinstance(payload, dict):
        return {}
    symbols_payload = payload.get("symbols")
    if not isinstance(symbols_payload, dict):
        return {}
    rows: dict[str, dict[str, Any]] = {}
    for symbol, row in symbols_payload.items():
        symbol_name = str(symbol).strip()
        if not symbol_name or symbol_name not in active_symbols or not isinstance(row, dict):
            continue
        rows[symbol_name] = row
    return rows


def _derive_local_runtime_state(
    package_present: bool,
    runtime_contract_present: bool,
    local_model_available: bool,
    promotion_approved: bool,
    forced_fallback: bool,
) -> str:
    if local_model_available and package_present and runtime_contract_present and promotion_approved and not forced_fallback:
        return "LOCAL_RUNTIME_READY"
    if package_present or runtime_contract_present:
        return "PACKAGE_PRESENT_BUT_DISABLED"
    return "GLOBAL_ONLY"


def _build_readiness_reasons(
    candidate_rows: int,
    outcome_rows: int,
    broker_net_ready: bool,
    package_present: bool,
    runtime_contract_present: bool,
    local_model_available: bool,
    registry_present: bool,
    rollback_detected: bool,
    guardrail_state: str,
    promotion_reasons: list[str],
) -> list[str]:
    reasons: list[str] = []
    if candidate_rows <= 0:
        reasons.append("NO_CANDIDATES")
    if outcome_rows <= 0:
        reasons.append("NO_OUTCOME")
    if not broker_net_ready:
        reasons.append("COST_TRUTH_GAP")
    if rollback_detected or guardrail_state.upper() == "FORCED_GLOBAL_FALLBACK":
        reasons.append("RECENT_ROLLBACK")
    if (not package_present) or (package_present and not runtime_contract_present) or (package_present and not local_model_available) or not registry_present:
        reasons.append("PACKAGE_RUNTIME_MISMATCH")

    reasons_text = " ".join(promotion_reasons).lower()
    if any(token in reasons_text for token in ("global", "nauczyciel", "teacher", "beat", "przebija", "stronger than local")):
        reasons.append("NOT_BEATING_GLOBAL")

    deduped: list[str] = []
    for reason in reasons:
        if reason not in deduped:
            deduped.append(reason)
    return deduped


def build_local_model_readiness_audit(paths: OverlayPaths) -> dict[str, Any]:
    active_registry = load_active_registry_symbols(paths)
    active_symbols = [item["symbol"] for item in active_registry]
    active_symbol_set = set(active_symbols)

    training_items = _load_items_by_symbol(paths.instrument_training_readiness_path)
    learning_health_items = _load_items_by_symbol(paths.learning_health_registry_path)
    local_audit_items = _load_items_by_symbol(paths.instrument_local_training_audit_path)
    guardrail_items = _load_items_by_symbol(paths.instrument_local_training_guardrails_path)
    package_symbols = _collect_package_symbols_filtered(paths, active_symbol_set)
    runtime_registry_symbols = _collect_runtime_registry_symbols(paths, active_symbol_set)
    symbol_registry_rows = _collect_symbol_registry_rows(paths, active_symbol_set)

    outcome_closure_payload = read_json(paths.outcome_closure_audit_path, default={})
    outcome_closure_summary = _get_nested_dict(
        outcome_closure_payload if isinstance(outcome_closure_payload, dict) else {},
        "summary",
    )
    ml_scalping_audit = read_json(paths.ml_scalping_fit_audit_path, default={})
    ml_scalping_summary = _get_nested_dict(ml_scalping_audit if isinstance(ml_scalping_audit, dict) else {}, "summary")
    broker_net_ready = _coerce_bool(
        outcome_closure_summary.get("broker_net_pln_ready"),
        default=(
            _coerce_bool(ml_scalping_summary.get("broker_net_pln_ready"), default=False)
            and _coerce_bool(ml_scalping_summary.get("paper_tracks_commission"), default=False)
            and _coerce_bool(ml_scalping_summary.get("paper_tracks_swap"), default=False)
        ),
    )

    lane_payload = read_json(paths.instrument_local_training_lane_path, default={})
    lane_start_group = []
    if isinstance(lane_payload, dict):
        raw_group = lane_payload.get("start_group")
        if isinstance(raw_group, list):
            lane_start_group = [
                str(item.get("symbol_alias") or "").strip()
                for item in raw_group
                if isinstance(item, dict) and str(item.get("symbol_alias") or "").strip()
            ]
    plan_payload = read_json(paths.instrument_local_training_plan_path, default={})
    plan_start_group = []
    if isinstance(plan_payload, dict):
        raw_group = plan_payload.get("start_group")
        if isinstance(raw_group, list):
            plan_start_group = [
                str(item.get("symbol_alias") or "").strip()
                for item in raw_group
                if isinstance(item, dict) and str(item.get("symbol_alias") or "").strip()
            ]

    stale_symbol_model_dirs = []
    if paths.symbol_models_dir.exists():
        stale_symbol_model_dirs = sorted(
            child.name
            for child in paths.symbol_models_dir.iterdir()
            if child.is_dir() and child.name not in active_symbol_set
        )

    stale_registry_symbols = sorted(
        symbol
        for symbol in recursive_collect_symbols(read_json(_find_symbol_registry(paths) or Path(), default={}))
        if symbol not in active_symbol_set
    )

    items: list[dict[str, Any]] = []
    reason_counts: dict[str, int] = {}
    training_state_counts: dict[str, int] = {}
    runtime_state_counts: dict[str, int] = {}

    for registry_row in active_registry:
        symbol = registry_row["symbol"]
        training_row = training_items.get(symbol, {})
        health_row = learning_health_items.get(symbol, {})
        local_audit_row = local_audit_items.get(symbol, {})
        guardrail_row = guardrail_items.get(symbol, {})
        runtime_row = runtime_registry_symbols.get(symbol, {})
        symbol_registry_row = symbol_registry_rows.get(symbol, {})
        model_state = _build_symbol_model_state(paths.symbol_models_dir / symbol)

        candidate_rows = _coerce_int(
            training_row.get("candidate_contract_rows"),
            model_state["candidate_rows"],
            health_row.get("candidate_rows"),
        )
        learning_rows = _coerce_int(
            training_row.get("learning_contract_rows"),
            health_row.get("rows_total"),
        )
        onnx_runtime_rows = _coerce_int(
            training_row.get("onnx_runtime_rows"),
            model_state["runtime_rows"],
            runtime_row.get("outcome_rows"),
        )
        outcome_rows = _coerce_int(
            training_row.get("outcome_rows"),
            model_state["outcome_rows"],
            runtime_row.get("outcome_rows"),
        )
        labeled_rows = _coerce_int(
            model_state["labeled_rows"],
            health_row.get("rows_total"),
        )

        training_state = (
            str(training_row.get("training_readiness_state") or "").strip()
            or str(model_state["training_mode"] or "").strip()
            or str(runtime_row.get("local_training_mode") or "").strip()
            or "FALLBACK_ONLY"
        )
        guardrail_state = (
            str(training_row.get("guardrail_state") or "").strip()
            or str(guardrail_row.get("guardrail_state") or "").strip()
        )
        guardrail_reason = (
            str(training_row.get("guardrail_reason") or "").strip()
            or str(guardrail_row.get("diagnosis") or "").strip()
        )
        promotion = model_state["promotion"]
        promotion_approved = _coerce_bool(promotion.get("approved"), default=False)
        promotion_reasons = [str(item) for item in promotion.get("reasons", []) if str(item).strip()]
        package_present = symbol in package_symbols
        runtime_contract_path = str(runtime_row.get("path") or "").strip()
        runtime_contract_present = bool(runtime_contract_path) and Path(runtime_contract_path).exists()
        registry_present = symbol in symbol_registry_rows
        local_model_available = (
            model_state["student_model_available"]
            or _coerce_bool(runtime_row.get("local_model_available"), default=False)
            or bool(str(symbol_registry_row.get("student_model_path") or "").strip())
        )
        rollback_detected = bool(local_audit_row) or guardrail_state.upper() == "FORCED_GLOBAL_FALLBACK"
        runtime_state = _derive_local_runtime_state(
            package_present=package_present,
            runtime_contract_present=runtime_contract_present,
            local_model_available=local_model_available,
            promotion_approved=promotion_approved,
            forced_fallback=(guardrail_state.upper() == "FORCED_GLOBAL_FALLBACK"),
        )
        readiness_reasons = _build_readiness_reasons(
            candidate_rows=candidate_rows,
            outcome_rows=outcome_rows,
            broker_net_ready=broker_net_ready,
            package_present=package_present,
            runtime_contract_present=runtime_contract_present,
            local_model_available=local_model_available,
            registry_present=registry_present,
            rollback_detected=rollback_detected,
            guardrail_state=guardrail_state,
            promotion_reasons=promotion_reasons,
        )

        if training_state == "FALLBACK_ONLY":
            readiness_verdict = "GLOBAL_FALLBACK"
        elif runtime_state == "LOCAL_RUNTIME_READY":
            readiness_verdict = "READY_FOR_LOCAL_RUNTIME"
        elif candidate_rows > 0:
            readiness_verdict = "TRAIN_ONLY"
        else:
            readiness_verdict = "GLOBAL_FALLBACK"

        item = {
            "symbol_alias": symbol,
            "broker_symbol": registry_row.get("broker_symbol", ""),
            "session_profile": registry_row.get("session_profile", ""),
            "expert": registry_row.get("expert", ""),
            "preset": registry_row.get("preset", ""),
            "training_state": training_state,
            "runtime_state": runtime_state,
            "readiness_verdict": readiness_verdict,
            "readiness_reasons": readiness_reasons,
            "local_training_eligibility": str(training_row.get("local_training_eligibility") or "").strip(),
            "teacher_dependency_level": str(training_row.get("teacher_dependency_level") or "").strip(),
            "learning_health_state": str(training_row.get("learning_health_state") or health_row.get("status") or "").strip(),
            "guardrail_state": guardrail_state,
            "guardrail_reason": guardrail_reason,
            "rollback_detected": rollback_detected,
            "in_lane_start_group": symbol in lane_start_group,
            "in_plan_start_group": symbol in plan_start_group,
            "candidate_rows": candidate_rows,
            "learning_rows": learning_rows,
            "onnx_runtime_rows": onnx_runtime_rows,
            "outcome_rows": outcome_rows,
            "labeled_rows": labeled_rows,
            "package_present": package_present,
            "runtime_contract_present": runtime_contract_present,
            "runtime_contract_path": runtime_contract_path,
            "symbol_registry_present": registry_present,
            "broker_net_pln_ready": broker_net_ready,
            "local_model_available": local_model_available,
            "student_model_path": model_state["onnx_path"] or str(symbol_registry_row.get("student_model_path") or "").strip(),
            "student_joblib_path": model_state["joblib_path"],
            "metrics_path": model_state["metrics_path"],
            "report_path": model_state["report_path"],
            "promotion_approved": promotion_approved,
            "promotion_reasons": promotion_reasons,
        }
        items.append(item)

        training_state_counts[training_state] = training_state_counts.get(training_state, 0) + 1
        runtime_state_counts[runtime_state] = runtime_state_counts.get(runtime_state, 0) + 1
        for reason in readiness_reasons:
            reason_counts[reason] = reason_counts.get(reason, 0) + 1

    items.sort(key=lambda row: (row["runtime_state"], row["symbol_alias"]))

    summary = {
        "total_symbols": len(active_symbols),
        "training_ready_count": training_state_counts.get("LOCAL_TRAINING_READY", 0),
        "training_limited_count": training_state_counts.get("LOCAL_TRAINING_LIMITED", 0),
        "fallback_only_count": training_state_counts.get("FALLBACK_ONLY", 0),
        "training_shadow_ready_count": training_state_counts.get("TRAINING_SHADOW_READY", 0),
        "runtime_ready_count": runtime_state_counts.get("LOCAL_RUNTIME_READY", 0),
        "runtime_package_present_but_disabled_count": runtime_state_counts.get("PACKAGE_PRESENT_BUT_DISABLED", 0),
        "runtime_global_only_count": runtime_state_counts.get("GLOBAL_ONLY", 0),
        "symbols_with_local_artifacts_count": sum(1 for row in items if row["local_model_available"]),
        "symbols_with_runtime_contract_count": sum(1 for row in items if row["runtime_contract_present"]),
        "symbols_with_package_entry_count": sum(1 for row in items if row["package_present"]),
        "broker_net_pln_ready": broker_net_ready,
        "reason_counts": reason_counts,
        "stale_symbol_model_dir_count": len(stale_symbol_model_dirs),
        "stale_symbol_registry_count": len(stale_registry_symbols),
    }

    return {
        "schema_version": "1.0",
        "generated_at_utc": utc_now_iso(),
        "active_fleet": {
            "count": len(active_symbols),
            "symbols": active_symbols,
        },
        "summary": summary,
        "stale_symbol_model_dirs": stale_symbol_model_dirs,
        "stale_symbol_registry_symbols": stale_registry_symbols,
        "items": items,
    }


def write_local_model_readiness_audit(paths: OverlayPaths) -> dict[str, Any]:
    payload = build_local_model_readiness_audit(paths)
    dump_json(paths.local_model_readiness_path, payload)
    return payload


def inspect_mql5_runtime(paths: OverlayPaths, active_registry: list[dict[str, Any]]) -> dict[str, Any]:
    microbots_dir = paths.resolve_microbots_dir()
    rows: dict[str, Any] = {}
    include_bridge_count = 0
    decision_gate_count = 0
    execution_snapshot_count = 0
    ledger_count = 0
    feature_contract_count = 0

    for item in active_registry:
        symbol = item["symbol"]
        expert = item["expert"]
        file_path = microbots_dir / f"{expert}.mq5"
        source = file_path.read_text(encoding="utf-8", errors="ignore") if file_path.exists() else ""
        has_bridge = "MbMlRuntimeBridge.mqh" in source
        has_snapshot = "MbExecutionSnapshot.mqh" in source or "MbMlRuntimeBridgeFlushSnapshot(" in source
        has_ledger = "MbBrokerNetLedger.mqh" in source or "MbMlRuntimeBridgeAppendPaperLedger(" in source
        has_feature_contract = (
            "MbMlFeatureContract.mqh" in source
            or "MbMlRuntimeBridgeWriteFeatureContract" in source
            or "MbMlRuntimeBridgeFlushSnapshot(" in source
        )
        has_student_gate = "MbStudentDecisionGate.mqh" in source or "MbMlRuntimeBridgeApplyStudentGate(" in source
        include_bridge_count += int(has_bridge)
        execution_snapshot_count += int(has_snapshot)
        ledger_count += int(has_ledger)
        feature_contract_count += int(has_feature_contract)
        decision_gate_count += int(has_student_gate)
        rows[symbol] = {
            "path": str(file_path),
            "exists": file_path.exists(),
            "bridge_include": has_bridge,
            "execution_snapshot_hook": has_snapshot,
            "ledger_hook": has_ledger,
            "feature_contract_hook": has_feature_contract,
            "student_gate_hook": has_student_gate,
        }

    pending = [symbol for symbol, row in rows.items() if not row["bridge_include"]]
    return {
        "microbots_dir": str(microbots_dir),
        "symbols": rows,
        "bridge_include_count": include_bridge_count,
        "execution_snapshot_hook_count": execution_snapshot_count,
        "ledger_hook_count": ledger_count,
        "feature_contract_hook_count": feature_contract_count,
        "student_gate_hook_count": decision_gate_count,
        "pending_symbols": pending,
        "ok": len(pending) == 0,
    }


def build_overlay_audit(
    paths: OverlayPaths,
    thresholds: AuditThresholds | None = None,
) -> dict[str, Any]:
    thresholds = thresholds or AuditThresholds()
    active_registry = load_active_registry_symbols(paths)
    active_symbols = [item["symbol"] for item in active_registry]

    candidate_counts = parquet_symbol_counts(paths.candidate_contract_path)
    runtime_counts = parquet_symbol_counts(paths.onnx_observations_contract_path)
    outcome_counts = parquet_symbol_counts(paths.learning_contract_path)
    symbol_modes = determine_symbol_modes(active_symbols, candidate_counts, outcome_counts, runtime_counts, thresholds)

    tail_bridge = inspect_tail_bridge(paths, thresholds)
    ledger = inspect_broker_net_ledger(paths, thresholds)
    package = inspect_package(paths, thresholds)
    symbol_models = inspect_symbol_models(paths, active_symbols, symbol_modes)
    runtime = inspect_mql5_runtime(paths, active_registry)
    lightgbm_available = try_import_lightgbm()

    warnings: list[str] = []
    errors: list[str] = []
    if not tail_bridge["exists"]:
        errors.append("SERVER_PARITY_TAIL_BRIDGE_MISSING")
    elif tail_bridge["missing_tail_count"] > 0:
        errors.append("SERVER_PARITY_TAIL_STALE_OR_INCOMPLETE")
    elif tail_bridge["age_hours"] is not None and tail_bridge["age_hours"] > thresholds.tail_freshness_hours:
        errors.append("SERVER_PARITY_TAIL_TOO_OLD")

    if not ledger["exists"]:
        errors.append("BROKER_NET_LEDGER_MISSING")
    elif ledger["labeled_rows"] < thresholds.min_labeled_rows_for_rollout:
        errors.append("BROKER_NET_LEDGER_TOO_FEW_LABELED_ROWS")
    elif ledger["age_hours"] is not None and ledger["age_hours"] > thresholds.ledger_freshness_hours:
        errors.append("BROKER_NET_LEDGER_TOO_OLD")
    if ledger["natural_drop_flag"]:
        errors.append("BROKER_NET_LEDGER_NATURAL_DROP_FLAG")

    if not package["exists"]:
        warnings.append("MT5_PACKAGE_MISSING")
    elif package["preview_only"]:
        warnings.append("MT5_PACKAGE_PREVIEW_ONLY")
    elif not package["global_model_onnx_exists"]:
        warnings.append("GLOBAL_ONNX_MISSING")
    if not symbol_models["ok"]:
        warnings.append("SYMBOL_MODELS_INCOMPLETE")
    if not runtime["ok"]:
        warnings.append("MQL5_RUNTIME_BRIDGE_INCOMPLETE")
    if not lightgbm_available:
        warnings.append("LIGHTGBM_FALLBACK_ACTIVE")

    rollout_blocked = len(errors) > 0
    package_should_export = not rollout_blocked and package["exists"] and not package["preview_only"]

    audit = {
        "schema_version": "1.0",
        "generated_at_utc": utc_now_iso(),
        "summary": {
            "rollout_blocked": rollout_blocked,
            "package_should_export": package_should_export,
            "warnings": warnings,
            "errors": errors,
            "lightgbm_available": lightgbm_available,
        },
        "active_fleet": {
            "count": len(active_symbols),
            "symbols": active_symbols,
        },
        "tail_bridge": tail_bridge,
        "broker_net_ledger": ledger,
        "package": package,
        "symbol_models": symbol_models,
        "runtime_mql5": runtime,
        "symbol_activity": {
            "candidate_counts": candidate_counts,
            "runtime_counts": runtime_counts,
            "outcome_counts": outcome_counts,
            "training_modes": symbol_modes,
        },
    }
    return audit


def write_overlay_audit(paths: OverlayPaths, thresholds: AuditThresholds | None = None) -> dict[str, Any]:
    audit = build_overlay_audit(paths, thresholds=thresholds)
    dump_json(paths.overlay_audit_path, audit)
    dump_json(
        paths.overlay_rollout_guard_path,
        {
            "schema_version": "1.0",
            "generated_at_utc": audit["generated_at_utc"],
            "rollout_blocked": audit["summary"]["rollout_blocked"],
            "warnings": audit["summary"]["warnings"],
            "errors": audit["summary"]["errors"],
            "package_should_export": audit["summary"]["package_should_export"],
        },
    )
    dump_json(
        paths.overlay_runtime_audit_path,
        {
            "schema_version": "1.0",
            "generated_at_utc": audit["generated_at_utc"],
            "runtime_mql5": audit["runtime_mql5"],
            "symbol_activity": audit["symbol_activity"],
        },
    )
    return audit
