from __future__ import annotations
import numpy as np
import datetime as dt
from typing import Any, Dict, List, Tuple
from zoneinfo import ZoneInfo

# These helpers were moved from safetybot.py
TZ_NY = ZoneInfo("America/New_York")
TZ_PL = ZoneInfo("Europe/Warsaw")
UTC = dt.timezone.utc

# Keep fallback windows aligned with SafetyBot defaults so "strategy.json missing"
# does not silently revert to an old session profile.
DEFAULT_GROUP_WINDOWS: Dict[str, List[Tuple[ZoneInfo, tuple[int, int], tuple[int, int]]]] = {
    "FX": [(TZ_PL, (9, 0), (12, 0))],
    "METAL": [(TZ_PL, (14, 0), (17, 0))],
}

def now_utc() -> dt.datetime:
    # In the future, this should use the time anchor from the main bot
    return dt.datetime.now(UTC)

def now_ny() -> dt.datetime:
    return now_utc().astimezone(TZ_NY)

def now_pl() -> dt.datetime:
    return now_utc().astimezone(TZ_PL)

def in_window(local_dt: dt.datetime, start_hm: tuple[int, int], end_hm: tuple[int, int]) -> bool:
    s = local_dt.replace(hour=start_hm[0], minute=start_hm[1], second=0, microsecond=0)
    e = local_dt.replace(hour=end_hm[0], minute=end_hm[1], second=0, microsecond=0)
    if (start_hm[0], start_hm[1]) == (end_hm[0], end_hm[1]):
        return True
    if e >= s:
        return bool(s <= local_dt <= e)

    # Overnight window support (e.g. 22:00-02:00).
    e = e + dt.timedelta(days=1)
    ref = local_dt
    if ref < s:
        ref = ref + dt.timedelta(days=1)
    return bool(s <= ref <= e)

# Forward-declare for type hinting
class Persistence:
    pass

class ActivityController:
    def __init__(self, db: Persistence, config: Any):
        self.db = db
        self.config = config

    @staticmethod
    def _norm_group(value: str) -> str:
        g = str(value or "").strip().upper()
        if g in {"METALS", "XAU"}:
            return "METAL"
        if g in {"INDICES"}:
            return "INDEX"
        return g

    @staticmethod
    def _parse_hm(raw: object, default_hm: tuple[int, int]) -> tuple[int, int]:
        if isinstance(raw, (list, tuple)) and len(raw) == 2:
            try:
                hh = int(raw[0])
                mm = int(raw[1])
                if 0 <= hh <= 23 and 0 <= mm <= 59:
                    return int(hh), int(mm)
            except Exception:
                return default_hm
        if isinstance(raw, str) and ":" in raw:
            try:
                hh_s, mm_s = raw.split(":", 1)
                hh = int(str(hh_s).strip())
                mm = int(str(mm_s).strip())
                if 0 <= hh <= 23 and 0 <= mm <= 59:
                    return int(hh), int(mm)
            except Exception:
                return default_hm
        return default_hm

    def _group_trade_windows(self, grp: str) -> List[Tuple[ZoneInfo, tuple[int, int], tuple[int, int]]]:
        """
        Dynamic windows from strategy.json are the source of truth.
        """
        out: List[Tuple[ZoneInfo, tuple[int, int], tuple[int, int]]] = []
        g = self._norm_group(grp)
        try:
            strategy = getattr(self.config, "strategy", {}) or {}
        except Exception:
            strategy = {}
        raw = strategy.get("trade_windows", {}) if isinstance(strategy, dict) else {}
        if not isinstance(raw, dict):
            return out
        for _wid, w in raw.items():
            if not isinstance(w, dict):
                continue
            wg = self._norm_group(str(w.get("group") or ""))
            if wg != g:
                continue
            tz_name = str(w.get("anchor_tz") or "Europe/Warsaw")
            try:
                tz = ZoneInfo(tz_name)
            except Exception:
                tz = TZ_PL
            start_hm = self._parse_hm(w.get("start_hm"), (0, 0))
            end_hm = self._parse_hm(w.get("end_hm"), (23, 59))
            out.append((tz, start_hm, end_hm))
        if not out:
            out.extend(DEFAULT_GROUP_WINDOWS.get(g, []))
        return out

    def time_weight(self, grp: str, symbol: str) -> float:
        n = now_ny()
        p = now_pl()
        g = self._norm_group(grp)
        # Runtime-configured trade windows are the source of truth.
        dynamic_windows = self._group_trade_windows(g)
        if dynamic_windows:
            now_ref_utc = now_utc()
            for tz, start_hm, end_hm in dynamic_windows:
                local_dt = now_ref_utc.astimezone(tz)
                if in_window(local_dt, start_hm, end_hm):
                    return 1.0
            return 0.25
        if g == "INDEX":
            prof = self.config.index_profile_map.get(symbol_base(symbol), "GEN")
            if prof == "EU":
                if in_window(p, (9, 0), (12, 0)): return 0.9
                if in_window(p, (12, 0), (15, 0)): return 0.6
                if in_window(p, (15, 0), (17, 35)): return 1.0
                return 0.25
            if prof == "US":
                if in_window(n, (9, 30), (11, 0)) or in_window(n, (15, 0), (16, 0)): return 1.0
                if in_window(n, (11, 0), (15, 0)): return 0.6
                return 0.25
            return 0.35
        return 0.2

    def score_factor(self, grp: str, symbol: str) -> float:
        ny_hour = now_ny().hour
        req = self.db.price_req_for_hour(grp, symbol, ny_hour, lookback_days=14)
        pnl = self.db.pnl_net_for_hour(grp, symbol, ny_hour, lookback_days=14)
        try:
            strat = getattr(self.config, "strategy", {}) or {}
        except Exception:
            strat = {}

        # Edge minus execution-cost proxy.
        spread_penalty_w = float(strat.get("score_spread_penalty_weight", 0.030))
        score_scale = float(strat.get("score_edge_scale", 2.0))
        req_soft_cap = float(strat.get("score_req_soft_cap", 120.0))
        req_penalty_w = float(strat.get("score_req_penalty_weight", 0.10))

        spread_p80 = 0.0
        try:
            spread_p80 = float(self.db.get_p80_spread(symbol))
        except Exception:
            spread_p80 = 0.0

        edge_per_req = float(pnl) / max(1.0, float(req))
        edge_minus_cost = edge_per_req - (spread_penalty_w * max(0.0, spread_p80))
        x = np.tanh(edge_minus_cost / max(1e-6, score_scale))

        req_pressure = min(1.0, float(req) / max(1.0, req_soft_cap))
        factor = 1.0 + 0.35 * x - req_penalty_w * req_pressure
        return float(min(1.35, max(0.60, factor)))

    def mode(self, grp: str, symbol: str, rollover_safe: bool) -> str:
        if not rollover_safe:
            return "ECO"
        w = self.time_weight(grp, symbol)
        f = self.score_factor(grp, symbol)
        base = w * f
        if base >= 0.95:
            return "HOT"
        if base >= 0.55:
            return "WARM"
        return "ECO"

    def max_symbols_per_iter(self, mode: str) -> int:
        if mode == "HOT": return self.config.scheduler["max_symbols_per_iter_hot"]
        if mode == "WARM": return self.config.scheduler["max_symbols_per_iter_warm"]
        return self.config.scheduler["max_symbols_per_iter_eco"]

    def m5_pull_period(self, mode: str) -> int:
        if mode == "HOT": return self.config.scheduler["m5_pull_sec_hot"]
        if mode == "WARM": return self.config.scheduler["m5_pull_sec_warm"]
        return self.config.scheduler["m5_pull_sec_eco"]

    def positions_poll_period(self, mode: str) -> int:
        if mode == "HOT": return self.config.scheduler["positions_poll_sec_hot"]
        if mode == "WARM": return self.config.scheduler["positions_poll_sec_warm"]
        return self.config.scheduler["positions_poll_sec_eco"]

def symbol_base(raw_symbol: str) -> str:
    return raw_symbol.split(".")[0]
