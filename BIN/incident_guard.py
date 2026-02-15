from __future__ import annotations

import datetime as dt
import json
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

UTC = dt.timezone.utc


def _now_iso_utc() -> str:
    return dt.datetime.now(tz=UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _parse_iso_utc(s: str) -> Optional[dt.datetime]:
    if not s:
        return None
    try:
        ss = str(s).strip()
        if ss.endswith("Z"):
            ss = ss[:-1] + "+00:00"
        d = dt.datetime.fromisoformat(ss)
        if d.tzinfo is None:
            d = d.replace(tzinfo=UTC)
        return d.astimezone(UTC)
    except Exception:
        return None


def classify_retcode(retcode_num: int, retcode_name: str = "") -> Tuple[str, str]:
    """Map MT5 retcode into incident class and severity."""
    n = int(retcode_num)
    name = str(retcode_name or "").upper()

    if n in (10008, 10009, 10010):
        return ("ok", "INFO")

    if n in (10018, 10021, 10024, 10033, 10034, 10040):
        return ("execution", "WARN")
    if n in (10004, 10020, 10015, 10016):
        return ("execution", "WARN")
    if n in (10012, 10031, 10011):
        return ("system", "ERROR")
    if n in (10017, 10026, 10027):
        return ("broker_policy", "ERROR")
    if n in (10028, 10029):
        return ("execution", "ERROR")
    if n in (10042, 10043, 10044, 10045, 10046):
        return ("broker_policy", "WARN")
    if n == 10019 or "NO_MONEY" in name:
        return ("risk", "CRITICAL")
    if n <= 0:
        return ("system", "ERROR")
    return ("unknown", "WARN")


@dataclass(slots=True)
class IncidentPolicy:
    max_line_len: int = 4096
    read_tail_max_lines: int = 4000


class IncidentJournal:
    """Append-only incident journal used by canary/drift health checks."""

    def __init__(self, logs_dir: Path, policy: IncidentPolicy | None = None, file_name: str = "incident_journal.jsonl"):
        self.policy = policy or IncidentPolicy()
        self.logs_dir = Path(logs_dir)
        self.logs_dir.mkdir(parents=True, exist_ok=True)
        self.path = self.logs_dir / str(file_name)

    def append(self, event: Dict[str, Any]) -> None:
        ev = dict(event or {})
        ev.setdefault("ts_utc", _now_iso_utc())
        line = json.dumps(ev, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        if len(line) > int(self.policy.max_line_len):
            line = line[: int(self.policy.max_line_len)]
        with open(self.path, "a", encoding="utf-8", newline="\n") as f:
            f.write(line + "\n")
            f.flush()
            os.fsync(f.fileno())

    def note_retcode(
        self,
        *,
        symbol: str,
        retcode_num: int,
        retcode_name: str,
        emergency: bool = False,
        attempt: int = 1,
        source: str = "order_send",
    ) -> None:
        cls, sev = classify_retcode(int(retcode_num), str(retcode_name))
        self.append(
            {
                "type": "retcode",
                "class": cls,
                "severity": sev,
                "source": str(source),
                "symbol": str(symbol or ""),
                "retcode_num": int(retcode_num),
                "retcode_name": str(retcode_name or ""),
                "emergency": int(bool(emergency)),
                "attempt": int(max(1, attempt)),
            }
        )

    def note_guard(
        self,
        *,
        guard: str,
        reason: str,
        severity: str = "WARN",
        category: str = "model",
        symbol: str = "",
        extra: Optional[Dict[str, Any]] = None,
    ) -> None:
        ev = {
            "type": "guard",
            "class": str(category or "model"),
            "severity": str(severity or "WARN").upper(),
            "source": str(guard or ""),
            "symbol": str(symbol or ""),
            "reason": str(reason or ""),
        }
        if isinstance(extra, dict):
            for k, v in extra.items():
                if k not in ev:
                    ev[k] = v
        self.append(ev)

    def recent_counts(self, lookback_sec: int = 3600) -> Dict[str, int]:
        now = dt.datetime.now(tz=UTC)
        cutoff = now - dt.timedelta(seconds=max(1, int(lookback_sec)))
        out = {
            "total": 0,
            "warn_or_worse": 0,
            "error_or_worse": 0,
            "critical": 0,
            "execution": 0,
            "system": 0,
            "broker_policy": 0,
            "risk": 0,
            "model": 0,
            "regime": 0,
            "unknown": 0,
        }
        if not self.path.exists():
            return out
        try:
            lines = self.path.read_text(encoding="utf-8", errors="ignore").splitlines()
        except Exception:
            return out
        tail = lines[-int(max(1, self.policy.read_tail_max_lines)) :]
        for ln in tail:
            ln = str(ln or "").strip()
            if not ln:
                continue
            try:
                ev = json.loads(ln)
                ts = _parse_iso_utc(str(ev.get("ts_utc") or ""))
                if ts is None or ts < cutoff:
                    continue
                out["total"] += 1
                sev = str(ev.get("severity") or "").upper()
                cls = str(ev.get("class") or "unknown").lower()
                if cls in out:
                    out[cls] += 1
                else:
                    out["unknown"] += 1
                if sev in {"WARN", "ERROR", "CRITICAL"}:
                    out["warn_or_worse"] += 1
                if sev in {"ERROR", "CRITICAL"}:
                    out["error_or_worse"] += 1
                if sev == "CRITICAL":
                    out["critical"] += 1
            except Exception:
                continue
        return out
