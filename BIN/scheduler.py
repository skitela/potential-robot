from __future__ import annotations
import numpy as np
import datetime as dt
from typing import Any, Dict
from zoneinfo import ZoneInfo

# These helpers were moved from safetybot.py
TZ_NY = ZoneInfo("America/New_York")
TZ_PL = ZoneInfo("Europe/Warsaw")
UTC = dt.timezone.utc

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
    return s <= local_dt <= e

# Forward-declare for type hinting
class Persistence:
    pass

class ActivityController:
    def __init__(self, db: Persistence, config: Any):
        self.db = db
        self.config = config

    def time_weight(self, grp: str, symbol: str) -> float:
        n = now_ny()
        p = now_pl()
        if grp == "FX":
            if in_window(n, (8, 0), (12, 0)): return 1.0
            if in_window(n, (3, 0), (8, 0)) or in_window(n, (12, 0), (16, 0)): return 0.6
            return 0.25
        if grp == "METAL":
            if in_window(n, (7, 0), (13, 0)): return 1.0
            if in_window(n, (3, 0), (7, 0)) or in_window(n, (13, 0), (16, 30)): return 0.6
            return 0.25
        if grp == "INDEX":
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
        if req < 50:
            return 1.0
        score = pnl / max(1.0, float(req))
        x = np.tanh(score / 2.0)
        return float(1.0 + 0.3 * x)

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
