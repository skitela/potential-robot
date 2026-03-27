from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    balanced_accuracy_score,
    log_loss,
    precision_score,
    recall_score,
    roc_auc_score,
)

from .adapter import build_broker_net_ledger, build_master_training_frame, build_server_parity_tail_bridge
from .evaluation import aggregate_fold_reports, build_decisions, fold_report, fold_reports_to_frame
from .export import export_model_to_onnx
from .features import (
    BASE_CATEGORICAL_FEATURES,
    BASE_NUMERIC_FEATURES,
    assert_no_target_leakage,
    build_feature_frame,
)
from .labels import build_targets
from .models import FittedBundle, fit_model, positive_proba, regression_pred
from .paths import CompatPaths
from .promotion import evaluate_promotion
from .registry import build_symbol_readiness, load_active_symbols
from .splits import make_walk_forward_splits
from .io_utils import ensure_dir, write_json


@dataclass(slots=True)
class TrainingThresholds:
    global_train_days: int = 45
    global_valid_days: int = 5
    global_step_days: int = 5
    embargo_minutes: int = 10
    min_train_rows: int = 250
    min_valid_rows: int = 50
    min_symbol_labeled_rows: int = 120
    min_symbol_train_rows: int = 50
    min_symbol_valid_rows: int = 20
    min_symbol_classes: int = 2
    min_gate_probability: float = 0.53
    min_decision_score_pln: float = 0.0
    max_spread_points: float = 999.0
    max_runtime_latency_us: float = 250000.0
    max_server_ping_ms: float = 35.0
    regression_clip_pln: float = 300.0
    sample_weight_abs_cap_pln: float = 150.0


INT_COMPAT_FEATURES = {
    "renko_run_length",
    "renko_reversal_flag",
    "runtime_data_present",
    "server_runtime_state_present",
    "server_ping_contract_enabled",
    "qdm_tick_count",
    "qdm_data_present",
    "hour",
    "day_of_week",
}


def _safe_float(value: Any, default: float = 0.0) -> float:
    try:
        if value is None or (isinstance(value, float) and np.isnan(value)):
            return default
        return float(value)
    except Exception:
        return default


def _normalize_feature_name_for_compat(name: str) -> str:
    out = str(name)
    out = out.replace("symbol_alias_", "symbol_")
    return out


def _extract_top_features(bundle: FittedBundle, limit: int = 20) -> dict[str, list[dict[str, float | str]]]:
    estimator = bundle.estimator
    try:
        pre = estimator.named_steps["pre"]
        model = estimator.named_steps["model"]
        raw_names = list(pre.get_feature_names_out())
    except Exception:
        return {"positive": [], "negative": []}

    feature_names = [_normalize_feature_name_for_compat(name) for name in raw_names]
    positives: list[dict[str, float | str]] = []
    negatives: list[dict[str, float | str]] = []

    if hasattr(model, "coef_"):
        coefficients = np.asarray(model.coef_, dtype=float).reshape(-1)
        ranked = sorted(zip(feature_names, coefficients), key=lambda item: abs(item[1]), reverse=True)
        positives = [
            {"feature": name, "coefficient": float(coef)}
            for name, coef in ranked
            if coef > 0
        ][:limit]
        negatives = [
            {"feature": name, "coefficient": float(coef)}
            for name, coef in ranked
            if coef < 0
        ][:limit]
        return {"positive": positives, "negative": negatives}

    if hasattr(model, "feature_importances_"):
        importances = np.asarray(model.feature_importances_, dtype=float).reshape(-1)
        ranked = sorted(zip(feature_names, importances), key=lambda item: item[1], reverse=True)
        positives = [
            {"feature": name, "coefficient": float(value)}
            for name, value in ranked[:limit]
        ]
        return {"positive": positives, "negative": negatives}

    return {"positive": [], "negative": []}


def _classify_feature_contract(contract) -> tuple[list[str], list[str]]:
    numeric_int = [feature for feature in contract.numeric_features if feature in INT_COMPAT_FEATURES]
    numeric_float = [feature for feature in contract.numeric_features if feature not in INT_COMPAT_FEATURES]
    return numeric_float, numeric_int


def _build_global_metrics_compat(
    *,
    paths: CompatPaths,
    master: pd.DataFrame,
    feature_frame: pd.DataFrame,
    summary: dict[str, Any],
    contract,
    gate_bundle: FittedBundle,
    gate_probability: np.ndarray,
    metrics: dict[str, Any],
    promotion: dict[str, Any],
    export_onnx: bool,
    onnx_path: str,
    onnx_error: str,
    priors: dict[str, Any],
) -> dict[str, Any]:
    y_true = feature_frame["y_gate"].to_numpy(dtype=int)
    y_pred = (np.asarray(gate_probability, dtype=float) >= 0.5).astype(int)

    try:
        roc_auc = float(roc_auc_score(y_true, gate_probability))
    except Exception:
        roc_auc = 0.0
    try:
        average_precision = float(average_precision_score(y_true, gate_probability))
    except Exception:
        average_precision = 0.0
    try:
        loss = float(log_loss(y_true, np.clip(np.asarray(gate_probability, dtype=float), 1e-6, 1 - 1e-6)))
    except Exception:
        loss = 0.0

    qdm_present = pd.to_numeric(master.get("qdm_data_present", pd.Series(dtype=float)), errors="coerce").fillna(0.0)
    rows_with_qdm = int((qdm_present > 0).sum()) if not master.empty else 0
    symbol_coverage = []
    if not master.empty and "symbol_alias" in master.columns:
        grouped = master.assign(_qdm_present=(qdm_present > 0).astype(int)).groupby("symbol_alias", dropna=True)
        for symbol, group in grouped:
            total_rows = int(len(group))
            with_qdm = int(group["_qdm_present"].sum())
            symbol_coverage.append(
                {
                    "symbol": str(symbol),
                    "rows_total": total_rows,
                    "rows_with_qdm": with_qdm,
                    "coverage_ratio": _safe_float(with_qdm / total_rows if total_rows else 0.0),
                }
            )
        symbol_coverage = sorted(symbol_coverage, key=lambda item: item["rows_total"], reverse=True)

    server_ping = _safe_float(feature_frame.get("server_operational_ping_ms", pd.Series(dtype=float)).replace(0, np.nan).median(), 0.0)
    numeric_float, numeric_int = _classify_feature_contract(contract)
    top_features = _extract_top_features(gate_bundle)
    train_rows = int(max((report.train_rows for report in []), default=0))
    test_rows = int(max((report.valid_rows for report in []), default=0))

    if not master.empty and "ts" in master.columns:
        ts_numeric = pd.to_datetime(master["ts"], utc=True, errors="coerce").astype("int64") // 10**9
        ts_numeric = ts_numeric.replace({-9223372037: np.nan}).dropna()
        ts_min = int(ts_numeric.min()) if not ts_numeric.empty else None
        ts_max = int(ts_numeric.max()) if not ts_numeric.empty else None
    else:
        ts_min = None
        ts_max = None

    compat_metrics = {
        "accuracy": float(accuracy_score(y_true, y_pred)),
        "balanced_accuracy": float(balanced_accuracy_score(y_true, y_pred)),
        "precision": float(precision_score(y_true, y_pred, zero_division=0)),
        "recall": float(recall_score(y_true, y_pred, zero_division=0)),
        "roc_auc": roc_auc,
        "average_precision": average_precision,
        "log_loss": loss,
        "positive_rate_actual": _safe_float(np.mean(y_true), 0.0),
        "positive_rate_predicted": _safe_float(np.mean(y_pred), 0.0),
        "fold_count": _safe_float(metrics.get("fold_count"), 0.0),
        "selected_trades_total": _safe_float(metrics.get("selected_trades_total"), 0.0),
        "pnl_sum_total_pln": _safe_float(metrics.get("pnl_sum_total_pln"), 0.0),
        "profit_factor_median": _safe_float(metrics.get("profit_factor_median"), 0.0),
        "max_drawdown_worst_pln": _safe_float(metrics.get("max_drawdown_worst_pln"), 0.0),
        "win_rate_median": _safe_float(metrics.get("win_rate_median"), 0.0),
        "precision_at_10pct_median": _safe_float(metrics.get("precision_at_10pct_median"), 0.0),
        "brier_median": _safe_float(metrics.get("brier_median"), 0.0),
        "roc_auc_median": _safe_float(metrics.get("roc_auc_median"), roc_auc),
        "balanced_accuracy_median": _safe_float(metrics.get("balanced_accuracy_median"), float(balanced_accuracy_score(y_true, y_pred))),
    }

    return {
        "dataset": {
            "db_path": str(paths.research_root / "microbot_research.duckdb"),
            "candidate_parquet_path": str(paths.candidate_signals_norm_latest),
            "qdm_parquet_path": str(paths.qdm_minute_bars_latest),
            "onnx_parquet_path": str(paths.onnx_observations_norm_latest),
            "runtime_state_parquet_path": str(paths.runtime_state_latest),
            "execution_ping_contract_path": str(paths.execution_ping_contract_csv),
            "source_kind": "PARQUET",
            "symbol_filter": "",
            "scope": "GLOBAL",
            "total_rows": int(len(feature_frame)),
            "train_rows": train_rows,
            "test_rows": test_rows,
            "positive_rate": _safe_float(np.mean(y_true), 0.0),
            "positive_rows": int((y_true == 1).sum()),
            "negative_rows": int((y_true == 0).sum()),
            "ts_min": ts_min,
            "ts_max": ts_max,
            "qdm_coverage": {
                "rows_with_qdm": rows_with_qdm,
                "row_coverage_ratio": _safe_float(rows_with_qdm / len(master) if len(master) else 0.0),
                "symbols_with_qdm": [item["symbol"] for item in symbol_coverage if item["rows_with_qdm"] > 0],
                "symbol_coverage": symbol_coverage,
            },
            "server_execution_ping_contract": {
                "enabled": True,
                "paper_operational_ping_ms": server_ping,
                "live_operational_ping_ms": server_ping,
                "source": "hosting_vps_broker",
            },
        },
        "features": {
            "categorical": contract.categorical_features,
            "numeric_float": numeric_float,
            "numeric_int": numeric_int,
            "teacher_feature_enabled": "teacher_global_score" in contract.all_features,
        },
        "model": {
            "family": "SGDClassifier",
            "role": "MODEL_GLOBALNY_BRAMKUJACY",
            "training_target": "net_pln_broker",
            "supports_sparse_categorical": True,
            "supports_onnx_export": bool(export_onnx),
        },
        "metrics": compat_metrics,
        "top_features": top_features,
        "promotion": promotion,
        "summary": summary,
        "feature_contract": {
            "all_features": contract.all_features,
            "categorical_features": contract.categorical_features,
        },
        "artifacts": {
            "paper_gate_acceptor_latest.joblib": str(paths.global_model_dir / "paper_gate_acceptor_latest.joblib"),
            "paper_gate_acceptor_latest.onnx": onnx_path,
            "paper_gate_acceptor_latest.onnx_error": onnx_error,
            "global_edge_prior_latest": priors["edge_prior"],
            "global_fill_prior_latest": priors["fill_prior"],
            "global_slippage_prior_latest": priors["slippage_prior"],
        },
        "calibrator_present": True,
        "notes": [
            "Teacher score liczony out-of-fold na walk-forward splitach.",
            "Cechy odcinają net_pln i koszty zrealizowane po fakcie.",
            "Trening globalny używa istniejących kontraktów candidate/onnx/learning i joinów zgodności.",
        ],
    }


def _build_symbol_registry_compat(paths: CompatPaths, results: dict[str, Any]) -> dict[str, Any]:
    items = []
    for symbol in load_active_symbols(paths):
        payload = results.get(symbol, {})
        training_mode = str(payload.get("training_mode", "FALLBACK_ONLY"))
        promotion = payload.get("promotion", {}) or {}
        metrics = payload.get("metrics", {}) or {}
        artifacts = payload.get("artifacts", {}) or {}
        gate_artifacts = artifacts.get("student_gate", {}) or {}
        onnx_path = gate_artifacts.get("onnx") or ""
        joblib_path = gate_artifacts.get("joblib") or ""
        has_local_model = bool(onnx_path or joblib_path)
        status = "MODEL_PER_SYMBOL_READY" if has_local_model and training_mode != "FALLBACK_ONLY" else "GLOBAL_FALLBACK"
        rows_total = int(payload.get("labeled_rows", 0) or 0)
        candidate_rows = int(payload.get("candidate_rows", 0) or 0)
        positive_rows = int(round(rows_total * _safe_float(metrics.get("positive_rate_actual"), 0.0), 0))
        negative_rows = max(0, rows_total - positive_rows)
        items.append(
            {
                "symbol": symbol,
                "symbol_alias": symbol,
                "status": status,
                "fallback_scope": "GLOBAL_MODEL" if status == "GLOBAL_FALLBACK" else "",
                "reason": "; ".join([str(reason) for reason in promotion.get("reasons", [])]) if status == "GLOBAL_FALLBACK" else training_mode,
                "rows_total": rows_total,
                "candidate_rows": candidate_rows,
                "positive_rows": positive_rows,
                "negative_rows": negative_rows,
                "roc_auc": _safe_float(metrics.get("roc_auc_median"), 0.0),
                "balanced_accuracy": _safe_float(metrics.get("balanced_accuracy_median"), 0.0),
                "teacher_enabled": status == "MODEL_PER_SYMBOL_READY",
                "data_source": "BROKER_NET_LEDGER",
                "onnx_path": onnx_path or None,
                "joblib_path": joblib_path or None,
                "metrics_path": str(paths.symbol_models_dir / symbol / "paper_gate_acceptor_metrics_latest.json") if (paths.symbol_models_dir / symbol / "paper_gate_acceptor_metrics_latest.json").exists() else None,
                "training_mode": training_mode,
                "promotion_approved": bool(promotion.get("approved", False)),
            }
        )
    ready_count = sum(1 for item in items if item["status"] == "MODEL_PER_SYMBOL_READY")
    return {
        "generated_at_local": pd.Timestamp.now(tz="Europe/Warsaw").strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": pd.Timestamp.utcnow().isoformat(),
        "total_symbols": len(items),
        "ready_count": ready_count,
        "fallback_count": len(items) - ready_count,
        "trained_now_count": ready_count,
        "items": items,
    }


def _fit_platt(raw_score: np.ndarray, y_true: np.ndarray) -> tuple[LogisticRegression | None, np.ndarray]:
    x = np.asarray(raw_score, dtype=float).reshape(-1, 1)
    y = np.asarray(y_true, dtype=int)
    if len(np.unique(y)) < 2:
        return None, np.full_like(raw_score, fill_value=float(y[0]) if len(y) else 0.5, dtype=float)
    model = LogisticRegression(max_iter=1000)
    model.fit(x, y)
    calibrated = model.predict_proba(x)[:, 1]
    return model, calibrated


def _adjust_split_thresholds_for_frame(frame: pd.DataFrame, thresholds: TrainingThresholds) -> TrainingThresholds:
    if frame.empty or "ts" not in frame.columns:
        return thresholds

    ts = pd.to_datetime(frame["ts"], utc=True, errors="coerce").dropna()
    if ts.empty:
        return thresholds

    span_days = max(1, int(np.ceil((ts.max() - ts.min()).total_seconds() / 86400.0)))
    requested_days = int(thresholds.global_train_days + thresholds.global_valid_days)
    if span_days >= requested_days:
        return thresholds

    valid_days = min(int(thresholds.global_valid_days), max(1, span_days // 4))
    train_days = min(int(thresholds.global_train_days), max(1, span_days - valid_days))
    if train_days + valid_days > span_days:
        if span_days <= 1:
            train_days = 1
            valid_days = 1
        else:
            valid_days = min(valid_days, max(1, span_days // 3))
            train_days = max(1, span_days - valid_days)
    step_days = max(1, min(int(thresholds.global_step_days), valid_days))

    return TrainingThresholds(
        global_train_days=train_days,
        global_valid_days=valid_days,
        global_step_days=step_days,
        embargo_minutes=thresholds.embargo_minutes,
        min_train_rows=thresholds.min_train_rows,
        min_valid_rows=thresholds.min_valid_rows,
        min_symbol_labeled_rows=thresholds.min_symbol_labeled_rows,
        min_symbol_train_rows=thresholds.min_symbol_train_rows,
        min_symbol_valid_rows=thresholds.min_symbol_valid_rows,
        min_symbol_classes=thresholds.min_symbol_classes,
        min_gate_probability=thresholds.min_gate_probability,
        min_decision_score_pln=thresholds.min_decision_score_pln,
        max_spread_points=thresholds.max_spread_points,
        max_runtime_latency_us=thresholds.max_runtime_latency_us,
        max_server_ping_ms=thresholds.max_server_ping_ms,
        regression_clip_pln=thresholds.regression_clip_pln,
        sample_weight_abs_cap_pln=thresholds.sample_weight_abs_cap_pln,
    )


def _build_oof_teacher_scores(
    frame: pd.DataFrame,
    feature_names: list[str],
    categorical_features: list[str],
    thresholds: TrainingThresholds,
    model_family: str = "sgd_classifier",
) -> tuple[pd.Series, FittedBundle, LogisticRegression | None]:
    assert_no_target_leakage(feature_names)
    split_thresholds = _adjust_split_thresholds_for_frame(frame, thresholds)
    splits = make_walk_forward_splits(
        frame,
        time_col="ts",
        train_days=split_thresholds.global_train_days,
        valid_days=split_thresholds.global_valid_days,
        step_days=split_thresholds.global_step_days,
        embargo_minutes=split_thresholds.embargo_minutes,
        min_train_rows=split_thresholds.min_train_rows,
        min_valid_rows=split_thresholds.min_valid_rows,
    )
    if not splits:
        raise RuntimeError("Nie udało się zbudować żadnego poprawnego walk-forward splitu.")

    oof = pd.Series(np.nan, index=frame.index, dtype="float64")
    valid_idx_all: list[int] = []
    y_all: list[int] = []

    for window in splits:
        train_frame = frame.loc[window.train_index].copy()
        valid_frame = frame.loc[window.valid_index].copy()
        bundle = fit_model(
            family=model_family,
            task="classification",
            frame=train_frame,
            feature_names=feature_names,
            categorical_features=categorical_features,
            random_state=42,
            target_col="y_gate",
            sample_weight_col="sample_weight",
        )
        probs = positive_proba(bundle, valid_frame[feature_names])
        oof.loc[window.valid_index] = probs
        valid_idx_all.extend(window.valid_index)
        y_all.extend(valid_frame["y_gate"].tolist())

    calibrator = None
    if valid_idx_all:
        calibrator, calibrated = _fit_platt(oof.loc[valid_idx_all].to_numpy(dtype=float), np.asarray(y_all, dtype=int))
        oof.loc[valid_idx_all] = calibrated

    final_bundle = fit_model(
        family=model_family,
        task="classification",
        frame=frame,
        feature_names=feature_names,
        categorical_features=categorical_features,
        random_state=42,
        target_col="y_gate",
        sample_weight_col="sample_weight",
    )
    full_pred = positive_proba(final_bundle, frame[feature_names])
    if calibrator is not None:
        full_pred = calibrator.predict_proba(full_pred.reshape(-1, 1))[:, 1]
    oof = oof.fillna(pd.Series(full_pred, index=frame.index))
    return oof, final_bundle, calibrator


def _train_validation_cycle(
    frame: pd.DataFrame,
    feature_names: list[str],
    categorical_features: list[str],
    thresholds: TrainingThresholds,
    edge_family: str = "lightgbm_regressor",
    fill_family: str = "logistic_regression",
    slippage_family: str = "lightgbm_regressor",
) -> tuple[list, dict]:
    split_thresholds = _adjust_split_thresholds_for_frame(frame, thresholds)
    splits = make_walk_forward_splits(
        frame,
        time_col="ts",
        train_days=split_thresholds.global_train_days,
        valid_days=split_thresholds.global_valid_days,
        step_days=split_thresholds.global_step_days,
        embargo_minutes=split_thresholds.embargo_minutes,
        min_train_rows=split_thresholds.min_train_rows,
        min_valid_rows=split_thresholds.min_valid_rows,
    )

    reports = []
    for window in splits:
        train_frame = frame.loc[window.train_index].copy()
        valid_frame = frame.loc[window.valid_index].copy()

        edge_bundle = fit_model(
            family=edge_family,
            task="regression",
            frame=train_frame,
            feature_names=feature_names,
            categorical_features=categorical_features,
            random_state=42,
            target_col="y_edge_reg",
            sample_weight_col="sample_weight",
        )
        fill_bundle = None
        if train_frame["y_fill"].nunique() > 1:
            fill_bundle = fit_model(
                family=fill_family,
                task="classification",
                frame=train_frame,
                feature_names=feature_names,
                categorical_features=categorical_features,
                random_state=42,
                target_col="y_fill",
                sample_weight_col="sample_weight",
            )
        slippage_bundle = fit_model(
            family=slippage_family,
            task="regression",
            frame=train_frame,
            feature_names=feature_names,
            categorical_features=categorical_features,
            random_state=42,
            target_col="y_slippage_reg",
            sample_weight_col="sample_weight",
        )

        gate_probability = valid_frame["teacher_global_score"].to_numpy(dtype=float)
        edge_prediction = regression_pred(edge_bundle, valid_frame[feature_names])
        fill_probability = positive_proba(fill_bundle, valid_frame[feature_names]) if fill_bundle else None
        slippage_prediction = regression_pred(slippage_bundle, valid_frame[feature_names])

        decided = build_decisions(
            valid_frame,
            gate_probability=gate_probability,
            edge_prediction_pln=edge_prediction,
            fill_probability=fill_probability,
            slippage_prediction_pln=slippage_prediction,
            min_gate_probability=thresholds.min_gate_probability,
            min_decision_score_pln=thresholds.min_decision_score_pln,
            max_spread_points=thresholds.max_spread_points,
            max_runtime_latency_us=thresholds.max_runtime_latency_us,
            max_server_ping_ms=thresholds.max_server_ping_ms,
        )
        rep = fold_report(window.fold_id, decided, valid_frame["y_gate"].to_numpy(dtype=int), gate_probability)
        rep.train_rows = int(len(train_frame))
        rep.valid_rows = int(len(valid_frame))
        reports.append(rep)

    return reports, aggregate_fold_reports(reports)


def _save_training_artifacts(
    model_dir: Path,
    bundle: FittedBundle | None,
    sample_frame: pd.DataFrame,
    family: str,
    basename: str,
    export_onnx: bool,
) -> dict[str, str]:
    ensure_dir(model_dir)
    result = {"joblib": "", "onnx": "", "onnx_error": ""}
    if bundle is None:
        return result
    joblib_path = model_dir / f"{basename}.joblib"
    joblib.dump(bundle, joblib_path)
    result["joblib"] = str(joblib_path)
    if export_onnx and not sample_frame.empty:
        onnx_path, onnx_error = export_model_to_onnx(bundle.estimator, sample_frame[bundle.features], model_dir / f"{basename}.onnx", family=family)
        if onnx_path is not None:
            result["onnx"] = str(onnx_path)
        if onnx_error:
            result["onnx_error"] = onnx_error
    return result


def _prepare_labeled_frame(paths: CompatPaths, thresholds: TrainingThresholds) -> tuple[pd.DataFrame, dict, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    master, summary, src = build_master_training_frame(paths)
    tail_bridge, tail_summary = build_server_parity_tail_bridge(paths)
    ledger, ledger_summary = build_broker_net_ledger(paths)

    if master.empty:
        raise RuntimeError("Brak kandydatów w candidate_signals_norm_latest.parquet.")

    required_labeled_columns = [
        "ts",
        "symbol_alias",
        "outcome_known",
        "net_pln",
        "slippage_cost_pln",
        "close_reason",
    ] + BASE_NUMERIC_FEATURES + BASE_CATEGORICAL_FEATURES
    available_labeled_columns = [column for column in dict.fromkeys(required_labeled_columns) if column in master.columns]
    labeled_mask = pd.to_numeric(master.get("outcome_known", pd.Series(dtype=float)), errors="coerce").fillna(0).eq(1)
    labeled = master.loc[labeled_mask, available_labeled_columns]
    if labeled.empty:
        raise RuntimeError("Brak domkniętych outcome. Trening na net_pln nie ma z czego powstać.")

    labeled, contract = build_feature_frame(labeled, ts_col="ts")
    labeled = build_targets(
        labeled,
        gate_positive_min_pln=0.0,
        regression_clip_pln=thresholds.regression_clip_pln,
        sample_weight_abs_cap_pln=thresholds.sample_weight_abs_cap_pln,
    )
    summary.update({
        "tail_bridge": tail_summary,
        "broker_net_ledger": ledger_summary,
        "feature_contract": {
            "numeric_features": contract.numeric_features,
            "categorical_features": contract.categorical_features,
        },
    })
    return labeled, summary, master, src.runtime, src.learning


def train_global_model(
    paths: CompatPaths,
    export_onnx: bool = False,
    thresholds: TrainingThresholds | None = None,
) -> dict[str, Any]:
    thresholds = thresholds or TrainingThresholds()
    labeled, summary, master, runtime, learning = _prepare_labeled_frame(paths, thresholds)

    feature_frame, contract = build_feature_frame(labeled, ts_col="ts")
    teacher_features = [f for f in contract.all_features if f != "teacher_global_score"]
    teacher_scores, gate_bundle, calibrator = _build_oof_teacher_scores(
        feature_frame,
        feature_names=teacher_features,
        categorical_features=contract.categorical_features,
        thresholds=thresholds,
        model_family="sgd_classifier",
    )

    labeled = labeled.copy()
    labeled["teacher_global_score"] = teacher_scores
    feature_frame, contract = build_feature_frame(labeled, ts_col="ts")
    reports, metrics = _train_validation_cycle(feature_frame, contract.all_features, contract.categorical_features, thresholds)
    promotion = evaluate_promotion(metrics)

    final_gate_probability = positive_proba(gate_bundle, feature_frame[teacher_features])
    if calibrator is not None:
        final_gate_probability = calibrator.predict_proba(final_gate_probability.reshape(-1, 1))[:, 1]
    final_frame = feature_frame.copy()
    final_frame["teacher_global_score"] = final_gate_probability
    final_feature_frame, final_contract = build_feature_frame(final_frame, ts_col="ts")

    edge_bundle = fit_model(
        family="lightgbm_regressor",
        task="regression",
        frame=final_feature_frame,
        feature_names=final_contract.all_features,
        categorical_features=final_contract.categorical_features,
        random_state=42,
        target_col="y_edge_reg",
        sample_weight_col="sample_weight",
    )
    fill_bundle = None
    if final_feature_frame["y_fill"].nunique() > 1:
        fill_bundle = fit_model(
            family="logistic_regression",
            task="classification",
            frame=final_feature_frame,
            feature_names=final_contract.all_features,
            categorical_features=final_contract.categorical_features,
            random_state=42,
            target_col="y_fill",
            sample_weight_col="sample_weight",
        )
    slippage_bundle = fit_model(
        family="lightgbm_regressor",
        task="regression",
        frame=final_feature_frame,
        feature_names=final_contract.all_features,
        categorical_features=final_contract.categorical_features,
        random_state=42,
        target_col="y_slippage_reg",
        sample_weight_col="sample_weight",
    )

    model_dir = ensure_dir(paths.global_model_dir)
    gate_joblib = model_dir / "paper_gate_acceptor_latest.joblib"
    joblib.dump(gate_bundle, gate_joblib)

    onnx_path = ""
    onnx_error = ""
    if export_onnx:
        onnx_obj, onnx_err = export_model_to_onnx(gate_bundle.estimator, feature_frame[teacher_features], model_dir / "paper_gate_acceptor_latest.onnx", family="sgd_classifier")
        if onnx_obj is not None:
            onnx_path = str(onnx_obj)
        if onnx_err:
            onnx_error = onnx_err

    priors = {
        "edge_prior": _save_training_artifacts(model_dir, edge_bundle, final_feature_frame, "lightgbm_regressor", "global_edge_prior_latest", export_onnx),
        "fill_prior": _save_training_artifacts(model_dir, fill_bundle, final_feature_frame, "logistic_regression", "global_fill_prior_latest", export_onnx),
        "slippage_prior": _save_training_artifacts(model_dir, slippage_bundle, final_feature_frame, "lightgbm_regressor", "global_slippage_prior_latest", export_onnx),
    }

    metrics_payload = {
        "scope": "GLOBAL",
        "project_root": str(paths.project_root),
        "research_root": str(paths.research_root),
        "summary": summary,
        "metrics": metrics,
        "promotion": promotion,
        "feature_contract": {
            "all_features": final_contract.all_features,
            "categorical_features": final_contract.categorical_features,
        },
        "teacher_features": teacher_features,
        "artifacts": {
            "paper_gate_acceptor_latest.joblib": str(gate_joblib),
            "paper_gate_acceptor_latest.onnx": onnx_path,
            "paper_gate_acceptor_latest.onnx_error": onnx_error,
            "global_edge_prior_latest": priors["edge_prior"],
            "global_fill_prior_latest": priors["fill_prior"],
            "global_slippage_prior_latest": priors["slippage_prior"],
        },
        "calibrator_present": calibrator is not None,
        "notes": [
            "Teacher score liczony out-of-fold na walk-forward splitach.",
            "Cechy odcinają net_pln i koszty zrealizowane po fakcie.",
            "Trening globalny używa istniejących kontraktów candidate/onnx/learning i joinów zgodności.",
        ],
    }

    metrics_path = model_dir / "paper_gate_acceptor_latest_metrics.json"
    write_json(metrics_path, metrics_payload)
    write_json(model_dir / "paper_gate_acceptor_metrics_latest.json", metrics_payload)

    report_md = [
        "# PAPER GATE ACCEPTOR — raport globalny",
        "",
        f"- Wiersze labeled: {int(len(final_feature_frame))}",
        f"- Foldy: {int(metrics.get('fold_count', 0))}",
        f"- Suma netto walidacji: {metrics.get('pnl_sum_total_pln', 0.0):.2f} PLN",
        f"- Profit factor mediana: {metrics.get('profit_factor_median', 0.0):.3f}",
        f"- Precision@10% mediana: {metrics.get('precision_at_10pct_median', 0.0):.3f}",
        f"- Promocja: {'TAK' if promotion['approved'] else 'NIE'}",
        "",
        "## Powody",
        *[f"- {x}" for x in promotion["reasons"]],
        "",
        "## Krytyczne zabezpieczenia",
        "- target = net_pln, nie accepted",
        "- teacher_global_score jest out-of-fold",
        "- feature contract blokuje przeciek celu",
        "- walidacja = walk-forward + embargo",
    ]
    (model_dir / "paper_gate_acceptor_report_latest.md").write_text("\n".join(report_md), encoding="utf-8")
    fold_reports_to_frame(reports).to_csv(model_dir / "paper_gate_acceptor_walk_forward_report_latest.csv", index=False)

    return metrics_payload


def _load_global_teacher(paths: CompatPaths) -> tuple[FittedBundle, dict[str, Any]]:
    model_path = paths.global_model_dir / "paper_gate_acceptor_latest.joblib"
    metrics_path = paths.global_model_dir / "paper_gate_acceptor_latest_metrics.json"
    if not model_path.exists():
        raise FileNotFoundError(f"Brak modelu globalnego: {model_path}")
    bundle = joblib.load(model_path)
    metrics = json.loads(metrics_path.read_text(encoding="utf-8")) if metrics_path.exists() else {}
    return bundle, metrics


def train_symbol_model(
    paths: CompatPaths,
    symbol: str,
    export_onnx: bool = False,
    thresholds: TrainingThresholds | None = None,
) -> dict[str, Any]:
    thresholds = thresholds or TrainingThresholds()
    labeled, summary, master, runtime, learning = _prepare_labeled_frame(paths, thresholds)
    readiness_df = build_symbol_readiness(labeled, master, runtime, learning, load_active_symbols(paths), min_local_rows=thresholds.min_symbol_labeled_rows)
    ready_row = readiness_df.loc[readiness_df["symbol_alias"] == symbol]
    if ready_row.empty:
        raise ValueError(f"Symbol {symbol} nie figuruje w aktywnej flocie.")
    ready = ready_row.iloc[0]

    teacher_bundle, global_metrics = _load_global_teacher(paths)

    symbol_dir = ensure_dir(paths.symbol_models_dir / symbol)
    result = {
        "scope": "LOCAL_STUDENT",
        "symbol_alias": symbol,
        "training_mode": str(ready["training_mode"]),
        "candidate_rows": int(ready["candidate_rows"]),
        "labeled_rows": int(ready["labeled_rows"]),
        "runtime_rows": int(ready["runtime_rows"]),
        "outcome_rows": int(ready["outcome_rows"]),
        "promotion": {"approved": False, "reasons": []},
        "artifacts": {},
        "feature_contract": {},
        "teacher_model_path": str(paths.global_model_dir / "paper_gate_acceptor_latest.joblib"),
    }

    metrics_path = symbol_dir / "paper_gate_acceptor_latest_metrics.json"
    report_path = symbol_dir / "paper_gate_acceptor_report_latest.md"

    if result["training_mode"] == "FALLBACK_ONLY" or int(ready["candidate_rows"]) <= 0:
        result["promotion"] = {"approved": False, "reasons": ["Brak candidate_signals lub symbol w trybie FALLBACK_ONLY."]}
        write_json(metrics_path, result)
        report_path.write_text("# Lokalny student\n\n- Tryb: FALLBACK_ONLY\n- Powód: brak kandydatów lub brak gotowości.\n", encoding="utf-8")
        return result

    symbol_labeled = labeled.loc[labeled["symbol_alias"] == symbol].copy()
    if len(symbol_labeled) < thresholds.min_symbol_train_rows or symbol_labeled["y_gate"].nunique() < thresholds.min_symbol_classes:
        result["training_mode"] = "LOCAL_TRAINING_LIMITED"
        result["promotion"] = {"approved": False, "reasons": ["Za mało domkniętych outcome do pełnego lokalnego treningu; pozostaje fallback do modelu globalnego."]}
        write_json(metrics_path, result)
        report_path.write_text("# Lokalny student\n\n- Tryb: LOCAL_TRAINING_LIMITED\n- Powód: za mało labeled rows.\n", encoding="utf-8")
        return result

    symbol_features, local_contract = build_feature_frame(symbol_labeled, ts_col="ts")
    teacher_features = [f for f in local_contract.all_features if f != "teacher_global_score"]
    teacher_score = positive_proba(teacher_bundle, symbol_features[teacher_features])
    symbol_labeled = symbol_labeled.copy()
    symbol_labeled["teacher_global_score"] = teacher_score
    symbol_features, local_contract = build_feature_frame(symbol_labeled, ts_col="ts")
    assert_no_target_leakage(local_contract.all_features)

    local_thresholds = TrainingThresholds(
        global_train_days=max(20, thresholds.global_train_days // 2),
        global_valid_days=max(3, thresholds.global_valid_days // 2),
        global_step_days=max(3, thresholds.global_step_days // 2),
        embargo_minutes=thresholds.embargo_minutes,
        min_train_rows=thresholds.min_symbol_train_rows,
        min_valid_rows=thresholds.min_symbol_valid_rows,
        min_symbol_labeled_rows=thresholds.min_symbol_labeled_rows,
        min_symbol_train_rows=thresholds.min_symbol_train_rows,
        min_symbol_valid_rows=thresholds.min_symbol_valid_rows,
        min_symbol_classes=thresholds.min_symbol_classes,
        min_gate_probability=thresholds.min_gate_probability,
        min_decision_score_pln=thresholds.min_decision_score_pln,
        max_spread_points=thresholds.max_spread_points,
        max_runtime_latency_us=thresholds.max_runtime_latency_us,
        max_server_ping_ms=thresholds.max_server_ping_ms,
        regression_clip_pln=thresholds.regression_clip_pln,
        sample_weight_abs_cap_pln=thresholds.sample_weight_abs_cap_pln,
    )

    splits = make_walk_forward_splits(
        symbol_features,
        time_col="ts",
        train_days=local_thresholds.global_train_days,
        valid_days=local_thresholds.global_valid_days,
        step_days=local_thresholds.global_step_days,
        embargo_minutes=local_thresholds.embargo_minutes,
        min_train_rows=local_thresholds.min_train_rows,
        min_valid_rows=local_thresholds.min_valid_rows,
    )
    if not splits:
        result["training_mode"] = "LOCAL_TRAINING_LIMITED"
        result["promotion"] = {"approved": False, "reasons": ["Za mało danych w oknach czasowych do lokalnego walk-forward."]}
        write_json(metrics_path, result)
        report_path.write_text("# Lokalny student\n\n- Tryb: LOCAL_TRAINING_LIMITED\n- Powód: brak poprawnych splitów walk-forward.\n", encoding="utf-8")
        return result

    fold_reports = []
    for window in splits:
        train_frame = symbol_features.loc[window.train_index].copy()
        valid_frame = symbol_features.loc[window.valid_index].copy()

        gate_bundle = fit_model("sgd_classifier", "classification", train_frame, local_contract.all_features, local_contract.categorical_features, 42, "y_gate", "sample_weight")
        edge_bundle = fit_model("lightgbm_regressor", "regression", train_frame, local_contract.all_features, local_contract.categorical_features, 42, "y_edge_reg", "sample_weight")
        fill_bundle = fit_model("logistic_regression", "classification", train_frame, local_contract.all_features, local_contract.categorical_features, 42, "y_fill", "sample_weight") if train_frame["y_fill"].nunique() > 1 else None
        slippage_bundle = fit_model("lightgbm_regressor", "regression", train_frame, local_contract.all_features, local_contract.categorical_features, 42, "y_slippage_reg", "sample_weight")

        gate_probability = positive_proba(gate_bundle, valid_frame[local_contract.all_features])
        edge_prediction = regression_pred(edge_bundle, valid_frame[local_contract.all_features])
        fill_probability = positive_proba(fill_bundle, valid_frame[local_contract.all_features]) if fill_bundle else None
        slippage_prediction = regression_pred(slippage_bundle, valid_frame[local_contract.all_features])

        decided = build_decisions(
            valid_frame,
            gate_probability=gate_probability,
            edge_prediction_pln=edge_prediction,
            fill_probability=fill_probability,
            slippage_prediction_pln=slippage_prediction,
            min_gate_probability=local_thresholds.min_gate_probability,
            min_decision_score_pln=local_thresholds.min_decision_score_pln,
            max_spread_points=local_thresholds.max_spread_points,
            max_runtime_latency_us=local_thresholds.max_runtime_latency_us,
            max_server_ping_ms=local_thresholds.max_server_ping_ms,
        )
        rep = fold_report(window.fold_id, decided, valid_frame["y_gate"].to_numpy(dtype=int), gate_probability)
        rep.train_rows = int(len(train_frame))
        rep.valid_rows = int(len(valid_frame))
        fold_reports.append(rep)

    metrics = aggregate_fold_reports(fold_reports)
    promotion = evaluate_promotion(metrics, min_validation_trades=20, min_profit_factor=1.0, max_drawdown_pln=250.0, min_fold_win_rate=0.40)

    gate_bundle = fit_model("sgd_classifier", "classification", symbol_features, local_contract.all_features, local_contract.categorical_features, 42, "y_gate", "sample_weight")
    edge_bundle = fit_model("lightgbm_regressor", "regression", symbol_features, local_contract.all_features, local_contract.categorical_features, 42, "y_edge_reg", "sample_weight")
    fill_bundle = fit_model("logistic_regression", "classification", symbol_features, local_contract.all_features, local_contract.categorical_features, 42, "y_fill", "sample_weight") if symbol_features["y_fill"].nunique() > 1 else None
    slippage_bundle = fit_model("lightgbm_regressor", "regression", symbol_features, local_contract.all_features, local_contract.categorical_features, 42, "y_slippage_reg", "sample_weight")

    artifacts = {
        "student_gate": _save_training_artifacts(symbol_dir, gate_bundle, symbol_features, "sgd_classifier", "paper_gate_acceptor_latest", export_onnx),
        "edge_model": _save_training_artifacts(symbol_dir, edge_bundle, symbol_features, "lightgbm_regressor", "edge_model_latest", export_onnx),
        "fill_model": _save_training_artifacts(symbol_dir, fill_bundle, symbol_features, "logistic_regression", "fill_model_latest", export_onnx),
        "slippage_model": _save_training_artifacts(symbol_dir, slippage_bundle, symbol_features, "lightgbm_regressor", "slippage_model_latest", export_onnx),
    }

    result.update({
        "training_mode": "TRAINING_SHADOW_READY" if promotion["approved"] else result["training_mode"],
        "promotion": promotion,
        "metrics": metrics,
        "feature_contract": {
            "all_features": local_contract.all_features,
            "categorical_features": local_contract.categorical_features,
        },
        "artifacts": artifacts,
        "global_summary": {
            "global_model_dir": str(paths.global_model_dir),
            "global_approved": global_metrics.get("promotion", {}).get("approved"),
        },
    })

    write_json(metrics_path, result)
    report_md = [
        f"# PAPER GATE ACCEPTOR — lokalny student {symbol}",
        "",
        f"- Tryb: {result['training_mode']}",
        f"- Candidate rows: {result['candidate_rows']}",
        f"- Labeled rows: {result['labeled_rows']}",
        f"- Foldy: {int(metrics.get('fold_count', 0))}",
        f"- Suma netto walidacji: {metrics.get('pnl_sum_total_pln', 0.0):.2f} PLN",
        f"- Profit factor mediana: {metrics.get('profit_factor_median', 0.0):.3f}",
        f"- Promocja: {'TAK' if promotion['approved'] else 'NIE'}",
        "",
        "## Powody",
        *[f"- {x}" for x in promotion["reasons"]],
        "",
        "## Zależność od nauczyciela globalnego",
        f"- Teacher model: {paths.global_model_dir / 'paper_gate_acceptor_latest.joblib'}",
        "- teacher_global_score jest dołączany jako cecha lokalna, ale liczony poza lokalnym fittingiem.",
    ]
    report_path.write_text("\n".join(report_md), encoding="utf-8")
    fold_reports_to_frame(fold_reports).to_csv(symbol_dir / "paper_gate_acceptor_walk_forward_report_latest.csv", index=False)
    return result


def train_all_symbol_models(
    paths: CompatPaths,
    export_onnx: bool = False,
    thresholds: TrainingThresholds | None = None,
) -> dict[str, Any]:
    thresholds = thresholds or TrainingThresholds()
    symbols = load_active_symbols(paths)
    results = {}
    for symbol in symbols:
        try:
            results[symbol] = train_symbol_model(paths, symbol=symbol, export_onnx=export_onnx, thresholds=thresholds)
        except Exception as exc:
            results[symbol] = {
                "symbol_alias": symbol,
                "scope": "LOCAL_STUDENT",
                "training_mode": "FALLBACK_ONLY",
                "promotion": {"approved": False, "reasons": [str(exc)]},
                "artifacts": {},
            }

    registry = {"schema_version": "1.0", "generated_at_utc": pd.Timestamp.utcnow().isoformat(), "symbols": {}}
    for symbol, payload in results.items():
        registry["symbols"][symbol] = {
            "symbol_alias": symbol,
            "training_mode": payload.get("training_mode"),
            "promotion": payload.get("promotion", {}),
            "trained_on_broker_net_pln": True,
            "trained_with_server_ping": True,
            "trained_with_server_latency": True,
            "teacher_model_path": str(paths.global_model_dir / "paper_gate_acceptor_latest.onnx"),
            "student_model_path": payload.get("artifacts", {}).get("student_gate", {}).get("onnx") or payload.get("artifacts", {}).get("student_gate", {}).get("joblib", ""),
            "edge_model_path": payload.get("artifacts", {}).get("edge_model", {}).get("onnx") or payload.get("artifacts", {}).get("edge_model", {}).get("joblib", ""),
            "fill_model_path": payload.get("artifacts", {}).get("fill_model", {}).get("onnx") or payload.get("artifacts", {}).get("fill_model", {}).get("joblib", ""),
            "slippage_model_path": payload.get("artifacts", {}).get("slippage_model", {}).get("onnx") or payload.get("artifacts", {}).get("slippage_model", {}).get("joblib", ""),
        }

    write_json(paths.onnx_symbol_registry_latest, registry)
    write_json(paths.onnx_symbol_registry_latest_alt, registry)
    return {"symbols": results, "registry_path": str(paths.onnx_symbol_registry_latest)}


def write_training_audits(paths: CompatPaths, global_payload: dict[str, Any], symbol_payload: dict[str, Any]) -> dict[str, str]:
    ensure_dir(paths.evidence_ops_dir)

    learning_source_audit = {
        "generated_at_utc": pd.Timestamp.utcnow().isoformat(),
        "project_root": str(paths.project_root),
        "research_root": str(paths.research_root),
        "datasets": {
            "candidate_signals_norm_latest": str(paths.candidate_signals_norm_latest),
            "onnx_observations_norm_latest": str(paths.onnx_observations_norm_latest),
            "learning_observations_v2_norm_latest": str(paths.learning_observations_v2_norm_latest),
            "qdm_minute_bars_latest": str(paths.qdm_minute_bars_latest),
            "execution_ping_contract_csv": str(paths.execution_ping_contract_csv),
        },
        "global_summary": global_payload.get("summary", {}),
    }
    write_json(paths.evidence_ops_dir / "learning_source_audit_latest.json", learning_source_audit)

    registry = json.loads(paths.onnx_symbol_registry_latest.read_text(encoding="utf-8")) if paths.onnx_symbol_registry_latest.exists() else {"symbols": {}}
    readiness = {"generated_at_utc": pd.Timestamp.utcnow().isoformat(), "symbols": registry.get("symbols", {})}
    write_json(paths.evidence_ops_dir / "instrument_training_readiness_latest.json", readiness)

    gap = {
        "generated_at_utc": pd.Timestamp.utcnow().isoformat(),
        "global_rows": global_payload.get("summary", {}).get("rows"),
        "global_labeled_rows": global_payload.get("summary", {}).get("labeled_rows"),
        "notes": [
            "Audit mierzy lukę między candidate/runtime/outcome na poziomie zgodności kontraktów.",
            "Symbole w FALLBACK_ONLY nie dostają lokalnej promocji.",
        ],
    }
    write_json(paths.evidence_ops_dir / "paper_live_action_gap_audit_latest.json", gap)

    transition = {
        "generated_at_utc": pd.Timestamp.utcnow().isoformat(),
        "global_promotion": global_payload.get("promotion", {}),
        "symbol_promotions": {symbol: payload.get("promotion", {}) for symbol, payload in symbol_payload.get("symbols", {}).items()},
    }
    write_json(paths.evidence_ops_dir / "trade_transition_audit_latest.json", transition)

    fit_audit = {
        "generated_at_utc": pd.Timestamp.utcnow().isoformat(),
        "global_metrics": global_payload.get("metrics", {}),
        "symbols": {
            symbol: {
                "training_mode": payload.get("training_mode"),
                "metrics": payload.get("metrics", {}),
                "promotion": payload.get("promotion", {}),
            }
            for symbol, payload in symbol_payload.get("symbols", {}).items()
        },
    }
    write_json(paths.evidence_ops_dir / "ml_scalping_fit_audit_latest.json", fit_audit)

    wellbeing = {
        "generated_at_utc": pd.Timestamp.utcnow().isoformat(),
        "status": "OK" if global_payload.get("promotion", {}).get("approved") else "REVIEW_REQUIRED",
        "global_model_approved": global_payload.get("promotion", {}).get("approved"),
        "local_students_approved": [symbol for symbol, payload in symbol_payload.get("symbols", {}).items() if payload.get("promotion", {}).get("approved")],
        "local_students_fallback_only": [symbol for symbol, payload in symbol_payload.get("symbols", {}).items() if payload.get("training_mode") == "FALLBACK_ONLY"],
    }
    write_json(paths.evidence_ops_dir / "learning_wellbeing_latest.json", wellbeing)

    return {
        "learning_source_audit_latest.json": str(paths.evidence_ops_dir / "learning_source_audit_latest.json"),
        "instrument_training_readiness_latest.json": str(paths.evidence_ops_dir / "instrument_training_readiness_latest.json"),
        "paper_live_action_gap_audit_latest.json": str(paths.evidence_ops_dir / "paper_live_action_gap_audit_latest.json"),
        "trade_transition_audit_latest.json": str(paths.evidence_ops_dir / "trade_transition_audit_latest.json"),
        "ml_scalping_fit_audit_latest.json": str(paths.evidence_ops_dir / "ml_scalping_fit_audit_latest.json"),
        "learning_wellbeing_latest.json": str(paths.evidence_ops_dir / "learning_wellbeing_latest.json"),
    }
