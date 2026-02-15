from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence, Tuple


@dataclass(slots=True)
class SelfHealPolicy:
    enabled: bool = True
    lookback_sec: int = 3 * 3600
    min_deals_in_window: int = 3
    loss_streak_trigger: int = 3
    max_net_loss_abs: float = 0.0
    backoff_seconds: int = 900
    symbol_cooldown_seconds: int = 600


@dataclass(frozen=True, slots=True)
class SelfHealSignal:
    active: bool
    reasons: Tuple[str, ...]
    backoff_seconds: int
    symbol_cooldown_seconds: int
    deals_in_window: int
    loss_streak: int
    net_pnl: float
    streak_symbols: Tuple[str, ...]


class SelfHealGuard:
    """Fail-closed guard that pauses entries after short-term degradation."""

    def __init__(self, policy: SelfHealPolicy | None = None) -> None:
        self.policy = policy or SelfHealPolicy()

    def evaluate(self, deals_desc: Sequence[Tuple[int, str, float]], now_ts: int) -> SelfHealSignal:
        if not bool(self.policy.enabled):
            return SelfHealSignal(
                active=False,
                reasons=("DISABLED",),
                backoff_seconds=0,
                symbol_cooldown_seconds=0,
                deals_in_window=0,
                loss_streak=0,
                net_pnl=0.0,
                streak_symbols=(),
            )

        lookback = max(1, int(self.policy.lookback_sec))
        window_start = int(now_ts) - lookback

        window_deals = []
        for item in deals_desc:
            try:
                t, sym, pnl = item
                t_i = int(t)
                if t_i < window_start:
                    continue
                sym_s = str(sym or "")
                pnl_f = float(pnl)
                window_deals.append((t_i, sym_s, pnl_f))
            except Exception:
                continue

        if not window_deals:
            return SelfHealSignal(
                active=False,
                reasons=("NO_RECENT_DEALS",),
                backoff_seconds=0,
                symbol_cooldown_seconds=0,
                deals_in_window=0,
                loss_streak=0,
                net_pnl=0.0,
                streak_symbols=(),
            )

        window_deals.sort(key=lambda x: int(x[0]), reverse=True)
        deals_n = len(window_deals)
        net_pnl = float(sum(float(x[2]) for x in window_deals))

        streak = 0
        streak_symbols = []
        for _t, sym, pnl in window_deals:
            if float(pnl) < 0.0:
                streak += 1
                streak_symbols.append(str(sym))
                continue
            break

        reasons = []
        min_n = max(1, int(self.policy.min_deals_in_window))
        if deals_n >= min_n and streak >= max(1, int(self.policy.loss_streak_trigger)):
            reasons.append("LOSS_STREAK")

        max_net_loss_abs = float(self.policy.max_net_loss_abs or 0.0)
        if deals_n >= min_n and max_net_loss_abs > 0.0 and net_pnl <= (-1.0 * abs(max_net_loss_abs)):
            reasons.append("NET_LOSS_ABS")

        active = bool(reasons)
        backoff_seconds = int(max(1, int(self.policy.backoff_seconds))) if active else 0
        symbol_cooldown_seconds = int(max(1, int(self.policy.symbol_cooldown_seconds))) if active else 0

        uniq_streak_symbols = tuple(dict.fromkeys(streak_symbols))
        return SelfHealSignal(
            active=active,
            reasons=tuple(reasons) if reasons else ("OK",),
            backoff_seconds=backoff_seconds,
            symbol_cooldown_seconds=symbol_cooldown_seconds,
            deals_in_window=int(deals_n),
            loss_streak=int(streak),
            net_pnl=float(net_pnl),
            streak_symbols=uniq_streak_symbols,
        )
