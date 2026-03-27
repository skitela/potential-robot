from __future__ import annotations

from dataclasses import asdict, dataclass

import numpy as np
import pandas as pd
from sklearn.metrics import brier_score_loss


@dataclass(slots=True)
class FoldReport:
    fold_id: int
    train_rows: int
    valid_rows: int
    selected_trades: int
    pnl_sum_pln: float
    profit_factor: float
    max_drawdown_pln: float
    win_rate: float
    precision_at_10pct: float
    brier: float | None


def safe_profit_factor(series: pd.Series) -> float:
    gp = series[series > 0].sum()
    gl = -series[series < 0].sum()
    if gl <= 0:
        return float("inf") if gp > 0 else 0.0
    return float(gp / gl)


def max_drawdown(cumulative: pd.Series) -> float:
    if cumulative.empty:
        return 0.0
    running = cumulative.cummax()
    dd = cumulative - running
    return float(-dd.min())


def precision_at_top_fraction(y_true: np.ndarray, score: np.ndarray, top_fraction: float = 0.10) -> float:
    if len(y_true) == 0:
        return 0.0
    k = max(1, int(len(y_true) * top_fraction))
    idx = np.argsort(np.asarray(score))[::-1][:k]
    return float(np.mean(np.asarray(y_true)[idx]))


def build_decisions(
    frame: pd.DataFrame,
    gate_probability: np.ndarray,
    edge_prediction_pln: np.ndarray,
    fill_probability: np.ndarray | None = None,
    slippage_prediction_pln: np.ndarray | None = None,
    min_gate_probability: float = 0.53,
    min_decision_score_pln: float = 0.0,
    max_spread_points: float = 999.0,
    max_runtime_latency_us: float = 250000.0,
    max_server_ping_ms: float = 35.0,
) -> pd.DataFrame:
    out = frame.copy()
    out["pred_gate_probability"] = np.asarray(gate_probability, dtype=float)
    out["pred_edge_pln"] = np.asarray(edge_prediction_pln, dtype=float)
    out["pred_fill_probability"] = 1.0 if fill_probability is None else np.asarray(fill_probability, dtype=float)
    out["pred_slippage_pln"] = 0.0 if slippage_prediction_pln is None else np.asarray(slippage_prediction_pln, dtype=float)
    out["decision_score_pln"] = out["pred_gate_probability"] * out["pred_fill_probability"] * (out["pred_edge_pln"] - out["pred_slippage_pln"])

    spread_ok = out.get("spread_points", 0.0) <= max_spread_points
    latency_ok = out.get("runtime_latency_us", 0.0) <= max_runtime_latency_us
    ping_ok = out.get("server_operational_ping_ms", 0.0) <= max_server_ping_ms

    out["selected_trade"] = (
        (out["pred_gate_probability"] >= min_gate_probability)
        & (out["decision_score_pln"] >= min_decision_score_pln)
        & spread_ok
        & latency_ok
        & ping_ok
    ).astype(int)
    return out


def fold_report(
    fold_id: int,
    validation_frame: pd.DataFrame,
    y_true_gate: np.ndarray,
    gate_probability: np.ndarray,
) -> FoldReport:
    selected = validation_frame.loc[validation_frame["selected_trade"] == 1].copy()
    pnl_sum = float(selected["net_pln"].sum()) if not selected.empty else 0.0
    win_rate = float((selected["net_pln"] > 0).mean()) if not selected.empty else 0.0
    pf = safe_profit_factor(selected["net_pln"]) if not selected.empty else 0.0
    dd = max_drawdown(selected["net_pln"].cumsum()) if not selected.empty else 0.0
    p10 = precision_at_top_fraction(y_true_gate, gate_probability, 0.10)
    try:
        brier = float(brier_score_loss(y_true_gate, gate_probability))
    except Exception:
        brier = None

    return FoldReport(
        fold_id=fold_id,
        train_rows=0,
        valid_rows=int(len(validation_frame)),
        selected_trades=int(selected.shape[0]),
        pnl_sum_pln=pnl_sum,
        profit_factor=pf,
        max_drawdown_pln=dd,
        win_rate=win_rate,
        precision_at_10pct=p10,
        brier=brier,
    )


def aggregate_fold_reports(reports: list[FoldReport]) -> dict[str, float]:
    if not reports:
        return {}
    pnl = [r.pnl_sum_pln for r in reports]
    pf = [r.profit_factor for r in reports]
    dd = [r.max_drawdown_pln for r in reports]
    wr = [r.win_rate for r in reports]
    p10 = [r.precision_at_10pct for r in reports]
    br = [r.brier for r in reports if r.brier is not None]
    sel = [r.selected_trades for r in reports]

    return {
        "fold_count": float(len(reports)),
        "selected_trades_total": float(sum(sel)),
        "pnl_sum_total_pln": float(sum(pnl)),
        "pnl_sum_median_pln": float(np.median(pnl)),
        "profit_factor_median": float(np.median(pf)),
        "max_drawdown_worst_pln": float(max(dd)),
        "win_rate_median": float(np.median(wr)),
        "precision_at_10pct_median": float(np.median(p10)),
        "brier_median": float(np.median(br)) if br else float("nan"),
    }


def fold_reports_to_frame(reports: list[FoldReport]) -> pd.DataFrame:
    return pd.DataFrame([asdict(r) for r in reports])
