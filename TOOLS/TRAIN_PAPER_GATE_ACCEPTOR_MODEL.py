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
    parser.add_argument("--output-root", default=r"C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor")
    parser.add_argument("--holdout-ratio", type=float, default=0.2)
    parser.add_argument("--sample-limit", type=int, default=0, help="Optional cap for training rows; 0 keeps all rows.")
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
]

FEATURE_NUMERIC_INT = [
    "renko_run_length",
    "renko_reversal_flag",
]

FEATURE_COLUMNS = FEATURE_CATEGORICAL + FEATURE_NUMERIC_FLOAT + FEATURE_NUMERIC_INT


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def load_dataset(db_path: Path, sample_limit: int) -> pd.DataFrame:
    query = """
        SELECT
            ts,
            symbol,
            accepted,
            setup_type,
            side,
            score,
            confidence_score,
            market_regime,
            spread_regime,
            confidence_bucket,
            candle_bias,
            candle_quality_grade,
            candle_score,
            renko_bias,
            renko_quality_grade,
            renko_score,
            renko_run_length,
            renko_reversal_flag,
            spread_points
        FROM candidate_signals
        WHERE stage = 'EVALUATED'
          AND accepted IS NOT NULL
          AND reason_code IN ('PAPER_SCORE_GATE', 'SCORE_BELOW_TRIGGER')
        ORDER BY ts
    """

    if sample_limit > 0:
        query += f" LIMIT {int(sample_limit)}"

    with duckdb.connect(str(db_path), read_only=True) as con:
        df = con.execute(query).df()

    return df


def normalize_frame(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    for col in FEATURE_CATEGORICAL:
        df[col] = df[col].fillna("UNKNOWN").astype(str)
    for col in FEATURE_NUMERIC_FLOAT:
        df[col] = pd.to_numeric(df[col], errors="coerce").astype("float32")
    for col in FEATURE_NUMERIC_INT:
        df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0).astype("int64")
    df["accepted"] = pd.to_numeric(df["accepted"], errors="coerce").fillna(0).astype("int64")
    df["ts"] = pd.to_numeric(df["ts"], errors="coerce").fillna(0).astype("int64")
    return df


def build_pipeline() -> Pipeline:
    categorical_pipeline = OneHotEncoder(handle_unknown="ignore")
    numeric_pipeline = StandardScaler()
    integer_pipeline = StandardScaler()

    preprocessor = ColumnTransformer(
        transformers=[
            ("cat", categorical_pipeline, FEATURE_CATEGORICAL),
            ("num_float", numeric_pipeline, FEATURE_NUMERIC_FLOAT),
            ("num_int", integer_pipeline, FEATURE_NUMERIC_INT),
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


def build_initial_types() -> list[tuple[str, Any]]:
    initial_types: list[tuple[str, Any]] = []
    for name in FEATURE_CATEGORICAL:
        initial_types.append((name, StringTensorType([None, 1])))
    for name in FEATURE_NUMERIC_FLOAT:
        initial_types.append((name, FloatTensorType([None, 1])))
    for name in FEATURE_NUMERIC_INT:
        initial_types.append((name, Int64TensorType([None, 1])))
    return initial_types


def export_onnx_model(pipeline: Pipeline, output_path: Path, test_frame: pd.DataFrame) -> dict[str, Any]:
    initial_types = build_initial_types()
    options = {id(pipeline.named_steps["model"]): {"zipmap": False}}
    onx = convert_sklearn(pipeline, initial_types=initial_types, target_opset=17, options=options)
    save_model(onx, str(output_path))

    sample = test_frame.head(5).copy()
    inputs: dict[str, np.ndarray] = {}
    for col in FEATURE_CATEGORICAL:
        inputs[col] = sample[[col]].astype(str).to_numpy()
    for col in FEATURE_NUMERIC_FLOAT:
        inputs[col] = sample[[col]].astype(np.float32).to_numpy()
    for col in FEATURE_NUMERIC_INT:
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
    lines = [
        "# 146 MicroBot ML Offline First Model V1",
        "",
        "## Cel",
        "- pierwszy model pomocniczy offline dla `candidate -> paper gate`",
        "- bez ingerencji w runtime `MQL5`",
        "- z eksportem do `ONNX` pod przyszla integracje",
        "",
        "## Dane",
        f"- rekordy lacznie: `{metadata['dataset']['total_rows']}`",
        f"- train: `{metadata['dataset']['train_rows']}`",
        f"- holdout: `{metadata['dataset']['test_rows']}`",
        f"- dodatni target (`accepted=1`): `{metadata['dataset']['positive_rate']:.4f}`",
        "",
        "## Metryki holdout",
    ]

    for key, value in metadata["metrics"].items():
        lines.append(f"- `{key}`: `{value:.6f}`")

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


def main() -> int:
    args = parse_args()
    db_path = Path(args.db_path)
    output_root = ensure_dir(Path(args.output_root))

    dataset = normalize_frame(load_dataset(db_path, args.sample_limit))
    if dataset.empty:
        raise RuntimeError(f"No training rows found in {db_path}")

    train_df, test_df = time_split(dataset, args.holdout_ratio)
    x_train = train_df[FEATURE_COLUMNS]
    y_train = train_df["accepted"].to_numpy()
    x_test = test_df[FEATURE_COLUMNS]
    y_test = test_df["accepted"].to_numpy()

    pipeline = build_pipeline()
    pipeline.fit(x_train, y_train)

    y_score = pipeline.predict_proba(x_test)[:, 1]
    y_pred = (y_score >= 0.5).astype(int)
    metrics = evaluate(y_test, y_pred, y_score)
    top_features = extract_top_features(pipeline)

    joblib_path = output_root / "paper_gate_acceptor_latest.joblib"
    onnx_path = output_root / "paper_gate_acceptor_latest.onnx"
    metrics_path = output_root / "paper_gate_acceptor_metrics_latest.json"
    report_path = output_root / "paper_gate_acceptor_report_latest.md"

    joblib.dump(pipeline, joblib_path)
    onnx_info = export_onnx_model(pipeline, onnx_path, x_test)

    metadata: dict[str, Any] = {
        "dataset": {
            "db_path": str(db_path),
            "total_rows": int(len(dataset.index)),
            "train_rows": int(len(train_df.index)),
            "test_rows": int(len(test_df.index)),
            "positive_rate": float(dataset["accepted"].mean()),
            "ts_min": int(dataset["ts"].min()),
            "ts_max": int(dataset["ts"].max()),
        },
        "features": {
            "categorical": FEATURE_CATEGORICAL,
            "numeric_float": FEATURE_NUMERIC_FLOAT,
            "numeric_int": FEATURE_NUMERIC_INT,
        },
        "metrics": metrics,
        "top_features": top_features,
        "onnx_info": onnx_info,
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
