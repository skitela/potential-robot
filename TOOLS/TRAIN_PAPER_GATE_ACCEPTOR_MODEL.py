#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import duckdb
import joblib
import numpy as np
import onnxruntime as ort
import pandas as pd
from onnx import save_model
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType, Int64TensorType, StringTensorType
from sklearn.compose import ColumnTransformer
from sklearn.linear_model import SGDClassifier
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    balanced_accuracy_score,
    log_loss,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train first offline helper model for microbot paper-gate acceptance.")
    parser.add_argument("--db-path", default=r"C:\TRADING_DATA\RESEARCH\microbot_research.duckdb")
    parser.add_argument("--candidate-parquet-path", default=r"C:\TRADING_DATA\RESEARCH\datasets\candidate_signals_latest.parquet")
    parser.add_argument("--qdm-parquet-path", default=r"C:\TRADING_DATA\RESEARCH\datasets\qdm_minute_bars_latest.parquet")
    parser.add_argument("--output-root", default=r"C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor")
    parser.add_argument("--holdout-ratio", type=float, default=0.2)
    parser.add_argument("--sample-limit", type=int, default=0, help="Optional cap for training rows; 0 keeps all rows.")
    parser.add_argument("--symbol-filter", default="", help="Optional symbol alias filter for per-instrument training.")
    parser.add_argument("--artifact-stem", default="paper_gate_acceptor_latest", help="Base artifact name without extension.")
    parser.add_argument("--teacher-model-path", default="", help="Optional global teacher pipeline path for per-instrument training.")
    parser.add_argument("--min-rows", type=int, default=10000, help="Minimum rows required to train the model.")
    parser.add_argument("--min-positive-rows", type=int, default=500, help="Minimum accepted=1 rows required to train the model.")
    parser.add_argument("--min-negative-rows", type=int, default=500, help="Minimum accepted=0 rows required to train the model.")
    return parser.parse_args()


FEATURE_CATEGORICAL = [
    "symbol",
    "setup_type",
    "market_regime",
    "spread_regime",
    "confidence_bucket",
    "candle_bias",
    "candle_quality_grade",
    "renko_bias",
    "renko_quality_grade",
]

FEATURE_NUMERIC_FLOAT = [
    "score",
    "confidence_score",
    "candle_score",
    "renko_score",
    "spread_points",
    "qdm_spread_mean",
    "qdm_spread_max",
    "qdm_mid_range_1m",
    "qdm_mid_return_1m",
]

FEATURE_NUMERIC_INT = [
    "renko_run_length",
    "renko_reversal_flag",
    "qdm_tick_count",
    "qdm_data_present",
]

FEATURE_COLUMNS = FEATURE_CATEGORICAL + FEATURE_NUMERIC_FLOAT + FEATURE_NUMERIC_INT


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def load_dataset(
    db_path: Path,
    candidate_parquet_path: Path,
    qdm_parquet_path: Path,
    sample_limit: int,
    symbol_filter: str,
) -> tuple[pd.DataFrame, str]:
    base_query = """
        SELECT
            c.ts,
            c.symbol,
            c.accepted,
            c.setup_type,
            c.side,
            c.score,
            c.confidence_score,
            c.market_regime,
            c.spread_regime,
            c.confidence_bucket,
            c.candle_bias,
            c.candle_quality_grade,
            c.candle_score,
            c.renko_bias,
            c.renko_quality_grade,
            c.renko_score,
            c.renko_run_length,
            c.renko_reversal_flag,
            c.spread_points,
            {qdm_select}
        FROM {candidate_source} c
        {qdm_join}
        WHERE c.stage = 'EVALUATED'
          AND c.accepted IS NOT NULL
          AND c.reason_code IN ('PAPER_SCORE_GATE', 'SCORE_BELOW_TRIGGER')
          {symbol_clause}
        ORDER BY c.ts
    """

    source_label = ""
    if candidate_parquet_path.exists():
        con = duckdb.connect(database=":memory:")
        qdm_available = qdm_parquet_path.exists()
        source_label = "PARQUET"
        qdm_join = (
            """
                LEFT JOIN read_parquet(?) q
                  ON q.symbol_alias = c.symbol
                 AND q.bar_minute = date_trunc('minute', epoch_ms(CAST(c.ts AS BIGINT) * 1000))
            """
            if qdm_available
            else ""
        )
        query = base_query.format(
            candidate_source="read_parquet(?)",
            qdm_select=(
                """
                    COALESCE(q.tick_count, 0)::BIGINT AS qdm_tick_count,
                    COALESCE(q.spread_mean, 0.0)::DOUBLE AS qdm_spread_mean,
                    COALESCE(q.spread_max, 0.0)::DOUBLE AS qdm_spread_max,
                    COALESCE(q.mid_range_1m, 0.0)::DOUBLE AS qdm_mid_range_1m,
                    COALESCE(q.mid_return_1m, 0.0)::DOUBLE AS qdm_mid_return_1m,
                    CASE WHEN q.bar_minute IS NULL THEN 0 ELSE 1 END::BIGINT AS qdm_data_present
                """
                if qdm_available
                else """
                    0::BIGINT AS qdm_tick_count,
                    0.0::DOUBLE AS qdm_spread_mean,
                    0.0::DOUBLE AS qdm_spread_max,
                    0.0::DOUBLE AS qdm_mid_range_1m,
                    0.0::DOUBLE AS qdm_mid_return_1m,
                    0::BIGINT AS qdm_data_present
                """
            ),
            qdm_join=qdm_join,
            symbol_clause=("AND c.symbol = ?" if symbol_filter else ""),
        )
        if sample_limit > 0:
            query += f" LIMIT {int(sample_limit)}"
        params: list[str] = [str(candidate_parquet_path)]
        if qdm_available:
            params.append(str(qdm_parquet_path))
        if symbol_filter:
            params.append(symbol_filter)
        df = con.execute(query, params).df()
        con.close()
        return df, source_label

    with duckdb.connect(str(db_path), read_only=True) as con:
        source_label = "DUCKDB"
        qdm_available = bool(
            con.execute(
                """
                SELECT 1
                FROM information_schema.tables
                WHERE table_name = 'qdm_minute_bars'
                LIMIT 1
                """
            ).fetchone()
        )

        if qdm_available:
            query = base_query.format(
                candidate_source="candidate_signals",
                qdm_select="""
                    COALESCE(q.tick_count, 0)::BIGINT AS qdm_tick_count,
                    COALESCE(q.spread_mean, 0.0)::DOUBLE AS qdm_spread_mean,
                    COALESCE(q.spread_max, 0.0)::DOUBLE AS qdm_spread_max,
                    COALESCE(q.mid_range_1m, 0.0)::DOUBLE AS qdm_mid_range_1m,
                    COALESCE(q.mid_return_1m, 0.0)::DOUBLE AS qdm_mid_return_1m,
                    CASE WHEN q.bar_minute IS NULL THEN 0 ELSE 1 END::BIGINT AS qdm_data_present
                """,
                qdm_join="""
                    LEFT JOIN qdm_minute_bars q
                      ON q.symbol_alias = c.symbol
                     AND q.bar_minute = date_trunc('minute', epoch_ms(CAST(c.ts AS BIGINT) * 1000))
                """,
                symbol_clause=("AND c.symbol = ?" if symbol_filter else ""),
            )
        else:
            query = base_query.format(
                candidate_source="candidate_signals",
                qdm_select="""
                    0::BIGINT AS qdm_tick_count,
                    0.0::DOUBLE AS qdm_spread_mean,
                    0.0::DOUBLE AS qdm_spread_max,
                    0.0::DOUBLE AS qdm_mid_range_1m,
                    0.0::DOUBLE AS qdm_mid_return_1m,
                    0::BIGINT AS qdm_data_present
                """,
                qdm_join="",
                symbol_clause=("AND c.symbol = ?" if symbol_filter else ""),
            )

        if sample_limit > 0:
            query += f" LIMIT {int(sample_limit)}"

        if symbol_filter:
            df = con.execute(query, [symbol_filter]).df()
        else:
            df = con.execute(query).df()

    return df, source_label


def build_qdm_coverage(df: pd.DataFrame) -> dict[str, Any]:
    if df.empty or "qdm_data_present" not in df.columns:
        return {
            "rows_with_qdm": 0,
            "row_coverage_ratio": 0.0,
            "symbols_with_qdm": [],
            "symbol_coverage": [],
        }

    rows_with_qdm = int((df["qdm_data_present"] > 0).sum())
    symbol_cov = (
        df.groupby("symbol", dropna=False)["qdm_data_present"]
        .agg(["count", "sum"])
        .reset_index()
        .rename(columns={"count": "rows_total", "sum": "rows_with_qdm"})
    )
    symbol_cov["coverage_ratio"] = symbol_cov["rows_with_qdm"] / symbol_cov["rows_total"].replace(0, 1)
    symbol_cov = symbol_cov.sort_values(["coverage_ratio", "rows_with_qdm"], ascending=[False, False])

    return {
        "rows_with_qdm": rows_with_qdm,
        "row_coverage_ratio": float(rows_with_qdm / len(df.index)),
        "symbols_with_qdm": [str(v) for v in symbol_cov.loc[symbol_cov["rows_with_qdm"] > 0, "symbol"].tolist()],
        "symbol_coverage": symbol_cov.head(20).to_dict(orient="records"),
    }


def normalize_frame(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    for col in FEATURE_CATEGORICAL:
        if col in df.columns:
            df[col] = df[col].fillna("UNKNOWN").astype(str)
    for col in FEATURE_NUMERIC_FLOAT:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce").astype("float32")
    for col in FEATURE_NUMERIC_INT:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0).astype("int64")
    df["accepted"] = pd.to_numeric(df["accepted"], errors="coerce").fillna(0).astype("int64")
    df["ts"] = pd.to_numeric(df["ts"], errors="coerce").fillna(0).astype("int64")
    return df


def build_pipeline(
    categorical_features: list[str],
    numeric_float_features: list[str],
    numeric_int_features: list[str],
) -> Pipeline:
    categorical_pipeline = OneHotEncoder(handle_unknown="ignore")
    numeric_pipeline = StandardScaler()
    integer_pipeline = StandardScaler()

    preprocessor = ColumnTransformer(
        transformers=[
            ("cat", categorical_pipeline, categorical_features),
            ("num_float", numeric_pipeline, numeric_float_features),
            ("num_int", integer_pipeline, numeric_int_features),
        ]
    )

    classifier = SGDClassifier(
        loss="log_loss",
        penalty="elasticnet",
        alpha=1e-5,
        l1_ratio=0.15,
        max_iter=30,
        tol=1e-4,
        random_state=42,
    )

    return Pipeline(
        steps=[
            ("preprocessor", preprocessor),
            ("model", classifier),
        ]
    )


def time_split(df: pd.DataFrame, holdout_ratio: float) -> tuple[pd.DataFrame, pd.DataFrame]:
    split_index = int(len(df.index) * (1.0 - holdout_ratio))
    split_index = max(1, min(split_index, len(df.index) - 1))
    train_df = df.iloc[:split_index].copy()
    test_df = df.iloc[split_index:].copy()
    return train_df, test_df


def evaluate(y_true: np.ndarray, y_pred: np.ndarray, y_score: np.ndarray) -> dict[str, float]:
    return {
        "accuracy": float(accuracy_score(y_true, y_pred)),
        "balanced_accuracy": float(balanced_accuracy_score(y_true, y_pred)),
        "precision": float(precision_score(y_true, y_pred, zero_division=0)),
        "recall": float(recall_score(y_true, y_pred, zero_division=0)),
        "roc_auc": float(roc_auc_score(y_true, y_score)),
        "average_precision": float(average_precision_score(y_true, y_score)),
        "log_loss": float(log_loss(y_true, np.vstack([1.0 - y_score, y_score]).T, labels=[0, 1])),
        "positive_rate_actual": float(np.mean(y_true)),
        "positive_rate_predicted": float(np.mean(y_pred)),
    }


def extract_top_features(pipeline: Pipeline, limit: int = 20) -> dict[str, list[dict[str, Any]]]:
    preprocessor: ColumnTransformer = pipeline.named_steps["preprocessor"]
    classifier: SGDClassifier = pipeline.named_steps["model"]
    feature_names = preprocessor.get_feature_names_out()
    coefs = classifier.coef_[0]
    order_pos = np.argsort(coefs)[-limit:][::-1]
    order_neg = np.argsort(coefs)[:limit]

    def rows(indices: np.ndarray) -> list[dict[str, Any]]:
        return [
            {
                "feature": str(feature_names[i]),
                "coefficient": float(coefs[i]),
            }
            for i in indices
        ]

    return {
        "positive": rows(order_pos),
        "negative": rows(order_neg),
    }


def build_initial_types(
    categorical_features: list[str],
    numeric_float_features: list[str],
    numeric_int_features: list[str],
) -> list[tuple[str, Any]]:
    initial_types: list[tuple[str, Any]] = []
    for name in categorical_features:
        initial_types.append((name, StringTensorType([None, 1])))
    for name in numeric_float_features:
        initial_types.append((name, FloatTensorType([None, 1])))
    for name in numeric_int_features:
        initial_types.append((name, Int64TensorType([None, 1])))
    return initial_types


def export_onnx_model(
    pipeline: Pipeline,
    output_path: Path,
    test_frame: pd.DataFrame,
    categorical_features: list[str],
    numeric_float_features: list[str],
    numeric_int_features: list[str],
) -> dict[str, Any]:
    initial_types = build_initial_types(categorical_features, numeric_float_features, numeric_int_features)
    options = {id(pipeline.named_steps["model"]): {"zipmap": False}}
    onx = convert_sklearn(pipeline, initial_types=initial_types, target_opset=17, options=options)
    save_model(onx, str(output_path))

    sample = test_frame.head(5).copy()
    inputs: dict[str, np.ndarray] = {}
    for col in categorical_features:
        inputs[col] = sample[[col]].astype(str).to_numpy()
    for col in numeric_float_features:
        inputs[col] = sample[[col]].astype(np.float32).to_numpy()
    for col in numeric_int_features:
        inputs[col] = sample[[col]].astype(np.int64).to_numpy()

    session = ort.InferenceSession(str(output_path), providers=["CPUExecutionProvider"])
    outputs = session.run(None, inputs)
    return {
        "onnx_path": str(output_path),
        "session_inputs": [i.name for i in session.get_inputs()],
        "session_outputs": [o.name for o in session.get_outputs()],
        "sample_output_rows": int(len(outputs[1])) if len(outputs) > 1 else int(len(outputs[0])),
    }


def markdown_report(metadata: dict[str, Any]) -> str:
    symbol_filter = metadata["dataset"].get("symbol_filter", "")
    scope_label = ("model per instrument" if symbol_filter else "model globalny")
    lines = [
        "# 146 MicroBot ML Offline First Model V1",
        "",
        "## Cel",
        "- pierwszy model pomocniczy offline dla `candidate -> paper gate`",
        "- bez ingerencji w runtime `MQL5`",
        "- z eksportem do `ONNX` pod przyszla integracje",
        f"- zakres: `{scope_label}`",
        "",
        "## Dane",
        f"- rekordy lacznie: `{metadata['dataset']['total_rows']}`",
        f"- train: `{metadata['dataset']['train_rows']}`",
        f"- holdout: `{metadata['dataset']['test_rows']}`",
        f"- dodatni target (`accepted=1`): `{metadata['dataset']['positive_rate']:.4f}`",
        f"- pokrycie `QDM`: `{metadata['dataset']['qdm_coverage']['row_coverage_ratio']:.4f}`",
        "",
        "## Metryki holdout",
    ]

    if symbol_filter:
        lines.insert(9, f"- symbol: `{symbol_filter}`")

    for key, value in metadata["metrics"].items():
        lines.append(f"- `{key}`: `{value:.6f}`")

    lines.extend(
        [
            "",
            "## Pokrycie QDM",
        ]
    )
    for row in metadata["dataset"]["qdm_coverage"]["symbol_coverage"][:10]:
        lines.append(
            f"- `{row['symbol']}` -> coverage `{row['coverage_ratio']:.4f}` "
            f"({int(row['rows_with_qdm'])}/{int(row['rows_total'])})"
        )

    lines.extend(
        [
            "",
            "## Najmocniejsze cechy dodatnie",
        ]
    )
    for row in metadata["top_features"]["positive"]:
        lines.append(f"- `{row['feature']}` -> `{row['coefficient']:.6f}`")

    lines.extend(
        [
            "",
            "## Najmocniejsze cechy ujemne",
        ]
    )
    for row in metadata["top_features"]["negative"]:
        lines.append(f"- `{row['feature']}` -> `{row['coefficient']:.6f}`")

    lines.extend(
        [
            "",
            "## Artefakty",
            f"- sklearn pipeline: `{metadata['artifacts']['joblib_path']}`",
            f"- ONNX: `{metadata['artifacts']['onnx_path']}`",
            f"- metrics json: `{metadata['artifacts']['metrics_path']}`",
        ]
    )
    return "\n".join(lines) + "\n"


def attach_teacher_signal(
    dataset: pd.DataFrame,
    teacher_model_path: Path,
) -> tuple[pd.DataFrame, bool]:
    if not teacher_model_path.exists():
        return dataset, False

    teacher_pipeline = joblib.load(teacher_model_path)
    teacher_x = dataset[FEATURE_COLUMNS]
    teacher_score = teacher_pipeline.predict_proba(teacher_x)[:, 1].astype("float32")
    enriched = dataset.copy()
    enriched["teacher_global_score"] = teacher_score
    return enriched, True


def main() -> int:
    args = parse_args()
    db_path = Path(args.db_path)
    candidate_parquet_path = Path(args.candidate_parquet_path)
    qdm_parquet_path = Path(args.qdm_parquet_path)
    output_root = ensure_dir(Path(args.output_root))
    symbol_filter = args.symbol_filter.strip().upper()
    teacher_model_path = Path(args.teacher_model_path) if args.teacher_model_path.strip() else None
    categorical_features = [name for name in FEATURE_CATEGORICAL if not (symbol_filter and name == "symbol")]
    numeric_float_features = list(FEATURE_NUMERIC_FLOAT)
    numeric_int_features = list(FEATURE_NUMERIC_INT)

    dataset, source_kind = load_dataset(
        db_path=db_path,
        candidate_parquet_path=candidate_parquet_path,
        qdm_parquet_path=qdm_parquet_path,
        sample_limit=args.sample_limit,
        symbol_filter=symbol_filter,
    )
    dataset = normalize_frame(dataset)
    if dataset.empty:
        raise RuntimeError(f"No training rows found for scope={symbol_filter or 'GLOBAL'}")

    teacher_feature_enabled = False
    if teacher_model_path is not None:
        dataset, teacher_feature_enabled = attach_teacher_signal(dataset, teacher_model_path)
        if teacher_feature_enabled:
            numeric_float_features.append("teacher_global_score")

    feature_columns = categorical_features + numeric_float_features + numeric_int_features

    total_rows = int(len(dataset.index))
    positive_rows = int((dataset["accepted"] == 1).sum())
    negative_rows = int((dataset["accepted"] == 0).sum())
    if total_rows < args.min_rows:
        raise RuntimeError(
            f"Not enough rows to train model for scope={symbol_filter or 'GLOBAL'}: {total_rows} < {args.min_rows}"
        )
    if positive_rows < args.min_positive_rows:
        raise RuntimeError(
            f"Not enough positive rows to train model for scope={symbol_filter or 'GLOBAL'}: {positive_rows} < {args.min_positive_rows}"
        )
    if negative_rows < args.min_negative_rows:
        raise RuntimeError(
            f"Not enough negative rows to train model for scope={symbol_filter or 'GLOBAL'}: {negative_rows} < {args.min_negative_rows}"
        )

    train_df, test_df = time_split(dataset, args.holdout_ratio)
    x_train = train_df[feature_columns]
    y_train = train_df["accepted"].to_numpy()
    x_test = test_df[feature_columns]
    y_test = test_df["accepted"].to_numpy()

    pipeline = build_pipeline(categorical_features, numeric_float_features, numeric_int_features)
    pipeline.fit(x_train, y_train)

    y_score = pipeline.predict_proba(x_test)[:, 1]
    y_pred = (y_score >= 0.5).astype(int)
    metrics = evaluate(y_test, y_pred, y_score)
    top_features = extract_top_features(pipeline)

    artifact_stem = args.artifact_stem.strip() or "paper_gate_acceptor_latest"
    joblib_path = output_root / f"{artifact_stem}.joblib"
    onnx_path = output_root / f"{artifact_stem}.onnx"
    metrics_path = output_root / f"{artifact_stem}_metrics.json"
    report_path = output_root / f"{artifact_stem}_report.md"

    joblib.dump(pipeline, joblib_path)
    onnx_info = export_onnx_model(
        pipeline,
        onnx_path,
        x_test,
        categorical_features,
        numeric_float_features,
        numeric_int_features,
    )

    metadata: dict[str, Any] = {
        "dataset": {
            "db_path": str(db_path),
            "candidate_parquet_path": str(candidate_parquet_path),
            "qdm_parquet_path": str(qdm_parquet_path),
            "source_kind": source_kind,
            "symbol_filter": symbol_filter,
            "scope": ("SYMBOL" if symbol_filter else "GLOBAL"),
            "total_rows": total_rows,
            "train_rows": int(len(train_df.index)),
            "test_rows": int(len(test_df.index)),
            "positive_rate": float(dataset["accepted"].mean()),
            "positive_rows": positive_rows,
            "negative_rows": negative_rows,
            "ts_min": int(dataset["ts"].min()),
            "ts_max": int(dataset["ts"].max()),
            "qdm_coverage": build_qdm_coverage(dataset),
        },
        "features": {
            "categorical": categorical_features,
            "numeric_float": numeric_float_features,
            "numeric_int": numeric_int_features,
            "teacher_feature_enabled": teacher_feature_enabled,
        },
        "metrics": metrics,
        "top_features": top_features,
        "onnx_info": onnx_info,
        "teacher": {
            "enabled": teacher_feature_enabled,
            "model_path": (str(teacher_model_path) if teacher_model_path is not None else ""),
        },
        "artifacts": {
            "joblib_path": str(joblib_path),
            "onnx_path": str(onnx_path),
            "metrics_path": str(metrics_path),
            "report_path": str(report_path),
        },
    }

    metrics_path.write_text(json.dumps(metadata, indent=2, ensure_ascii=True), encoding="utf-8")
    report_path.write_text(markdown_report(metadata), encoding="utf-8")

    print(json.dumps(metadata, indent=2, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
