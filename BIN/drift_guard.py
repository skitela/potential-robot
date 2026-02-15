from __future__ import annotations

import math
import statistics
from dataclasses import dataclass
from typing import Sequence, Tuple


@dataclass(slots=True)
class DriftPolicy:
    enabled: bool = True
    min_samples: int = 30
    baseline_window: int = 30
    recent_window: int = 15
    mean_drop_fraction: float = 0.40
    zscore_threshold: float = 1.8
    backoff_seconds: int = 900


@dataclass(frozen=True, slots=True)
class DriftSignal:
    active: bool
    reasons: Tuple[str, ...]
    samples: int
    baseline_mean: float
    recent_mean: float
    mean_drop: float
    zscore: float
    backoff_seconds: int


class DriftGuard:
    """Detect short-term distribution shift and request protective mode."""

    def __init__(self, policy: DriftPolicy | None = None) -> None:
        self.policy = policy or DriftPolicy()

    def evaluate(self, values: Sequence[float]) -> DriftSignal:
        if not bool(self.policy.enabled):
            return DriftSignal(False, ("DISABLED",), 0, 0.0, 0.0, 0.0, 0.0, 0)

        xs = [float(v) for v in values if isinstance(v, (int, float)) and math.isfinite(float(v))]
        n = len(xs)
        min_n = max(3, int(self.policy.min_samples))
        if n < min_n:
            return DriftSignal(False, ("INSUFFICIENT_DATA",), n, 0.0, 0.0, 0.0, 0.0, 0)

        recent_n = max(3, int(self.policy.recent_window))
        base_n = max(3, int(self.policy.baseline_window))
        if n < (recent_n + base_n):
            base = xs[: max(3, n - recent_n)]
            recent = xs[-recent_n:]
        else:
            base = xs[-(recent_n + base_n) : -recent_n]
            recent = xs[-recent_n:]
        if len(base) < 3 or len(recent) < 3:
            return DriftSignal(False, ("INSUFFICIENT_WINDOWS",), n, 0.0, 0.0, 0.0, 0.0, 0)

        mu_b = float(statistics.mean(base))
        mu_r = float(statistics.mean(recent))
        std_b = float(statistics.pstdev(base)) if len(base) >= 2 else 0.0
        drop = float(mu_b - mu_r)
        if std_b > 1e-12:
            z = float(drop / std_b)
        else:
            floor = max(1e-6, abs(mu_b) * 0.10)
            z = float(drop / floor)

        reasons = []
        active = False
        drop_frac = float(max(0.0, self.policy.mean_drop_fraction))
        z_thr = float(max(0.0, self.policy.zscore_threshold))

        if mu_b > 0.0:
            min_drop = abs(mu_b) * drop_frac
            if drop > min_drop and z >= z_thr:
                active = True
                reasons.append("POSITIVE_EDGE_COLLAPSE")
        else:
            if mu_r < mu_b and z >= z_thr:
                active = True
                reasons.append("NEGATIVE_DRIFT_DEEPENING")

        if not reasons:
            reasons = ["DRIFT_OK"]
        backoff = int(max(1, int(self.policy.backoff_seconds))) if active else 0
        return DriftSignal(
            active=bool(active),
            reasons=tuple(reasons),
            samples=int(n),
            baseline_mean=float(mu_b),
            recent_mean=float(mu_r),
            mean_drop=float(drop),
            zscore=float(z),
            backoff_seconds=int(backoff),
        )
