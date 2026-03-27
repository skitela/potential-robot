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
    bad_states: list[str] = []
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
                  coalesce(sum(case when upper(cast({state_column} as varchar)) <> 'OK' then 1 else 0 end), 0) as bad_rows,
                  string_agg(distinct cast({state_column} as varchar), ',') as states
                from read_parquet(?)
                """,
                [str(paths.tail_bridge_path)],
            )
            if result:
                missing_tail_count = int(result[0].get("bad_rows") or 0)
                states_str = str(result[0].get("states") or "")
                bad_states = [item for item in states_str.split(",") if item and item != "OK"]
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
        "bad_states": bad_states,
        "ok": bool(exists and rows > 0 and missing_tail_count == 0 and (age_hours is None or age_hours <= thresholds.tail_freshness_hours)),
    }


def inspect_broker_net_ledger(paths: OverlayPaths, thresholds: AuditThresholds) -> dict[str, Any]:
    exists = paths.broker_net_ledger_path.exists()
    rows = 0
    labeled_rows = 0
    sample_symbols: list[str] = []
    age_hours = file_age_hours(paths.broker_net_ledger_path)
    if exists:
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
        "symbols_present": sorted(sample_symbols),
        "ok": bool(
            exists
            and rows > 0
            and labeled_rows >= thresholds.min_labeled_rows_for_rollout
            and not natural_drop_flag
            and (age_hours is None or age_hours <= thresholds.ledger_freshness_hours)
        ),
    }


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
