from __future__ import annotations

import math
import statistics
from dataclasses import dataclass
from typing import Dict, Tuple


@dataclass(slots=True)
class MarketDataBaseline:
    """EWMA baseline used for global market stress normalization."""

    mean_volatility: float = 0.010
    std_volatility: float = 0.005
    mean_spread: float = 10.0
    std_spread: float = 5.0


@dataclass(slots=True)
class BlackSwanPolicy:
    black_swan_threshold: float = 3.0
    precaution_fraction: float = 0.8
    ewma_alpha: float = 0.02


@dataclass(frozen=True, slots=True)
class BlackSwanSignal:
    stress_index: float
    threshold: float
    precaution_threshold: float
    precaution: bool
    black_swan: bool
    reasons: Tuple[str, ...]


def compute_z_score(current_val: float, mean: float, std: float) -> float:
    if std <= 1e-9:
        return 0.0
    if not (math.isfinite(current_val) and math.isfinite(mean) and math.isfinite(std)):
        return 0.0
    return float((current_val - mean) / std)


def calculate_global_stress_index(
    current_vols: Dict[str, float],
    current_spreads: Dict[str, float],
    baseline: MarketDataBaseline,
    weights: Tuple[float, float] = (0.6, 0.4),
) -> float:
    """Compute stress index from volatility and spread Z-scores."""

    w_vol, w_spread = weights
    valid_vols = [float(v) for v in current_vols.values() if math.isfinite(float(v)) and float(v) > 0.0]
    valid_spreads = [float(v) for v in current_spreads.values() if math.isfinite(float(v)) and float(v) > 0.0]

    avg_current_vol = statistics.mean(valid_vols) if valid_vols else float(baseline.mean_volatility)
    avg_current_spread = statistics.mean(valid_spreads) if valid_spreads else float(baseline.mean_spread)

    z_vol = compute_z_score(avg_current_vol, float(baseline.mean_volatility), float(baseline.std_volatility))
    z_spread = compute_z_score(avg_current_spread, float(baseline.mean_spread), float(baseline.std_spread))

    raw_stress = (float(w_vol) * z_vol) + (float(w_spread) * z_spread)
    return float(max(0.0, min(raw_stress, 10.0)))


def ewma_update(old: float, new: float, alpha: float) -> float:
    alpha = max(0.0, min(float(alpha), 1.0))
    if not (math.isfinite(old) and math.isfinite(new)):
        return float(old)
    return float((1.0 - alpha) * old + alpha * new)


def ewma_std_update(old_std: float, new_sample: float, old_mean: float, new_mean: float, alpha: float) -> float:
    alpha = max(0.0, min(float(alpha), 1.0))
    old_var = (float(old_std) * float(old_std)) if (float(old_std) > 1e-9 and math.isfinite(float(old_std))) else 1.0

    if not (math.isfinite(new_sample) and math.isfinite(old_mean) and math.isfinite(new_mean)):
        return float(math.sqrt(old_var))

    var = (1.0 - alpha) * old_var + alpha * ((new_sample - new_mean) ** 2)
    return float(math.sqrt(max(var, 1e-12)))


def update_baseline_ewma(
    baseline: MarketDataBaseline,
    avg_vol: float,
    avg_spread: float,
    alpha: float = 0.02,
    freeze: bool = False,
) -> MarketDataBaseline:
    if freeze:
        return baseline

    new_mean_vol = ewma_update(float(baseline.mean_volatility), float(avg_vol), alpha)
    new_mean_spread = ewma_update(float(baseline.mean_spread), float(avg_spread), alpha)

    new_std_vol = ewma_std_update(
        float(baseline.std_volatility),
        float(avg_vol),
        float(baseline.mean_volatility),
        float(new_mean_vol),
        alpha,
    )
    new_std_spread = ewma_std_update(
        float(baseline.std_spread),
        float(avg_spread),
        float(baseline.mean_spread),
        float(new_mean_spread),
        alpha,
    )

    return MarketDataBaseline(
        mean_volatility=float(new_mean_vol),
        std_volatility=float(new_std_vol),
        mean_spread=float(new_mean_spread),
        std_spread=float(new_std_spread),
    )


class BlackSwanGuard:
    """Global stress guard adapted from GLOBALNY HANDEL VER1 risk layer."""

    def __init__(
        self,
        policy: BlackSwanPolicy | None = None,
        baseline: MarketDataBaseline | None = None,
    ) -> None:
        self.policy = policy or BlackSwanPolicy()
        self.baseline = baseline or MarketDataBaseline()

    def evaluate(self, current_vols: Dict[str, float], current_spreads: Dict[str, float]) -> BlackSwanSignal:
        stress = calculate_global_stress_index(current_vols=current_vols, current_spreads=current_spreads, baseline=self.baseline)
        threshold = max(0.0, float(self.policy.black_swan_threshold))
        precaution_threshold = max(0.0, threshold * float(self.policy.precaution_fraction))

        black_swan = bool(threshold > 0.0 and stress >= threshold)
        precaution = bool((not black_swan) and precaution_threshold > 0.0 and stress >= precaution_threshold)

        if black_swan:
            reasons = ("BLACK_SWAN_STRESS", "KILL_SWITCH_BLACK_SWAN_STRESS")
        elif precaution:
            reasons = ("STRESS_PRECAUTION",)
        else:
            reasons = ("RISK_OK",)

        vols = [float(v) for v in current_vols.values() if math.isfinite(float(v)) and float(v) > 0.0]
        spreads = [float(v) for v in current_spreads.values() if math.isfinite(float(v)) and float(v) > 0.0]
        avg_vol = statistics.mean(vols) if vols else float(self.baseline.mean_volatility)
        avg_spread = statistics.mean(spreads) if spreads else float(self.baseline.mean_spread)

        self.baseline = update_baseline_ewma(
            baseline=self.baseline,
            avg_vol=avg_vol,
            avg_spread=avg_spread,
            alpha=float(self.policy.ewma_alpha),
            freeze=bool(black_swan),
        )

        return BlackSwanSignal(
            stress_index=float(stress),
            threshold=float(threshold),
            precaution_threshold=float(precaution_threshold),
            precaution=bool(precaution),
            black_swan=bool(black_swan),
            reasons=reasons,
        )
