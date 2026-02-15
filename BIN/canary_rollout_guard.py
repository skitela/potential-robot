from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence, Tuple


@dataclass(slots=True)
class CanaryPolicy:
    enabled: bool = True
    lookback_sec: int = 24 * 3600
    promote_min_deals: int = 15
    promote_min_net_pnl: float = 0.0
    pause_loss_streak: int = 3
    pause_net_loss_abs: float = 0.0
    max_error_incidents: int = 3
    canary_max_symbols: int = 1
    backoff_seconds: int = 900


@dataclass(frozen=True, slots=True)
class CanarySignal:
    canary_active: bool
    promoted: bool
    promoted_now: bool
    pause: bool
    allowed_symbols: int
    reasons: Tuple[str, ...]
    deals_in_window: int
    loss_streak: int
    net_pnl: float
    error_incidents: int
    backoff_seconds: int


class CanaryRolloutGuard:
    """Conservative rollout gate for live-small-cap training."""

    def __init__(self, policy: CanaryPolicy | None = None) -> None:
        self.policy = policy or CanaryPolicy()

    def evaluate(
        self,
        *,
        deals_desc: Sequence[Tuple[int, str, float]],
        now_ts: int,
        promoted_state: bool,
        incident_error_count: int,
    ) -> CanarySignal:
        if not bool(self.policy.enabled):
            return CanarySignal(
                canary_active=False,
                promoted=True,
                promoted_now=False,
                pause=False,
                allowed_symbols=1_000_000,
                reasons=("DISABLED",),
                deals_in_window=0,
                loss_streak=0,
                net_pnl=0.0,
                error_incidents=0,
                backoff_seconds=0,
            )

        lookback = max(1, int(self.policy.lookback_sec))
        cutoff = int(now_ts) - lookback
        wins = []
        for item in deals_desc:
            try:
                t, sym, pnl = item
                if int(t) < cutoff:
                    continue
                wins.append((int(t), str(sym or ""), float(pnl)))
            except Exception:
                continue
        wins.sort(key=lambda x: int(x[0]), reverse=True)

        deals_n = len(wins)
        net_pnl = float(sum(float(x[2]) for x in wins))
        loss_streak = 0
        for _t, _s, pnl in wins:
            if float(pnl) < 0.0:
                loss_streak += 1
                continue
            break

        reasons = []
        promoted = bool(promoted_state)
        promoted_now = False
        if not promoted:
            if (
                deals_n >= max(1, int(self.policy.promote_min_deals))
                and net_pnl >= float(self.policy.promote_min_net_pnl)
                and int(incident_error_count) <= 0
            ):
                promoted = True
                promoted_now = True
                reasons.append("PROMOTED")

        pause = False
        if deals_n > 0 and loss_streak >= max(1, int(self.policy.pause_loss_streak)):
            pause = True
            reasons.append("LOSS_STREAK")
        max_loss_abs = float(self.policy.pause_net_loss_abs or 0.0)
        if max_loss_abs > 0.0 and deals_n > 0 and net_pnl <= (-1.0 * abs(max_loss_abs)):
            pause = True
            reasons.append("NET_LOSS_ABS")
        if int(self.policy.max_error_incidents) > 0 and int(incident_error_count) >= int(self.policy.max_error_incidents):
            pause = True
            reasons.append("INCIDENTS")

        canary_active = (not promoted)
        allowed_symbols = int(self.policy.canary_max_symbols) if canary_active else 1_000_000
        if pause:
            allowed_symbols = 0

        if not reasons:
            reasons = ["CANARY_ACTIVE" if canary_active else "NORMAL"]
        backoff = int(max(1, int(self.policy.backoff_seconds))) if pause else 0

        return CanarySignal(
            canary_active=bool(canary_active),
            promoted=bool(promoted),
            promoted_now=bool(promoted_now),
            pause=bool(pause),
            allowed_symbols=int(max(0, allowed_symbols)),
            reasons=tuple(reasons),
            deals_in_window=int(deals_n),
            loss_streak=int(loss_streak),
            net_pnl=float(net_pnl),
            error_incidents=int(max(0, incident_error_count)),
            backoff_seconds=int(backoff),
        )
