from __future__ import annotations

from pathlib import Path
from typing import Any
import shutil

import pandas as pd


def export_model_to_onnx(
    estimator: Any,
    sample_frame: pd.DataFrame,
    path: str | Path,
    family: str,
    target_opset: int = 17,
) -> tuple[Path | None, str | None]:
    out = Path(path)
    family = family.lower()

    try:
        from skl2onnx import to_onnx
    except Exception as exc:
        return None, f"Brak skl2onnx: {exc}"

    try:
        if "lightgbm" in family:
            from onnxmltools.convert.lightgbm.operator_converters.LightGbm import convert_lightgbm  # type: ignore
            from onnxmltools.convert.lightgbm.shape_calculators.Classifier import calculate_linear_classifier_output_shapes  # type: ignore
            from onnxmltools.convert.lightgbm.shape_calculators.Regressor import calculate_linear_regressor_output_shapes  # type: ignore
            from skl2onnx import update_registered_converter
            from lightgbm import LGBMClassifier, LGBMRegressor

            update_registered_converter(LGBMClassifier, "LightGbmLGBMClassifier", calculate_linear_classifier_output_shapes, convert_lightgbm)
            update_registered_converter(LGBMRegressor, "LightGbmLGBMRegressor", calculate_linear_regressor_output_shapes, convert_lightgbm)
    except Exception:
        pass

    try:
        model_proto = to_onnx(estimator, sample_frame.iloc[:1], target_opset=target_opset)
        out.write_bytes(model_proto.SerializeToString())
        return out, None
    except Exception as exc:
        return None, str(exc)


def write_alias_copy(source: str | Path | None, alias_path: str | Path) -> Path | None:
    if source is None:
        return None
    source = Path(source)
    if not source.exists():
        return None
    alias_path = Path(alias_path)
    alias_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, alias_path)
    return alias_path
