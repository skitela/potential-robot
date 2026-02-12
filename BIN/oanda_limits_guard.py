import json
import threading
import time
import datetime as dt
from pathlib import Path
from typing import List, Optional


class OandaLimitsGuard:
    """Central guard for OANDA TMS (PL) MT5 operational limits."""

    def __init__(
        self,
        persistence,
        evidence_dir: Path,
        warn_day: int,
        hard_stop_day: int,
        orders_per_sec: int,
        positions_pending_limit: int,
    ):
        self.db = persistence
        self.evidence_dir = Path(evidence_dir)
        self.warn_day = int(warn_day)
        self.hard_stop_day = int(hard_stop_day)
        self.orders_per_sec = int(orders_per_sec)
        self.positions_pending_limit = int(positions_pending_limit)
        self._lock = threading.Lock()
        self._order_ts: List[float] = []

    def _utc_day_id(self, now_ts: Optional[float] = None) -> str:
        if now_ts is None:
            now_ts = time.time()
        return dt.datetime.fromtimestamp(float(now_ts), tz=dt.timezone.utc).strftime("%Y%m%d")

    def _state_get(self, key: str, default: str = "0") -> str:
        return str(self.db.state_get(key, default))

    def _state_set(self, key: str, value: str) -> None:
        self.db.state_set(key, str(value))

    def _load_rolling(self) -> List[int]:
        raw = self._state_get("oanda_limits:price:rolling_24h", "[]")
        try:
            data = json.loads(raw)
            if isinstance(data, list):
                return [int(x) for x in data if isinstance(x, (int, float, str))]
        except Exception:
            return []
        return []

    def _save_rolling(self, items: List[int]) -> None:
        self._state_set("oanda_limits:price:rolling_24h", json.dumps([int(x) for x in items]))

    def _get_safe_mode_reason(self) -> str:
        return str(self._state_get("oanda_limits:safe_mode_reason", ""))

    def _set_safe_mode(self, reason: str) -> None:
        if not reason:
            return
        self._state_set("oanda_limits:safe_mode_reason", str(reason))
        self._state_set("oanda_limits:safe_mode_ts", str(int(time.time())))

    def safe_mode_active(self) -> bool:
        return bool(self._get_safe_mode_reason())

    def _write_state(self, now_ts: Optional[float] = None) -> None:
        if now_ts is None:
            now_ts = time.time()
        utc_day = self._utc_day_id(now_ts)
        utc_count = int(self._state_get(f"oanda_limits:price:utc:{utc_day}", "0"))
        rolling = self._load_rolling()
        data = {
            "utc_day_id": utc_day,
            "utc_day_count": int(utc_count),
            "rolling_24h_count": int(len(rolling)),
            "orders_per_sec_window": int(len(self._order_ts)),
            "last_safe_mode_reason": self._get_safe_mode_reason(),
            "safe_mode_active": bool(self.safe_mode_active()),
            "updated_ts": int(now_ts),
        }
        self.evidence_dir.mkdir(parents=True, exist_ok=True)
        tmp = self.evidence_dir / "oanda_limits_state.json.tmp"
        out = self.evidence_dir / "oanda_limits_state.json"
        tmp.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")
        tmp.replace(out)

    def write_state(self, now_ts: Optional[float] = None) -> None:
        self._write_state(now_ts)

    def _increment_utc_day(self, now_ts: Optional[float] = None) -> int:
        utc_day = self._utc_day_id(now_ts)
        key_day = "oanda_limits:price:utc_day_id"
        key_count = f"oanda_limits:price:utc:{utc_day}"
        last_day = self._state_get(key_day, "")
        if last_day != utc_day:
            self._state_set(key_day, utc_day)
            self._state_set(key_count, "0")
        cur = int(self._state_get(key_count, "0"))
        cur += 1
        self._state_set(key_count, str(cur))
        return cur

    def note_price_request(self, now_ts: Optional[float] = None, emergency: bool = False) -> bool:
        if now_ts is None:
            now_ts = time.time()
        with self._lock:
            utc_count = self._increment_utc_day(now_ts)
            rolling = self._load_rolling()
            cutoff = int(float(now_ts)) - 24 * 3600
            rolling = [int(t) for t in rolling if int(t) >= cutoff]
            rolling.append(int(now_ts))
            self._save_rolling(rolling)

            if (utc_count >= self.hard_stop_day) or (len(rolling) >= self.hard_stop_day):
                if not self.safe_mode_active():
                    reason = "PRICE_HARD_STOP_UTC" if utc_count >= self.hard_stop_day else "PRICE_HARD_STOP_ROLLING"
                    self._set_safe_mode(reason)
            self._write_state(now_ts)

            if (not emergency) and self.safe_mode_active():
                return False
            return True

    def allow_price_request(self, emergency: bool = False) -> bool:
        if (not emergency) and self.safe_mode_active():
            return False
        return True

    def allow_order_submit(self, now_ts: Optional[float] = None, emergency: bool = False) -> bool:
        if now_ts is None:
            now_ts = time.time()
        if (not emergency) and self.safe_mode_active():
            self._write_state(now_ts)
            return False
        with self._lock:
            self._order_ts = [t for t in self._order_ts if (now_ts - float(t)) < 1.0]
            if len(self._order_ts) >= int(self.orders_per_sec):
                self._write_state(now_ts)
                return False
            self._order_ts.append(float(now_ts))
            self._write_state(now_ts)
            return True

    def allow_positions_pending(self, total: int, emergency: bool = False) -> bool:
        if (not emergency) and self.safe_mode_active():
            return False
        if int(total) >= int(self.positions_pending_limit):
            return False
        return True

    def warn_level_reached(self, now_ts: Optional[float] = None) -> bool:
        if now_ts is None:
            now_ts = time.time()
        utc_day = self._utc_day_id(now_ts)
        utc_count = int(self._state_get(f"oanda_limits:price:utc:{utc_day}", "0"))
        rolling = self._load_rolling()
        cutoff = int(float(now_ts)) - 24 * 3600
        rolling = [int(t) for t in rolling if int(t) >= cutoff]
        return (utc_count >= self.warn_day) or (len(rolling) >= self.warn_day)
