from __future__ import annotations

import math


def evaluate_promotion(
    summary: dict[str, float],
    min_validation_trades: int = 60,
    min_total_net_pln: float = 0.0,
    min_profit_factor: float = 1.02,
    max_drawdown_pln: float = 500.0,
    min_precision_at_10pct: float = 0.50,
    max_brier: float = 0.30,
    min_fold_win_rate: float = 0.45,
) -> dict[str, object]:
    reasons = []

    selected_trades = int(summary.get("selected_trades_total", 0))
    pnl_total = float(summary.get("pnl_sum_total_pln", 0.0))
    pf = float(summary.get("profit_factor_median", 0.0))
    dd = float(summary.get("max_drawdown_worst_pln", 0.0))
    p10 = float(summary.get("precision_at_10pct_median", 0.0))
    brier = float(summary.get("brier_median", float("nan")))
    wr = float(summary.get("win_rate_median", 0.0))

    if selected_trades < min_validation_trades:
        reasons.append(f"Za mało transakcji walidacyjnych: {selected_trades} < {min_validation_trades}")
    if pnl_total < min_total_net_pln:
        reasons.append(f"Wynik netto walidacji za niski: {pnl_total:.2f} PLN")
    if pf < min_profit_factor:
        reasons.append(f"Profit factor za niski: {pf:.3f}")
    if dd > max_drawdown_pln:
        reasons.append(f"Obsunięcie za wysokie: {dd:.2f} PLN > {max_drawdown_pln:.2f} PLN")
    if p10 < min_precision_at_10pct:
        reasons.append(f"Precision@10% za niskie: {p10:.3f}")
    if not math.isnan(brier) and brier > max_brier:
        reasons.append(f"Brier za wysoki: {brier:.3f}")
    if wr < min_fold_win_rate:
        reasons.append(f"Mediana win-rate za niska: {wr:.3f}")

    return {
        "approved": not reasons,
        "reasons": reasons if reasons else ["Model spełnił bramki promocji."],
        "summary": summary,
    }
