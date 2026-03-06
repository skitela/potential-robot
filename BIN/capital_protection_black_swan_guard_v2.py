from __future__ import annotations

import math
from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional, Tuple


class GuardState(Enum):
    NORMAL = "NORMAL"
    CAUTION = "CAUTION"
    DEFENSIVE = "DEFENSIVE"
    CLOSE_ONLY = "CLOSE_ONLY"
    HALT = "HALT"


class GuardAction(Enum):
    ALLOW = "ALLOW"
    REDUCE_SIZE = "REDUCE_SIZE"
    BLOCK_NEW_TRADES = "BLOCK_NEW_TRADES"
    CLOSE_ONLY = "CLOSE_ONLY"
    FORCE_FLAT = "FORCE_FLAT"


class TriggerType(Enum):
    NONE = "NONE"
    STRESS = "STRESS"
    CRASH = "CRASH"
    RECOVERY = "RECOVERY"


@dataclass(frozen=True)
class MarketSnapshot:
    ts_monotonic: float
    symbol: str
    volatility_score: float
    spread_points: float
    slippage_points: float
    liquidity_score: float
    tick_rate_per_sec: float
    tick_gap_ms: float
    price_jump_points: float
    bridge_wait_ms: float
    heartbeat_age_ms: float
    reject_count_recent: int
    stale_tick_flag: bool = False
    burst_flag: bool = False
    ask_lt_bid_flag: bool = False


@dataclass(frozen=True)
class GuardConfig:
    ewma_alpha: float = 0.03
    warmup_ticks: int = 30

    w_volatility: float = 0.20
    w_spread: float = 0.22
    w_bridge_wait: float = 0.14
    w_slippage: float = 0.14
    w_liquidity: float = 0.10
    w_tick_gap: float = 0.10
    w_rejects: float = 0.10

    caution_threshold: float = 1.20
    defensive_threshold: float = 1.80
    close_only_threshold: float = 2.60
    halt_threshold: float = 3.40

    caution_exit_threshold: float = 0.95
    defensive_exit_threshold: float = 1.35
    close_only_exit_threshold: float = 2.00
    halt_exit_threshold: float = 1.70

    crash_move_mult: float = 6.0
    crash_spread_mult: float = 4.0
    crash_bridge_mult: float = 3.5
    crash_bridge_streak_required: int = 3
    crash_slippage_mult: float = 5.0
    crash_tick_gap_mult: float = 4.0
    crash_reject_count: int = 3
    liquidity_floor_score: float = 0.20
    liquidity_floor_streak_required: int = 3
    min_tick_rate_fraction: float = 0.30

    hard_max_spread_points: float = 40.0
    hard_max_slippage_points: float = 25.0
    hard_max_bridge_wait_ms: float = 300.0
    hard_max_heartbeat_age_ms: float = 2500.0
    hard_max_tick_gap_ms: float = 2000.0

    caution_cooldown_sec: int = 30
    defensive_cooldown_sec: int = 90
    close_only_cooldown_sec: int = 180
    halt_cooldown_sec: int = 300
    required_stable_ticks_for_recovery: int = 8

    caution_size_multiplier: float = 0.75
    defensive_size_multiplier: float = 0.40

    stress_clip_min: float = 0.0
    stress_clip_max: float = 10.0


@dataclass
class GuardDecision:
    symbol: str
    ts_monotonic: float
    state: GuardState
    action: GuardAction
    trigger: TriggerType
    stress_score: float
    size_multiplier: float
    cooldown_remaining_sec: float
    frozen_baseline: bool
    warm: bool
    dominant_reason: str
    reasons: List[str] = field(default_factory=list)
    telemetry: Dict[str, float] = field(default_factory=dict)


class _EWMA:
    __slots__ = ("alpha", "value", "count")

    def __init__(self, alpha: float):
        self.alpha = float(alpha)
        self.value: Optional[float] = None
        self.count = 0

    def update(self, x: float) -> float:
        x = float(x)
        if self.value is None:
            self.value = x
        else:
            self.value = ((1.0 - self.alpha) * self.value) + (self.alpha * x)
        self.count += 1
        return float(self.value)


class CapitalProtectionBlackSwanGuardV2:
    """
    Advisory Black Swan/Crash guard.
    No network I/O, no file I/O, no blocking waits.
    """

    def __init__(self, config: Optional[GuardConfig] = None):
        self.cfg = config or GuardConfig()
        self._volatility = _EWMA(self.cfg.ewma_alpha)
        self._spread = _EWMA(self.cfg.ewma_alpha)
        self._bridge_wait = _EWMA(self.cfg.ewma_alpha)
        self._slippage = _EWMA(self.cfg.ewma_alpha)
        self._liquidity = _EWMA(self.cfg.ewma_alpha)
        self._tick_rate = _EWMA(self.cfg.ewma_alpha)
        self._tick_gap = _EWMA(self.cfg.ewma_alpha)
        self._price_jump = _EWMA(self.cfg.ewma_alpha)
        self._reject_count = _EWMA(self.cfg.ewma_alpha)
        self._state = GuardState.NORMAL
        self._trigger = TriggerType.NONE
        self._last_transition_ts = 0.0
        self._stable_tick_counter = 0
        self._frozen_baseline = False
        self._liquidity_floor_streak = 0
        self._bridge_freeze_streak = 0

    def evaluate(self, snap: MarketSnapshot) -> GuardDecision:
        self._validate_snapshot(snap)
        warm_before = self._is_warm()
        if (not self._frozen_baseline) or (not warm_before):
            self._update_baselines(snap)
        warm = self._is_warm()

        stress_score, stress_reasons, stress_telemetry = self._compute_stress(snap)
        crash_hit, crash_reasons = self._detect_crash(snap, warm=warm)
        reasons = list(stress_reasons) + list(crash_reasons)
        telemetry = dict(stress_telemetry)

        proposed_state, trigger = self._classify_state(stress_score=stress_score, crash_hit=crash_hit, warm=warm, snap=snap)
        next_state = self._apply_hysteresis(
            now_ts=snap.ts_monotonic,
            proposed_state=proposed_state,
            stress_score=stress_score,
            crash_hit=crash_hit,
        )

        if next_state != self._state:
            self._state = next_state
            self._trigger = trigger if next_state != GuardState.NORMAL else TriggerType.RECOVERY
            self._last_transition_ts = float(snap.ts_monotonic)
            self._stable_tick_counter = 0
        elif self._state == GuardState.NORMAL and not crash_hit and stress_score < self.cfg.caution_threshold:
            self._trigger = TriggerType.NONE

        self._frozen_baseline = self._state in (GuardState.CLOSE_ONLY, GuardState.HALT)
        action, size_multiplier = self._map_action(self._state)
        cooldown_remaining = self._cooldown_remaining(snap.ts_monotonic, self._state)
        dominant_reason = self._dominant_reason(reasons, stress_score, crash_hit, warm)

        telemetry.update(
            {
                "stress_score": float(stress_score),
                "stable_tick_counter": float(self._stable_tick_counter),
                "bridge_wait_baseline": float(self._bridge_wait.value or 0.0),
                "spread_baseline": float(self._spread.value or 0.0),
                "slippage_baseline": float(self._slippage.value or 0.0),
                "liquidity_baseline": float(self._liquidity.value or 0.0),
                "tick_gap_baseline": float(self._tick_gap.value or 0.0),
                "tick_rate_baseline": float(self._tick_rate.value or 0.0),
                "price_jump_baseline": float(self._price_jump.value or 0.0),
                "reject_count_baseline": float(self._reject_count.value or 0.0),
            }
        )

        return GuardDecision(
            symbol=str(snap.symbol),
            ts_monotonic=float(snap.ts_monotonic),
            state=self._state,
            action=action,
            trigger=self._trigger,
            stress_score=float(stress_score),
            size_multiplier=float(size_multiplier),
            cooldown_remaining_sec=float(cooldown_remaining),
            frozen_baseline=bool(self._frozen_baseline),
            warm=bool(warm),
            dominant_reason=dominant_reason,
            reasons=reasons,
            telemetry=telemetry,
        )

    @staticmethod
    def _validate_snapshot(snap: MarketSnapshot) -> None:
        if not math.isfinite(float(snap.ts_monotonic)):
            raise ValueError("ts_monotonic must be finite")
        fields = {
            "volatility_score": float(snap.volatility_score),
            "spread_points": float(snap.spread_points),
            "slippage_points": float(snap.slippage_points),
            "liquidity_score": float(snap.liquidity_score),
            "tick_rate_per_sec": float(snap.tick_rate_per_sec),
            "tick_gap_ms": float(snap.tick_gap_ms),
            "price_jump_points": float(snap.price_jump_points),
            "bridge_wait_ms": float(snap.bridge_wait_ms),
            "heartbeat_age_ms": float(snap.heartbeat_age_ms),
            "reject_count_recent": float(snap.reject_count_recent),
        }
        for name, value in fields.items():
            if not math.isfinite(value):
                raise ValueError(f"{name} must be finite")
            if name != "liquidity_score" and value < 0.0:
                raise ValueError(f"{name} must be >= 0")
        if not (0.0 <= float(snap.liquidity_score) <= 1.0):
            raise ValueError("liquidity_score must be in [0, 1]")

    def _update_baselines(self, snap: MarketSnapshot) -> None:
        self._volatility.update(float(snap.volatility_score))
        self._spread.update(float(snap.spread_points))
        self._bridge_wait.update(float(snap.bridge_wait_ms))
        self._slippage.update(float(snap.slippage_points))
        self._liquidity.update(max(0.001, float(snap.liquidity_score)))
        self._tick_rate.update(max(0.001, float(snap.tick_rate_per_sec)))
        self._tick_gap.update(float(snap.tick_gap_ms))
        self._price_jump.update(float(snap.price_jump_points))
        self._reject_count.update(float(snap.reject_count_recent))

    def _is_warm(self) -> bool:
        counts = (
            self._volatility.count,
            self._spread.count,
            self._bridge_wait.count,
            self._slippage.count,
            self._liquidity.count,
            self._tick_rate.count,
            self._tick_gap.count,
            self._price_jump.count,
        )
        return int(min(counts)) >= int(self.cfg.warmup_ticks)

    @staticmethod
    def _safe_dev(value: float, baseline: Optional[float], *, invert: bool = False) -> float:
        if baseline is None or baseline <= 0.0:
            return 0.0
        if invert:
            v = max(float(value), 1e-6)
            return max(0.0, (float(baseline) - v) / float(baseline))
        return max(0.0, abs(float(value) - float(baseline)) / float(baseline))

    def _compute_stress(self, snap: MarketSnapshot) -> Tuple[float, List[str], Dict[str, float]]:
        d_vol = self._safe_dev(snap.volatility_score, self._volatility.value)
        d_spread = self._safe_dev(snap.spread_points, self._spread.value)
        d_bridge = self._safe_dev(snap.bridge_wait_ms, self._bridge_wait.value)
        d_slippage = self._safe_dev(snap.slippage_points, self._slippage.value)
        d_liquidity = self._safe_dev(snap.liquidity_score, self._liquidity.value, invert=True)
        d_tick_gap = self._safe_dev(snap.tick_gap_ms, self._tick_gap.value)
        d_rejects = self._safe_dev(float(snap.reject_count_recent), self._reject_count.value)

        score = (
            (self.cfg.w_volatility * d_vol)
            + (self.cfg.w_spread * d_spread)
            + (self.cfg.w_bridge_wait * d_bridge)
            + (self.cfg.w_slippage * d_slippage)
            + (self.cfg.w_liquidity * d_liquidity)
            + (self.cfg.w_tick_gap * d_tick_gap)
            + (self.cfg.w_rejects * d_rejects)
        )
        score = float(min(self.cfg.stress_clip_max, max(self.cfg.stress_clip_min, score)))

        reasons: List[str] = []
        if d_spread > 0.8:
            reasons.append("stress:spread_regime_deterioration")
        if d_bridge > 0.8:
            reasons.append("stress:bridge_latency_deterioration")
        if d_slippage > 0.8:
            reasons.append("stress:slippage_deterioration")
        if d_liquidity > 0.5:
            reasons.append("stress:liquidity_deterioration")
        if d_tick_gap > 0.8:
            reasons.append("stress:tick_gap_deterioration")
        if d_vol > 1.0:
            reasons.append("stress:volatility_regime_shift")
        if d_rejects > 0.5:
            reasons.append("stress:rejections_increasing")
        if snap.stale_tick_flag:
            reasons.append("runtime:stale_tick_flag")
        if snap.burst_flag:
            reasons.append("runtime:burst_flag")
        if snap.ask_lt_bid_flag:
            reasons.append("runtime:ask_lt_bid_flag")

        telemetry = {
            "d_volatility": float(d_vol),
            "d_spread": float(d_spread),
            "d_bridge_wait": float(d_bridge),
            "d_slippage": float(d_slippage),
            "d_liquidity": float(d_liquidity),
            "d_tick_gap": float(d_tick_gap),
            "d_rejects": float(d_rejects),
        }
        return score, reasons, telemetry

    def _detect_crash(self, snap: MarketSnapshot, *, warm: bool) -> Tuple[bool, List[str]]:
        reasons: List[str] = []
        if float(snap.spread_points) >= float(self.cfg.hard_max_spread_points):
            reasons.append("hard_cap:spread")
        if float(snap.slippage_points) >= float(self.cfg.hard_max_slippage_points):
            reasons.append("hard_cap:slippage")
        if float(snap.bridge_wait_ms) >= float(self.cfg.hard_max_bridge_wait_ms):
            reasons.append("hard_cap:bridge_wait")
        if float(snap.heartbeat_age_ms) >= float(self.cfg.hard_max_heartbeat_age_ms):
            reasons.append("hard_cap:heartbeat_age")
        if float(snap.tick_gap_ms) >= float(self.cfg.hard_max_tick_gap_ms):
            reasons.append("hard_cap:tick_gap")

        # During warmup, keep only absolute crash conditions that do not depend
        # on EWMA baselines. This prevents startup false positives.
        if not bool(warm):
            if int(snap.reject_count_recent) >= int(self.cfg.crash_reject_count):
                reasons.append("crash:reject_cluster")
            if bool(snap.ask_lt_bid_flag):
                reasons.append("crash:crossed_market")
            return bool(reasons), reasons

        if self._price_jump.value and float(snap.price_jump_points) >= float(self.cfg.crash_move_mult) * float(self._price_jump.value):
            reasons.append("crash:flash_move")
        if self._spread.value and float(snap.spread_points) >= float(self.cfg.crash_spread_mult) * float(self._spread.value):
            reasons.append("crash:spread_explosion")
        bridge_freeze_hit = bool(
            self._bridge_wait.value
            and float(snap.bridge_wait_ms) >= float(self.cfg.crash_bridge_mult) * float(self._bridge_wait.value)
        )
        if bridge_freeze_hit:
            self._bridge_freeze_streak += 1
        else:
            self._bridge_freeze_streak = 0
        req_bridge_streak = max(1, int(self.cfg.crash_bridge_streak_required))
        if self._bridge_freeze_streak >= req_bridge_streak:
            reasons.append("crash:bridge_freeze")
        if self._slippage.value and float(snap.slippage_points) >= float(self.cfg.crash_slippage_mult) * float(self._slippage.value):
            reasons.append("crash:slippage_spike")
        if self._tick_gap.value and float(snap.tick_gap_ms) >= float(self.cfg.crash_tick_gap_mult) * float(self._tick_gap.value):
            reasons.append("crash:tick_gap_spike")
        if int(snap.reject_count_recent) >= int(self.cfg.crash_reject_count):
            reasons.append("crash:reject_cluster")
        if float(snap.liquidity_score) < float(self.cfg.liquidity_floor_score):
            self._liquidity_floor_streak += 1
        else:
            self._liquidity_floor_streak = 0
        req_streak = max(1, int(self.cfg.liquidity_floor_streak_required))
        if self._liquidity_floor_streak >= req_streak:
            reasons.append("crash:liquidity_floor")
        if self._tick_rate.value and float(snap.tick_rate_per_sec) <= float(self.cfg.min_tick_rate_fraction) * float(self._tick_rate.value):
            reasons.append("crash:tick_rate_collapse")
        if bool(snap.ask_lt_bid_flag):
            reasons.append("crash:crossed_market")
        return bool(reasons), reasons

    def _classify_state(
        self,
        *,
        stress_score: float,
        crash_hit: bool,
        warm: bool,
        snap: MarketSnapshot,
    ) -> Tuple[GuardState, TriggerType]:
        if crash_hit:
            return GuardState.HALT, TriggerType.CRASH
        if not warm:
            if (
                float(snap.spread_points) >= float(self.cfg.hard_max_spread_points)
                or float(snap.bridge_wait_ms) >= float(self.cfg.hard_max_bridge_wait_ms)
                or float(snap.heartbeat_age_ms) >= float(self.cfg.hard_max_heartbeat_age_ms)
            ):
                return GuardState.CLOSE_ONLY, TriggerType.STRESS
            return GuardState.CAUTION, TriggerType.STRESS
        if stress_score >= float(self.cfg.halt_threshold):
            return GuardState.HALT, TriggerType.STRESS
        if stress_score >= float(self.cfg.close_only_threshold):
            return GuardState.CLOSE_ONLY, TriggerType.STRESS
        if stress_score >= float(self.cfg.defensive_threshold):
            return GuardState.DEFENSIVE, TriggerType.STRESS
        if stress_score >= float(self.cfg.caution_threshold):
            return GuardState.CAUTION, TriggerType.STRESS
        return GuardState.NORMAL, TriggerType.RECOVERY

    def _apply_hysteresis(
        self,
        *,
        now_ts: float,
        proposed_state: GuardState,
        stress_score: float,
        crash_hit: bool,
    ) -> GuardState:
        current = self._state
        if proposed_state.value == current.value:
            return current
        if self._severity(proposed_state) > self._severity(current):
            self._stable_tick_counter = 0
            return proposed_state
        if crash_hit:
            self._stable_tick_counter = 0
            return current
        if current == GuardState.NORMAL:
            return proposed_state

        if not self._recovery_threshold_ok(current, stress_score):
            self._stable_tick_counter = 0
            return current

        self._stable_tick_counter += 1
        if self._cooldown_remaining(now_ts, current) > 0.0:
            return current
        if self._stable_tick_counter < int(self.cfg.required_stable_ticks_for_recovery):
            return current
        return self._one_step_less_severe(current)

    @staticmethod
    def _severity(state: GuardState) -> int:
        if state == GuardState.NORMAL:
            return 0
        if state == GuardState.CAUTION:
            return 1
        if state == GuardState.DEFENSIVE:
            return 2
        if state == GuardState.CLOSE_ONLY:
            return 3
        return 4

    def _recovery_threshold_ok(self, state: GuardState, stress_score: float) -> bool:
        if state == GuardState.HALT:
            return bool(stress_score < float(self.cfg.halt_exit_threshold))
        if state == GuardState.CLOSE_ONLY:
            return bool(stress_score < float(self.cfg.close_only_exit_threshold))
        if state == GuardState.DEFENSIVE:
            return bool(stress_score < float(self.cfg.defensive_exit_threshold))
        if state == GuardState.CAUTION:
            return bool(stress_score < float(self.cfg.caution_exit_threshold))
        return True

    @staticmethod
    def _one_step_less_severe(state: GuardState) -> GuardState:
        if state == GuardState.HALT:
            return GuardState.CLOSE_ONLY
        if state == GuardState.CLOSE_ONLY:
            return GuardState.DEFENSIVE
        if state == GuardState.DEFENSIVE:
            return GuardState.CAUTION
        if state == GuardState.CAUTION:
            return GuardState.NORMAL
        return GuardState.NORMAL

    def _cooldown_remaining(self, now_ts: float, state: GuardState) -> float:
        if self._last_transition_ts <= 0.0:
            return 0.0
        elapsed = max(0.0, float(now_ts) - float(self._last_transition_ts))
        if state == GuardState.HALT:
            target = float(self.cfg.halt_cooldown_sec)
        elif state == GuardState.CLOSE_ONLY:
            target = float(self.cfg.close_only_cooldown_sec)
        elif state == GuardState.DEFENSIVE:
            target = float(self.cfg.defensive_cooldown_sec)
        elif state == GuardState.CAUTION:
            target = float(self.cfg.caution_cooldown_sec)
        else:
            target = 0.0
        return max(0.0, target - elapsed)

    def _map_action(self, state: GuardState) -> Tuple[GuardAction, float]:
        if state == GuardState.NORMAL:
            return GuardAction.ALLOW, 1.0
        if state == GuardState.CAUTION:
            return GuardAction.REDUCE_SIZE, float(self.cfg.caution_size_multiplier)
        if state == GuardState.DEFENSIVE:
            return GuardAction.BLOCK_NEW_TRADES, float(self.cfg.defensive_size_multiplier)
        if state == GuardState.CLOSE_ONLY:
            return GuardAction.CLOSE_ONLY, 0.0
        return GuardAction.FORCE_FLAT, 0.0

    @staticmethod
    def _dominant_reason(reasons: List[str], stress_score: float, crash_hit: bool, warm: bool) -> str:
        if reasons:
            for prefix in ("hard_cap:", "crash:", "runtime:", "stress:"):
                for reason in reasons:
                    if reason.startswith(prefix):
                        return str(reason)
            return str(reasons[0])
        if crash_hit:
            return "CRASH"
        if not warm:
            return "WARMUP_GUARDED"
        if stress_score > 0.0:
            return "STRESS_NONZERO"
        return "NONE"


def decision_to_payload(decision: GuardDecision) -> Dict[str, object]:
    return {
        "schema_version": "black_swan_guard.v2",
        "symbol": str(decision.symbol),
        "ts_monotonic": float(decision.ts_monotonic),
        "state": decision.state.value,
        "action": decision.action.value,
        "trigger": decision.trigger.value,
        "stress_score": round(float(decision.stress_score), 6),
        "size_multiplier": round(float(decision.size_multiplier), 6),
        "cooldown_remaining_sec": round(float(decision.cooldown_remaining_sec), 3),
        "frozen_baseline": bool(decision.frozen_baseline),
        "warm": bool(decision.warm),
        "dominant_reason": str(decision.dominant_reason),
        "reasons": list(decision.reasons),
        "telemetry": {str(k): round(float(v), 6) for k, v in (decision.telemetry or {}).items()},
        "integration_constraints": {
            "advisory_only": True,
            "mql5_final_authority": True,
            "force_flat_scope_must_be_defined_in_runtime": True,
            "no_direct_live_execution_from_python": True,
        },
    }
