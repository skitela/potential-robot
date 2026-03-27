from __future__ import annotations

import numpy as np
import pandas as pd


def build_targets(
    df: pd.DataFrame,
    gate_positive_min_pln: float = 0.0,
    regression_clip_pln: float = 300.0,
    sample_weight_abs_cap_pln: float = 150.0,
) -> pd.DataFrame:
    if "net_pln" not in df.columns:
        raise KeyError("Brak kolumny 'net_pln' wymaganej do budowy etykiet.")
    out = df.copy()
    out["y_gate"] = (out["net_pln"] >= gate_positive_min_pln).astype(int)
    out["y_edge_reg"] = out["net_pln"].clip(-regression_clip_pln, regression_clip_pln)
    out["y_slippage_reg"] = out.get("slippage_cost_pln", 0.0).clip(0.0, regression_clip_pln)
    if "close_reason" in out.columns:
        out["y_fill"] = (~out["close_reason"].fillna("").str.contains("NOT_FILLED|REJECTED|CANCEL", case=False)).astype(int)
    else:
        out["y_fill"] = 1
    out["sample_weight"] = 1.0 + np.minimum(out["net_pln"].abs(), sample_weight_abs_cap_pln) / max(sample_weight_abs_cap_pln, 1.0)
    return out
