from __future__ import annotations

from dataclasses import dataclass
import os
from typing import Any

import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.dummy import DummyClassifier, DummyRegressor
from sklearn.ensemble import HistGradientBoostingClassifier, HistGradientBoostingRegressor
from sklearn.linear_model import LogisticRegression, Ridge, SGDClassifier
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

try:
    from lightgbm import LGBMClassifier, LGBMRegressor
except Exception:  # pragma: no cover
    LGBMClassifier = None
    LGBMRegressor = None


@dataclass(slots=True)
class FittedBundle:
    estimator: Any
    model_family: str
    task: str
    features: list[str]
    notes: list[str]


def build_preprocessor(
    numeric_features: list[str],
    categorical_features: list[str],
    linear: bool = False,
) -> ColumnTransformer:
    transformers = []
    if categorical_features:
        transformers.append(("cat", OneHotEncoder(handle_unknown="ignore", sparse_output=bool(linear)), categorical_features))
    if numeric_features:
        transformers.append(("num", StandardScaler(with_mean=False) if linear else "passthrough", numeric_features))
    return ColumnTransformer(transformers=transformers, remainder="drop")


def build_estimator(
    family: str,
    task: str,
    numeric_features: list[str],
    categorical_features: list[str],
    random_state: int = 42,
) -> tuple[Any, list[str]]:
    family = family.lower().strip()
    notes = []

    if task == "classification":
        if family == "sgd_classifier":
            pre = build_preprocessor(numeric_features, categorical_features, linear=True)
            model = SGDClassifier(
                loss="log_loss",
                penalty="elasticnet",
                alpha=1e-5,
                l1_ratio=0.15,
                max_iter=300,
                tol=1e-4,
                class_weight="balanced",
                random_state=random_state,
            )
            return Pipeline([("pre", pre), ("model", model)]), notes

        if family == "logistic_regression":
            pre = build_preprocessor(numeric_features, categorical_features, linear=True)
            model = LogisticRegression(max_iter=1000, class_weight="balanced", random_state=random_state)
            return Pipeline([("pre", pre), ("model", model)]), notes

        if family == "lightgbm_classifier" and LGBMClassifier is not None and os.environ.get("MB_DISABLE_LIGHTGBM", "0") not in {"1", "true", "TRUE"}:
            pre = build_preprocessor(numeric_features, categorical_features, linear=False)
            model = LGBMClassifier(
                n_estimators=300,
                learning_rate=0.04,
                num_leaves=31,
                subsample=0.9,
                colsample_bytree=0.9,
                min_child_samples=25,
                reg_alpha=0.05,
                reg_lambda=0.05,
                random_state=random_state,
                n_jobs=-1,
            )
            return Pipeline([("pre", pre), ("model", model)]), notes

        pre = build_preprocessor(numeric_features, categorical_features, linear=True)
        model = LogisticRegression(max_iter=1000, class_weight="balanced", random_state=random_state)
        notes.append("LightGBM niedostępny; użyto LogisticRegression jako szybki fallback klasyfikacyjny.")
        return Pipeline([("pre", pre), ("model", model)]), notes

    if task == "regression":
        if family == "ridge_regression":
            pre = build_preprocessor(numeric_features, categorical_features, linear=True)
            model = Ridge(alpha=1.0, random_state=random_state)
            return Pipeline([("pre", pre), ("model", model)]), notes

        if family == "lightgbm_regressor" and LGBMRegressor is not None and os.environ.get("MB_DISABLE_LIGHTGBM", "0") not in {"1", "true", "TRUE"}:
            pre = build_preprocessor(numeric_features, categorical_features, linear=False)
            model = LGBMRegressor(
                n_estimators=350,
                learning_rate=0.04,
                num_leaves=31,
                subsample=0.9,
                colsample_bytree=0.9,
                min_child_samples=25,
                reg_alpha=0.05,
                reg_lambda=0.1,
                random_state=random_state,
                n_jobs=-1,
            )
            return Pipeline([("pre", pre), ("model", model)]), notes

        pre = build_preprocessor(numeric_features, categorical_features, linear=True)
        model = Ridge(alpha=1.0, random_state=random_state)
        notes.append("LightGBM niedostępny; użyto Ridge jako szybki fallback regresyjny.")
        return Pipeline([("pre", pre), ("model", model)]), notes

    raise ValueError(f"Nieobsługiwana kombinacja family/task: {family}/{task}")


def fit_model(
    family: str,
    task: str,
    frame: pd.DataFrame,
    feature_names: list[str],
    categorical_features: list[str],
    random_state: int,
    target_col: str,
    sample_weight_col: str | None = None,
) -> FittedBundle:
    X = frame[feature_names]
    y = frame[target_col]
    numeric_features = [c for c in feature_names if c not in categorical_features]

    if task == "classification" and pd.Series(y).nunique(dropna=False) < 2:
        constant = int(pd.Series(y).iloc[0])
        estimator = DummyClassifier(strategy="constant", constant=constant)
        estimator.fit(X, y)
        return FittedBundle(estimator, "dummy_classifier", task, feature_names, [f"Jednoklasowy slice: {constant}."])

    if task == "regression" and pd.Series(y).nunique(dropna=False) < 2:
        estimator = DummyRegressor(strategy="mean")
        estimator.fit(X, y)
        return FittedBundle(estimator, "dummy_regressor", task, feature_names, ["Jeden poziom wartości celu."])

    estimator, notes = build_estimator(family, task, numeric_features, categorical_features, random_state)
    fit_kwargs = {}
    if sample_weight_col is not None and sample_weight_col in frame.columns:
        fit_kwargs["model__sample_weight"] = frame[sample_weight_col].to_numpy(dtype=float)
    estimator.fit(X, y, **fit_kwargs)
    return FittedBundle(estimator=estimator, model_family=family, task=task, features=feature_names, notes=notes)


def positive_proba(bundle: FittedBundle | None, X: pd.DataFrame) -> np.ndarray:
    if bundle is None:
        return np.ones(shape=(len(X),), dtype=float)
    estimator = bundle.estimator
    if hasattr(estimator, "predict_proba"):
        probs = estimator.predict_proba(X)
        if probs.ndim == 2 and probs.shape[1] >= 2:
            return probs[:, 1].astype(float)
    if hasattr(estimator, "decision_function"):
        raw = np.asarray(estimator.decision_function(X), dtype=float)
        return 1.0 / (1.0 + np.exp(-raw))
    pred = estimator.predict(X)
    return np.clip(np.asarray(pred, dtype=float), 0.0, 1.0)


def regression_pred(bundle: FittedBundle | None, X: pd.DataFrame) -> np.ndarray:
    if bundle is None:
        return np.zeros(shape=(len(X),), dtype=float)
    return np.asarray(bundle.estimator.predict(X), dtype=float)
