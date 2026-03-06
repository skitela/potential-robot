from __future__ import annotations

"""
OANDA_MT5_SYSTEM — ostrożny wdrażacz profili dla wykonawców krajowych
====================================================================

Cel modułu:
- odczytać paczkę propozycji profili,
- sprawdzić jej spójność,
- odczytać stan systemu i stan wykonania,
- wybrać profil dla każdego instrumentu,
- zapisać wynik atomowo,
- zostawić pełny ślad rozliczeniowy,
- nie zmieniać samoczynnie ryzyka kapitału.

Uzasadnienie projektowe
----------------------
1. Powiązanie wyboru profilu ze stanem ścieżki zleceń jest zasadne,
   bo dobra historia nie ma wartości, gdy wykonanie zaczyna się dławić.
2. Powiązanie wyboru profilu z jakością łączności i z odsetkiem przekroczeń
   czasu chroni rachunek przed wejściem w rynek w chwili, gdy system nie nadąża.
3. Rozdzielenie progów wykonawczych od ryzyka kapitału jest konieczne,
   bo automat może zaostrzać lub łagodzić filtr wejścia, ale nie może sam
   zmieniać wielkości ryzyka na rachunku.
4. Okres wstrzymania po zmianie profilu ogranicza szarpanie ustawieniami,
   dzięki czemu system nie przeskakuje nerwowo między trybami.
5. Zgodność nazw progów z rzeczywistymi plikami etapu pierwszego jest konieczna,
   bo brak tej zgodności prowadzi do cichego gubienia danych lub do błędnej odmowy wdrożenia.

Uwagi wykonawcze
----------------
- Moduł żyje poza gorącą ścieżką wejścia w zlecenie.
- Ostateczna zgoda albo odmowa wejścia należy do warstwy MQL5.
- Moduł nie dotyka kluczy ryzyka kapitału.
- Moduł jest ostrożnym urzędnikiem od wdrożeń, a nie strategią handlową.
"""

import argparse
import copy
import dataclasses
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta, timezone
import hashlib
import json
import logging
import os
from pathlib import Path
import sqlite3
import tempfile
import time
import uuid
from typing import Any, Dict, Iterable, List, Optional, Protocol, Tuple

try:
    from TOOLS.lab_guardrails import ensure_write_parent, resolve_lab_data_root
except Exception:  # pragma: no cover
    from lab_guardrails import ensure_write_parent, resolve_lab_data_root

LOG = logging.getLogger("auto_deployer_kontraktorzy_pl_v3")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
)

PROPOSAL_SCHEMA_VALUES = {
    "proposal_pack_v1",
    "oanda.mt5.stage1_profile_pack.v1",
}
APPROVAL_SCHEMA = "oanda.mt5.stage1_manual_approval.v1"
LIVE_SCHEMA_VERSION = "live_config_v3"

# Klucze ryzyka kapitału są nienaruszalne dla automatu.
RISK_LOCKED_KEYS = {
    "risk_per_trade",
    "risk_per_trade_pct",
    "risk_per_trade_max_pct",
    "max_daily_drawdown",
    "max_daily_drawdown_pct",
    "max_weekly_drawdown",
    "max_weekly_drawdown_pct",
    "max_open_positions",
    "max_global_exposure",
    "max_series_loss",
    "capital_risk_mode",
    "account_risk_mode",
    "lot_sizing_mode",
    "fixed_lot",
    "kelly_fraction",
    "max_loss_account_ccy_day",
    "max_loss_account_ccy_week",
    "crypto_major_max_open_positions",
}

# Nazwy kanoniczne zgodne z rzeczywistą paczką z etapu pierwszego.
CANONICAL_THRESHOLD_KEYS = {
    "spread_cap_points",
    "signal_score_threshold",
    "max_latency_ms",
    "min_tradeability_score",
    "min_setup_quality_score",
    "min_liquidity_score",
}

# Zgodność wsteczna z wcześniejszym szkieletem.
THRESHOLD_ALIASES = {
    "max_spread_points": "spread_cap_points",
    "min_signal_quality_score": "signal_score_threshold",
    "min_signal_score": "signal_score_threshold",
    "max_latency_ms": "max_latency_ms",
    "min_tradeability_score": "min_tradeability_score",
    "min_setup_quality_score": "min_setup_quality_score",
    "min_setup_score": "min_setup_quality_score",
    "spread_cap_points": "spread_cap_points",
    "signal_score_threshold": "signal_score_threshold",
    "min_liquidity_score": "min_liquidity_score",
}

THRESHOLD_BOUNDS = {
    "spread_cap_points": {"min": 0.1, "max": 300.0},
    "signal_score_threshold": {"min": 0.0, "max": 100.0},
    "max_latency_ms": {"min": 10.0, "max": 5000.0},
    "min_tradeability_score": {"min": 0.0, "max": 1.0},
    "min_setup_quality_score": {"min": 0.0, "max": 1.0},
    "min_liquidity_score": {"min": 0.0, "max": 1.0},
}

PROFILE_KEY_ALIASES = {
    "conservative": "conservative",
    "balanced": "balanced",
    "aggressive": "aggressive",
    "bezpieczny": "conservative",
    "sredni": "balanced",
    "odwazniejszy": "aggressive",
    "BEZPIECZNY": "conservative",
    "SREDNI": "balanced",
    "ODWAZNIEJSZY": "aggressive",
}

PROFILE_LABEL_PL = {
    "conservative": "bezpieczny",
    "balanced": "sredni",
    "aggressive": "odwazniejszy",
    "EMERGENCY": "awaryjny",
}

DEFAULT_GLOBAL_DD_HALT_LIMIT_PCT = 2.0
DEFAULT_TRADE_PATH_TIMEOUT_HALT = 0.05
DEFAULT_HEARTBEAT_TIMEOUT_WARN = 0.10
DEFAULT_TRADE_PATH_TIMEOUT_OK = 0.02
DEFAULT_TRADE_PATH_P99_WARN_MS = 1200.0
DEFAULT_HEARTBEAT_P99_WARN_MS = 1800.0
DEFAULT_MIN_INSTRUMENT_TRADES_FOR_AGGR = 5
DEFAULT_PROFILE_COOLDOWN_MINUTES = 60


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def iso_utc(dt: Optional[datetime] = None) -> str:
    return (dt or utcnow()).astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_iso_utc(raw: Any) -> Optional[datetime]:
    text = str(raw or "").strip()
    if not text:
        return None
    try:
        out = datetime.fromisoformat(text.replace("Z", "+00:00"))
        if out.tzinfo is None:
            out = out.replace(tzinfo=timezone.utc)
        return out.astimezone(timezone.utc)
    except Exception:
        return None


def symbol_base(sym: Any) -> str:
    s = str(sym or "").strip().upper()
    if not s:
        return ""
    for sep in (".", "-", "_"):
        if sep in s:
            s = s.split(sep, 1)[0]
    return s


def json_default(obj: Any):
    if isinstance(obj, datetime):
        return iso_utc(obj)
    if dataclasses.is_dataclass(obj):
        return asdict(obj)
    raise TypeError(f"Nie można zapisać typu: {type(obj)}")


def canonical_json_dumps(payload: Dict[str, Any]) -> str:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False, default=json_default)


def sha256_hex(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def compute_hash_without_field(payload: Dict[str, Any], field_name: str = "config_hash") -> str:
    obj = copy.deepcopy(payload)
    obj.pop(field_name, None)
    return sha256_hex(canonical_json_dumps(obj))


def atomic_write_json(path: str, payload: Dict[str, Any]) -> str:
    """
    Zapis atomowy:
    - obliczenie skrótu,
    - zapis do pliku tymczasowego,
    - wymuszenie zapisu na dysk,
    - podmiana w jednym kroku.
    """
    obj = copy.deepcopy(payload)
    obj["config_hash"] = compute_hash_without_field(obj, "config_hash")

    raw = json.dumps(obj, ensure_ascii=False, indent=2, sort_keys=True, default=json_default)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".tmp_live_config_", suffix=".json", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(raw)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass
    return str(obj["config_hash"])


@dataclass
class ProposalScores:
    net_score: float = 0.0
    stability_score: float = 0.0
    runtime_safety_score: float = 0.0
    coverage_score: float = 0.0
    overall_score: float = 0.0


@dataclass
class ProposalProfile:
    profile_key: str
    profile_label: str
    profile_id: str
    sample_count: int
    thresholds: Dict[str, float]
    scores: ProposalScores
    warnings: List[str] = field(default_factory=list)
    validation_summary: Dict[str, Any] = field(default_factory=dict)
    source_block: Dict[str, Any] = field(default_factory=dict)


@dataclass
class InstrumentProposal:
    instrument: str
    profiles: Dict[str, ProposalProfile]


@dataclass
class ProposalPack:
    schema_version: str
    generated_at: str
    proposal_id: str
    config_hash: str
    integrity_mode: str
    source_model_version: str
    instruments: Dict[str, InstrumentProposal]
    notes: List[str] = field(default_factory=list)


@dataclass
class InstrumentHealth:
    instrument: str
    recent_pnl_account_ccy: float = 0.0
    trade_count: int = 0
    win_rate: Optional[float] = None
    expectancy_net: Optional[float] = None
    dd_estimate_account_ccy: Optional[float] = None
    dd_estimate_pct: Optional[float] = None
    has_sufficient_sample: bool = False


@dataclass
class GlobalHealth:
    recent_pnl_account_ccy: float = 0.0
    trade_count: int = 0
    account_dd_pct: float = 0.0
    halted: bool = False
    halt_reason: Optional[str] = None
    drawdown_source: Optional[str] = None


@dataclass
class PathHealth:
    timeout_rate: float = 0.0
    sample_n: int = 0
    p95_bridge_wait_ms: Optional[float] = None
    p99_bridge_wait_ms: Optional[float] = None
    top_timeout_reason: Optional[str] = None


@dataclass
class RuntimeHealthSplit:
    instrument: str
    heartbeat_path: PathHealth = field(default_factory=PathHealth)
    trade_path: PathHealth = field(default_factory=PathHealth)
    overall: PathHealth = field(default_factory=PathHealth)


@dataclass
class LiveInstrumentConfig:
    active_profile: str
    profile_label_pl: str
    profile_id: str
    canary_mode: bool
    canary_fraction: float
    cooldown_until: Optional[str]
    thresholds: Dict[str, float]
    reason_for_change: str
    rejected_profiles: List[Dict[str, Any]] = field(default_factory=list)
    deployment_meta: Dict[str, Any] = field(default_factory=dict)


class HealthMetricsProvider(Protocol):
    def get_global_health(self, lookback_hours: int = 24) -> GlobalHealth: ...
    def get_instrument_health(self, instrument: str, lookback_hours: int = 24) -> InstrumentHealth: ...
    def get_runtime_health_split(self, instrument: str, lookback_hours: int = 24) -> RuntimeHealthSplit: ...


@dataclass
class _AuditAgg:
    sent: int = 0
    timeout: int = 0
    waits_ms: List[float] = field(default_factory=list)
    timeout_reasons: Dict[str, int] = field(default_factory=dict)

    def add_timeout_reason(self, reason: str) -> None:
        key = str(reason or "UNKNOWN")
        self.timeout_reasons[key] = int(self.timeout_reasons.get(key, 0) + 1)


class LocalSQLiteAuditHealthProvider:
    """
    Provider zgodny z aktualnym środowiskiem:
    - instrument/global health: DB/decision_events.sqlite
    - runtime split: LOGS/audit_trail.jsonl
    """

    def __init__(self, db_path: Path, audit_path: Path):
        self.db_path = Path(db_path).resolve()
        self.audit_path = Path(audit_path).resolve()
        self._cache: Dict[Tuple[int, int, int], Dict[str, Any]] = {}

    @staticmethod
    def _percentile(values: List[float], p: float) -> Optional[float]:
        if not values:
            return None
        arr = sorted(float(v) for v in values)
        idx = min(len(arr) - 1, int((len(arr) - 1) * p))
        return float(arr[idx])

    @staticmethod
    def _normalize_cmd_type(raw: Any) -> str:
        text = str(raw or "").strip().upper()
        if not text:
            return "OTHER"
        if "HEARTBEAT" in text:
            return "HEARTBEAT"
        if "TRADE_PATH" in text or text == "TRADE" or "TRADE" in text:
            return "TRADE_PATH"
        return "OTHER"

    @staticmethod
    def _extract_symbol(data: Dict[str, Any]) -> str:
        sym = symbol_base(data.get("symbol"))
        if sym:
            return sym
        details = data.get("details") if isinstance(data.get("details"), dict) else {}
        sym = symbol_base(details.get("symbol"))
        if sym:
            return sym
        payload = data.get("payload") if isinstance(data.get("payload"), dict) else {}
        return symbol_base(payload.get("symbol"))

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        return conn

    def _read_runtime_cache(self, lookback_hours: int) -> Dict[str, Any]:
        if not self.audit_path.exists():
            return {"heartbeat": _AuditAgg(), "trade_by_symbol": {}}

        stat = self.audit_path.stat()
        cache_key = (int(lookback_hours), int(stat.st_mtime_ns), int(stat.st_size))
        if cache_key in self._cache:
            return self._cache[cache_key]

        cutoff = utcnow() - timedelta(hours=max(1, int(lookback_hours)))
        heartbeat = _AuditAgg()
        trade_by_symbol: Dict[str, _AuditAgg] = {}

        with self.audit_path.open("r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                if not isinstance(obj, dict):
                    continue
                ts = parse_iso_utc(obj.get("timestamp_utc"))
                if ts is None or ts < cutoff:
                    continue

                event_type = str(obj.get("event_type") or "").strip().upper()
                data = obj.get("data") if isinstance(obj.get("data"), dict) else {}
                cmd_type = self._normalize_cmd_type(data.get("command_type"))
                if cmd_type not in {"HEARTBEAT", "TRADE_PATH"}:
                    continue

                if cmd_type == "HEARTBEAT":
                    agg = heartbeat
                else:
                    sym = self._extract_symbol(data) or "__UNKNOWN__"
                    agg = trade_by_symbol.setdefault(sym, _AuditAgg())

                if event_type == "COMMAND_SENT":
                    agg.sent += 1
                    continue
                if event_type == "COMMAND_TIMEOUT":
                    agg.timeout += 1
                    reason = str(data.get("bridge_timeout_reason") or data.get("reason") or "UNKNOWN")
                    subreason = str(data.get("bridge_timeout_subreason") or "")
                    if subreason:
                        reason = f"{reason}:{subreason}"
                    agg.add_timeout_reason(reason)
                    continue
                if event_type == "REPLY_RECEIVED":
                    try:
                        agg.waits_ms.append(float(data.get("wait_ms")))
                    except Exception:
                        continue

        payload = {"heartbeat": heartbeat, "trade_by_symbol": trade_by_symbol}
        self._cache = {cache_key: payload}
        return payload

    def _agg_to_path_health(self, agg: _AuditAgg) -> PathHealth:
        sent_n = int(agg.sent)
        wait_n = len(agg.waits_ms)
        sample_n = sent_n if sent_n > 0 else wait_n
        timeout_rate = float(agg.timeout) / float(sent_n) if sent_n > 0 else 0.0
        p95 = self._percentile(agg.waits_ms, 0.95)
        p99 = self._percentile(agg.waits_ms, 0.99)
        top_reason = None
        if agg.timeout_reasons:
            top_reason = sorted(agg.timeout_reasons.items(), key=lambda item: item[1], reverse=True)[0][0]
        return PathHealth(
            timeout_rate=float(timeout_rate),
            sample_n=int(sample_n),
            p95_bridge_wait_ms=p95,
            p99_bridge_wait_ms=p99,
            top_timeout_reason=top_reason,
        )

    def get_global_health(self, lookback_hours: int = 24) -> GlobalHealth:
        if not self.db_path.exists():
            return GlobalHealth(drawdown_source="UNKNOWN_DB_MISSING")
        cutoff_iso = iso_utc(utcnow() - timedelta(hours=max(1, int(lookback_hours))))
        query = """
        SELECT
            COUNT(*) AS trade_count,
            COALESCE(SUM(CASE WHEN outcome_pnl_net IS NOT NULL THEN outcome_pnl_net ELSE 0 END), 0) AS pnl
        FROM decision_events
        WHERE ts_utc >= ?
        """
        with self._connect() as conn:
            row = conn.execute(query, (cutoff_iso,)).fetchone()
            trade_count = int(row["trade_count"] or 0) if row else 0
            pnl = float(row["pnl"] or 0.0) if row else 0.0
        return GlobalHealth(
            recent_pnl_account_ccy=pnl,
            trade_count=trade_count,
            account_dd_pct=0.0,
            halted=False,
            halt_reason=None,
            drawdown_source="UNKNOWN_NO_EQUITY_DD_SOURCE",
        )

    def get_instrument_health(self, instrument: str, lookback_hours: int = 24) -> InstrumentHealth:
        sym = symbol_base(instrument)
        if not self.db_path.exists():
            return InstrumentHealth(instrument=sym, has_sufficient_sample=False)
        cutoff_iso = iso_utc(utcnow() - timedelta(hours=max(1, int(lookback_hours))))
        query = """
        SELECT
            COUNT(*) AS trade_count,
            COALESCE(SUM(CASE WHEN outcome_pnl_net IS NOT NULL THEN outcome_pnl_net ELSE 0 END), 0) AS pnl,
            AVG(CASE WHEN outcome_pnl_net IS NOT NULL THEN outcome_pnl_net ELSE NULL END) AS expectancy_net,
            AVG(
                CASE
                    WHEN outcome_pnl_net IS NULL THEN NULL
                    WHEN outcome_pnl_net > 0 THEN 1.0
                    ELSE 0.0
                END
            ) AS win_rate
        FROM decision_events
        WHERE ts_utc >= ?
          AND choice_A = ?
        """
        with self._connect() as conn:
            row = conn.execute(query, (cutoff_iso, sym)).fetchone()
            trade_count = int(row["trade_count"] or 0) if row else 0
            pnl = float(row["pnl"] or 0.0) if row else 0.0
            expectancy_net = float(row["expectancy_net"]) if row and row["expectancy_net"] is not None else None
            win_rate = float(row["win_rate"]) if row and row["win_rate"] is not None else None
        return InstrumentHealth(
            instrument=sym,
            recent_pnl_account_ccy=pnl,
            trade_count=trade_count,
            win_rate=win_rate,
            expectancy_net=expectancy_net,
            has_sufficient_sample=(trade_count >= DEFAULT_MIN_INSTRUMENT_TRADES_FOR_AGGR),
        )

    def get_runtime_health_split(self, instrument: str, lookback_hours: int = 24) -> RuntimeHealthSplit:
        cache = self._read_runtime_cache(lookback_hours)
        hb_agg = cache.get("heartbeat", _AuditAgg())
        trade_map = cache.get("trade_by_symbol", {})
        sym = symbol_base(instrument)
        tr_agg = trade_map.get(sym, _AuditAgg())

        hb = self._agg_to_path_health(hb_agg)
        tr = self._agg_to_path_health(tr_agg)
        total_n = int(hb.sample_n + tr.sample_n)
        weighted_timeout = 0.0
        if total_n > 0:
            weighted_timeout = (hb.timeout_rate * hb.sample_n + tr.timeout_rate * tr.sample_n) / float(total_n)
        overall = PathHealth(timeout_rate=float(weighted_timeout), sample_n=total_n)
        return RuntimeHealthSplit(instrument=sym, heartbeat_path=hb, trade_path=tr, overall=overall)


class AuditLogger(Protocol):
    def log(self, record: Dict[str, Any]) -> None: ...


class JsonlAuditLogger:
    def __init__(self, path: str):
        self.path = path
        os.makedirs(os.path.dirname(path), exist_ok=True)

    def log(self, record: Dict[str, Any]) -> None:
        line = json.dumps(record, ensure_ascii=False, sort_keys=True, default=json_default)
        with open(self.path, "a", encoding="utf-8") as f:
            f.write(line + "\n")


class CooldownStateStore:
    def __init__(self, path: str):
        self.path = path
        self.state = self._load()

    def _load(self) -> Dict[str, Any]:
        if not os.path.exists(self.path):
            return {"instruments": {}}
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                payload = json.load(f)
                return payload if isinstance(payload, dict) else {"instruments": {}}
        except Exception:
            return {"instruments": {}}

    def save(self) -> None:
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        atomic_write_json(self.path, self.state)

    def get_instrument_state(self, instrument: str) -> Dict[str, Any]:
        return self.state.setdefault("instruments", {}).setdefault(instrument, {})


class ContractError(Exception):
    pass


def require_keys(block: Dict[str, Any], keys: Iterable[str], where: str) -> None:
    missing = [key for key in keys if key not in block]
    if missing:
        raise ContractError(f"{where}: brakuje pól {missing}")


def deep_find_locked(obj: Any, path: str = "") -> List[str]:
    hits: List[str] = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            p = f"{path}.{k}" if path else str(k)
            if str(k) in RISK_LOCKED_KEYS:
                hits.append(p)
            hits.extend(deep_find_locked(v, p))
    elif isinstance(obj, list):
        for idx, v in enumerate(obj):
            hits.extend(deep_find_locked(v, f"{path}[{idx}]"))
    return hits


def normalize_profile_key(value: Any) -> Optional[str]:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    return PROFILE_KEY_ALIASES.get(text, PROFILE_KEY_ALIASES.get(text.lower()))


def normalize_signal_threshold(value: float) -> float:
    # W starszym szkielecie próg sygnału bywał zapisany jako 0..1.
    # W paczce z etapu pierwszego występuje jako 0..100.
    if 0.0 <= value <= 1.0:
        return float(value * 100.0)
    return float(value)


def normalize_thresholds(thresholds_raw: Dict[str, Any]) -> Dict[str, float]:
    out: Dict[str, float] = {}
    for raw_key, raw_value in thresholds_raw.items():
        if raw_key in RISK_LOCKED_KEYS:
            continue
        canonical_key = THRESHOLD_ALIASES.get(raw_key)
        if canonical_key is None:
            continue
        try:
            numeric = float(raw_value)
        except Exception as exc:
            raise ContractError(f"Próg {raw_key} nie jest liczbą: {raw_value}") from exc

        if canonical_key == "signal_score_threshold":
            numeric = normalize_signal_threshold(numeric)

        bounds = THRESHOLD_BOUNDS.get(canonical_key)
        if bounds:
            numeric = max(bounds["min"], min(bounds["max"], numeric))
        out[canonical_key] = float(numeric)

    required_min = ["spread_cap_points", "signal_score_threshold", "max_latency_ms"]
    missing = [name for name in required_min if name not in out]
    if missing:
        raise ContractError(f"Brakuje wymaganych progów: {missing}")
    return out


def extract_scores(profile_block: Dict[str, Any]) -> ProposalScores:
    if isinstance(profile_block.get("scores"), dict):
        s = profile_block["scores"]
        return ProposalScores(
            net_score=float(s.get("net_score", 0.0)),
            stability_score=float(s.get("stability_score", s.get("overall_score", 0.0))),
            runtime_safety_score=float(s.get("runtime_safety_score", s.get("overall_score", 0.0))),
            coverage_score=float(s.get("coverage_score", 0.0)),
            overall_score=float(s.get("overall_score", s.get("net_score", 0.0))),
        )

    if isinstance(profile_block.get("evaluation"), dict):
        score_estimate = float(profile_block["evaluation"].get("score_estimate", 0.0))
        return ProposalScores(
            net_score=score_estimate,
            stability_score=score_estimate,
            runtime_safety_score=score_estimate,
            coverage_score=score_estimate,
            overall_score=score_estimate,
        )

    return ProposalScores(
        net_score=float(profile_block.get("net_score", 0.0)),
        stability_score=float(profile_block.get("stability_score", 0.0)),
        runtime_safety_score=float(profile_block.get("runtime_safety_score", 0.0)),
        coverage_score=float(profile_block.get("coverage_score", 0.0)),
        overall_score=float(profile_block.get("overall_score", 0.0)),
    )


def build_profile_from_block(profile_key: str, block: Dict[str, Any], instrument: str, symbol_samples_n: int) -> ProposalProfile:
    thresholds_raw = dict(block.get("thresholds") or {})
    if not thresholds_raw:
        thresholds_raw = {
            key: value
            for key, value in block.items()
            if key in THRESHOLD_ALIASES and key not in RISK_LOCKED_KEYS
        }
    thresholds = normalize_thresholds(thresholds_raw)
    scores = extract_scores(block)
    sample_count = int(block.get("sample_count") or block.get("samples_n") or symbol_samples_n or 0)
    profile_name = str(block.get("profile_name") or PROFILE_LABEL_PL.get(profile_key, profile_key))
    profile_id = str(block.get("profile_id") or f"{instrument}_{profile_key}_{sha256_hex(canonical_json_dumps(block))[:10]}")
    return ProposalProfile(
        profile_key=profile_key,
        profile_label=profile_name,
        profile_id=profile_id,
        sample_count=sample_count,
        thresholds=thresholds,
        scores=scores,
        warnings=list(block.get("warnings", [])),
        validation_summary=dict(block.get("validation_summary", {})),
        source_block=dict(block),
    )


def compute_integrity_mode_and_hash(payload: Dict[str, Any]) -> Tuple[str, str]:
    if payload.get("config_hash"):
        calculated = compute_hash_without_field(payload, "config_hash")
        if calculated != payload.get("config_hash"):
            raise ContractError("Niezgodność skrótu w paczce propozycji")
        return "strict_config_hash", str(payload["config_hash"])

    # Dostosowanie do rzeczywistego raportu etapu pierwszego.
    calculated = sha256_hex(canonical_json_dumps(payload))
    return "self_computed_hash", calculated


def parse_proposal_pack(payload: Dict[str, Any]) -> ProposalPack:
    require_keys(payload, ["schema" if "schema" in payload else "schema_version"], "proposal_pack")
    schema_value = str(payload.get("schema_version") or payload.get("schema") or "")
    if schema_value not in PROPOSAL_SCHEMA_VALUES:
        raise ContractError(f"Nieobsługiwany schemat paczki propozycji: {schema_value}")

    locked_hits = deep_find_locked(payload)
    if locked_hits:
        raise ContractError(f"Paczka propozycji zawiera zakazane klucze ryzyka: {locked_hits}")

    integrity_mode, config_hash = compute_integrity_mode_and_hash(payload)

    instruments: Dict[str, InstrumentProposal] = {}

    if isinstance(payload.get("profiles_by_symbol"), list):
        for item in payload["profiles_by_symbol"]:
            if not isinstance(item, dict):
                continue
            instrument = symbol_base(item.get("symbol") or item.get("instrument"))
            if not instrument:
                continue
            symbol_samples_n = int(item.get("samples_n") or 0)
            block = item.get("profiles") or {}
            if not isinstance(block, dict):
                continue
            parsed_profiles: Dict[str, ProposalProfile] = {}
            for raw_profile_key, raw_profile_block in block.items():
                if not isinstance(raw_profile_block, dict):
                    continue
                profile_key = normalize_profile_key(raw_profile_key) or normalize_profile_key(raw_profile_block.get("profile_name"))
                if profile_key is None:
                    continue
                parsed_profiles[profile_key] = build_profile_from_block(
                    profile_key,
                    raw_profile_block,
                    instrument,
                    symbol_samples_n=symbol_samples_n,
                )
            if parsed_profiles:
                instruments[instrument] = InstrumentProposal(instrument=instrument, profiles=parsed_profiles)

    else:
        root = payload.get("instruments") or payload.get("profiles") or {}
        if not isinstance(root, dict):
            raise ContractError("Brak czytelnego korzenia z profilami")
        for instrument, raw_profiles in root.items():
            if not isinstance(raw_profiles, dict):
                continue
            parsed_profiles: Dict[str, ProposalProfile] = {}
            inst = symbol_base(instrument)
            for raw_profile_key, raw_profile_block in raw_profiles.items():
                if not isinstance(raw_profile_block, dict):
                    continue
                profile_key = normalize_profile_key(raw_profile_key) or normalize_profile_key(raw_profile_block.get("profile_name"))
                if profile_key is None:
                    continue
                parsed_profiles[profile_key] = build_profile_from_block(
                    profile_key,
                    raw_profile_block,
                    inst,
                    symbol_samples_n=0,
                )
            if parsed_profiles:
                instruments[inst] = InstrumentProposal(instrument=inst, profiles=parsed_profiles)

    if not instruments:
        raise ContractError("Paczka propozycji nie zawiera poprawnych profili")

    generated_at = str(payload.get("generated_at") or payload.get("started_at_utc") or iso_utc())
    proposal_id = str(payload.get("proposal_id") or payload.get("run_id") or generated_at)
    source_model_version = str(payload.get("source_model_version") or payload.get("reason") or "unknown")

    return ProposalPack(
        schema_version=schema_value,
        generated_at=generated_at,
        proposal_id=proposal_id,
        config_hash=config_hash,
        integrity_mode=integrity_mode,
        source_model_version=source_model_version,
        instruments=instruments,
        notes=list(payload.get("notes", [])),
    )


def parse_approval_payload(payload: Dict[str, Any]) -> Dict[str, str]:
    if str(payload.get("schema") or "") != APPROVAL_SCHEMA:
        raise ContractError(f"Nieobsługiwany schemat approval: {payload.get('schema')}")
    if not bool(payload.get("approved")):
        raise ContractError("Approval nie jest zatwierdzony (approved=false)")
    locked_hits = deep_find_locked(payload)
    if locked_hits:
        raise ContractError(f"Approval zawiera zakazane klucze ryzyka: {locked_hits}")
    instruments = payload.get("instruments")
    if not isinstance(instruments, dict):
        return {}

    out: Dict[str, str] = {}
    for sym_raw, profile_raw in instruments.items():
        sym = symbol_base(sym_raw)
        if not sym:
            continue
        profile_text = str(profile_raw or "").strip().upper()
        if profile_text in {"", "AUTO"}:
            continue
        profile = normalize_profile_key(profile_text)
        if profile is None:
            raise ContractError(f"Approval dla {sym} ma nieobsługiwany profil: {profile_raw}")
        out[sym] = profile
    return out


@dataclass
class AutoDeployerConfig:
    root: str
    lab_data_root: str
    proposed_config_path: str
    approval_path: str
    live_config_path: str
    dry_run_output_path: str
    apply_live: bool
    cooldown_state_path: str
    audit_jsonl_path: str

    lookback_hours: int = 24
    global_dd_halt_limit_pct: float = DEFAULT_GLOBAL_DD_HALT_LIMIT_PCT
    trade_path_timeout_halt_limit: float = DEFAULT_TRADE_PATH_TIMEOUT_HALT
    heartbeat_timeout_warn_limit: float = DEFAULT_HEARTBEAT_TIMEOUT_WARN
    trade_path_timeout_ok_limit: float = DEFAULT_TRADE_PATH_TIMEOUT_OK
    trade_path_p99_warn_ms: float = DEFAULT_TRADE_PATH_P99_WARN_MS
    heartbeat_p99_warn_ms: float = DEFAULT_HEARTBEAT_P99_WARN_MS
    profile_cooldown_minutes: int = DEFAULT_PROFILE_COOLDOWN_MINUTES

    default_canary_fraction: float = 0.25
    enable_canary: bool = True

    min_required_win_rate_for_aggressive: float = 0.55
    min_required_win_rate_for_balanced: float = 0.50

    emergency_thresholds: Dict[str, float] = field(default_factory=lambda: {
        "spread_cap_points": 5.0,
        "signal_score_threshold": 70.0,
        "max_latency_ms": 300.0,
        "min_tradeability_score": 0.75,
        "min_setup_quality_score": 0.75,
        "min_liquidity_score": 0.60,
    })


class AutoDeployerKontraktorzyPL:
    def __init__(self, cfg: AutoDeployerConfig, provider: HealthMetricsProvider, audit_logger: AuditLogger):
        self.cfg = cfg
        self.provider = provider
        self.audit = audit_logger
        self.cooldown_store = CooldownStateStore(cfg.cooldown_state_path)

    def run(self) -> int:
        started = time.time()
        deployment_id = f"dep_{utcnow().strftime('%Y%m%dT%H%M%SZ')}_{uuid.uuid4().hex[:8]}"
        LOG.info("Start wdrożenia %s", deployment_id)

        proposal_pack = self._load_and_validate_proposal()
        approval_map = self._load_and_validate_approval()
        global_health = self.provider.get_global_health(self.cfg.lookback_hours)
        target_config_path = self.cfg.live_config_path if self.cfg.apply_live else self.cfg.dry_run_output_path

        live_obj: Dict[str, Any] = {
            "schema_version": LIVE_SCHEMA_VERSION,
            "generated_at": iso_utc(),
            "deployment_id": deployment_id,
            "source_proposal_id": proposal_pack.proposal_id,
            "proposal_integrity_mode": proposal_pack.integrity_mode,
            "source_proposal_hash": proposal_pack.config_hash,
            "config_hash": "",
            "notes": [
                "auto_deployer_kontraktorzy_pl_v3",
                "bez_auto_zmiany_ryzyka_kapitalu",
                "spojne_z_paczka_etapu_pierwszego",
                "manualna_bramka_approval_wymagana",
                f"tryb_zapisu={'apply_live' if self.cfg.apply_live else 'dry_run'}",
            ],
            "instruments": {},
        }

        if global_health.account_dd_pct >= self.cfg.global_dd_halt_limit_pct or global_health.halted:
            reason = global_health.halt_reason or "GLOBAL_DD_HALT"
            LOG.warning("Aktywny stan awaryjny dla całego systemu: %s", reason)
            for instrument in proposal_pack.instruments:
                instrument_cfg = self._build_emergency_instrument_config(
                    instrument=instrument,
                    deployment_id=deployment_id,
                    reason_for_change=f"globalny_stan_awaryjny:{reason}",
                )
                live_obj["instruments"][instrument] = dataclass_to_dict(instrument_cfg)
            config_hash = atomic_write_json(target_config_path, live_obj)
            self._audit_deployment(
                deployment_id=deployment_id,
                proposal_pack=proposal_pack,
                global_health=global_health,
                config_hash=config_hash,
                live_obj=live_obj,
                event="GLOBAL_EMERGENCY_DEPLOY",
                output_path=target_config_path,
                apply_live=self.cfg.apply_live,
            )
            self.cooldown_store.save()
            LOG.info("Koniec wdrożenia awaryjnego w %.2fs", time.time() - started)
            return 0

        for instrument, iprop in proposal_pack.instruments.items():
            try:
                instr_health = self.provider.get_instrument_health(instrument, self.cfg.lookback_hours)
                runtime_split = self.provider.get_runtime_health_split(instrument, self.cfg.lookback_hours)
                approval_override = approval_map.get(symbol_base(instrument))
                decision, live_instr_cfg = self._decide_profile_for_instrument(
                    instrument=instrument,
                    iprop=iprop,
                    instr_health=instr_health,
                    global_health=global_health,
                    runtime_split=runtime_split,
                    deployment_id=deployment_id,
                    approval_override=approval_override,
                )
                live_obj["instruments"][instrument] = dataclass_to_dict(live_instr_cfg)
                self._audit_instrument_decision(
                    deployment_id=deployment_id,
                    instrument=instrument,
                    decision=decision,
                    instr_health=instr_health,
                    runtime_split=runtime_split,
                    selected=live_instr_cfg,
                )
            except ContractError as exc:
                LOG.exception("[%s] Błąd kontraktu, przejście do trybu awaryjnego: %s", instrument, exc)
                fallback = self._build_emergency_instrument_config(
                    instrument=instrument,
                    deployment_id=deployment_id,
                    reason_for_change=f"blad_kontraktu:{type(exc).__name__}",
                )
                live_obj["instruments"][instrument] = dataclass_to_dict(fallback)
                self._audit_exception_path(deployment_id, instrument, exc, fallback)
            except Exception as exc:
                LOG.exception("[%s] Błąd nieoczekiwany, przejście do trybu awaryjnego: %s", instrument, exc)
                fallback = self._build_emergency_instrument_config(
                    instrument=instrument,
                    deployment_id=deployment_id,
                    reason_for_change=f"blad_nieoczekiwany:{type(exc).__name__}",
                )
                live_obj["instruments"][instrument] = dataclass_to_dict(fallback)
                self._audit_exception_path(deployment_id, instrument, exc, fallback)

        config_hash = atomic_write_json(target_config_path, live_obj)
        self._audit_deployment(
            deployment_id=deployment_id,
            proposal_pack=proposal_pack,
            global_health=global_health,
            config_hash=config_hash,
            live_obj=live_obj,
            event="DEPLOY_OK" if self.cfg.apply_live else "DEPLOY_DRY_RUN_OK",
            output_path=target_config_path,
            apply_live=self.cfg.apply_live,
        )
        self.cooldown_store.save()
        LOG.info(
            "Koniec wdrożenia %s, skrót=%s, output=%s, czas=%.2fs",
            deployment_id,
            config_hash,
            target_config_path,
            time.time() - started,
        )
        return 0

    def _load_and_validate_proposal(self) -> ProposalPack:
        if not os.path.exists(self.cfg.proposed_config_path):
            raise FileNotFoundError(f"Nie znaleziono paczki propozycji: {self.cfg.proposed_config_path}")
        with open(self.cfg.proposed_config_path, "r", encoding="utf-8") as f:
            raw = json.load(f)
        proposal = parse_proposal_pack(raw)
        LOG.info(
            "Wczytano paczkę propozycji: id=%s, instrumenty=%d, tryb_spojnosci=%s",
            proposal.proposal_id,
            len(proposal.instruments),
            proposal.integrity_mode,
        )
        return proposal

    def _load_and_validate_approval(self) -> Dict[str, str]:
        if not os.path.exists(self.cfg.approval_path):
            raise FileNotFoundError(f"Nie znaleziono approval: {self.cfg.approval_path}")
        with open(self.cfg.approval_path, "r", encoding="utf-8") as f:
            raw = json.load(f)
        out = parse_approval_payload(raw)
        LOG.info("Wczytano approval: instrumenty_z_nadpisaniem=%d", len(out))
        return out

    def _describe_runtime_state(self, runtime_split: RuntimeHealthSplit) -> Tuple[str, List[str]]:
        reasons: List[str] = []
        trade_timeout = runtime_split.trade_path.timeout_rate
        hb_timeout = runtime_split.heartbeat_path.timeout_rate
        trade_p99 = runtime_split.trade_path.p99_bridge_wait_ms or 0.0
        hb_p99 = runtime_split.heartbeat_path.p99_bridge_wait_ms or 0.0

        if trade_timeout > self.cfg.trade_path_timeout_halt_limit:
            reasons.append(f"trade_timeout={trade_timeout:.4f}")
            return "AWARYJNY", reasons
        if trade_p99 > self.cfg.trade_path_p99_warn_ms:
            reasons.append(f"trade_p99={trade_p99:.1f}")
            return "OSTROZNY", reasons
        if hb_timeout > self.cfg.heartbeat_timeout_warn_limit:
            reasons.append(f"heartbeat_timeout={hb_timeout:.4f}")
            return "OSTROZNY", reasons
        if hb_p99 > self.cfg.heartbeat_p99_warn_ms:
            reasons.append(f"heartbeat_p99={hb_p99:.1f}")
            return "OSTROZNY", reasons
        return "DOBRY", reasons

    def _decide_profile_for_instrument(
        self,
        instrument: str,
        iprop: InstrumentProposal,
        instr_health: InstrumentHealth,
        global_health: GlobalHealth,
        runtime_split: RuntimeHealthSplit,
        deployment_id: str,
        approval_override: Optional[str],
    ) -> Tuple[str, LiveInstrumentConfig]:
        state = self.cooldown_store.get_instrument_state(instrument)
        current_profile = str(state.get("active_profile") or "bootstrap")
        cooldown_until = parse_dt(state.get("cooldown_until"))
        now = utcnow()

        runtime_state, runtime_reasons = self._describe_runtime_state(runtime_split)
        if runtime_state == "AWARYJNY":
            cfg = self._build_from_profile_or_emergency(
                instrument=instrument,
                iprop=iprop,
                preferred="conservative",
                deployment_id=deployment_id,
                reason_for_change="awaryjny_stan_sciezki_zlecen:" + ";".join(runtime_reasons),
                canary=False,
                rejected_profiles=[{"profile": "aggressive", "reason": "sciezka_zlecen_nieprawidlowa"}, {"profile": "balanced", "reason": "sciezka_zlecen_nieprawidlowa"}],
            )
            self._set_cooldown(state, cfg.active_profile, now)
            return "FORCED_CONSERVATIVE_RUNTIME", cfg

        allowed = {"conservative", "balanced", "aggressive"}
        rejected: List[Dict[str, Any]] = []
        manual_override = normalize_profile_key(approval_override)

        if manual_override:
            if manual_override not in iprop.profiles:
                raise ContractError(f"{instrument}: manualny profil niedostępny w paczce: {manual_override}")
            allowed = {manual_override}
            rejected.extend(
                [
                    {"profile": p, "reason": f"manualny_wybor_operatora:{manual_override}"}
                    for p in sorted({"conservative", "balanced", "aggressive"} - {manual_override})
                ]
            )

        if runtime_state == "OSTROZNY" and not manual_override:
            if "aggressive" in allowed:
                allowed.remove("aggressive")
                rejected.append({"profile": "aggressive", "reason": "stan_ostrozny_wykonania"})

        if not manual_override and instr_health.win_rate is not None:
            if instr_health.win_rate < self.cfg.min_required_win_rate_for_balanced:
                for profile in sorted(allowed - {"conservative"}):
                    rejected.append({"profile": profile, "reason": f"za_niska_skutecznosc:{instr_health.win_rate:.4f}"})
                allowed = {"conservative"}
            elif instr_health.win_rate < self.cfg.min_required_win_rate_for_aggressive and "aggressive" in allowed:
                allowed.remove("aggressive")
                rejected.append({"profile": "aggressive", "reason": f"za_niska_skutecznosc_dla_odwaznego:{instr_health.win_rate:.4f}"})
        elif not manual_override:
            if "aggressive" in allowed:
                allowed.remove("aggressive")
                rejected.append({"profile": "aggressive", "reason": "brak_danych_o_skutecznosci"})

        if not manual_override and not instr_health.has_sufficient_sample and "aggressive" in allowed:
            allowed.remove("aggressive")
            rejected.append({"profile": "aggressive", "reason": "za_malo_prob"})

        ranked = self._rank_profiles(iprop, allowed)
        rejected.extend(ranked[1][3] if len(ranked) > 1 else [])
        if not ranked:
            cfg = self._build_emergency_instrument_config(
                instrument=instrument,
                deployment_id=deployment_id,
                reason_for_change=(
                    f"brak_poprawnych_profili_po_filtrach:manualny={manual_override}"
                    if manual_override
                    else "brak_poprawnych_profili_po_filtrach"
                ),
            )
            self._set_cooldown(state, cfg.active_profile, now)
            return "EMERGENCY_NO_VALID_PROFILES", cfg

        best_name, best_profile, rank_reason, rank_rejected = ranked[0]
        rejected.extend(rank_rejected)

        if global_health.account_dd_pct >= max(0.0, self.cfg.global_dd_halt_limit_pct * 0.75):
            if best_name == "aggressive":
                best_name = "balanced" if "balanced" in iprop.profiles else "conservative"
                best_profile = iprop.profiles[best_name]
                rank_reason += "|globalny_drawdown_podwyzszony"
                rejected.append({"profile": "aggressive", "reason": "podwyzszony_globalny_drawdown"})

        if cooldown_until and now < cooldown_until and current_profile != "bootstrap":
            held_name = current_profile if current_profile in iprop.profiles else best_name
            held_profile = iprop.profiles.get(held_name, best_profile)
            live_cfg = self._build_live_instrument_config(
                instrument=instrument,
                profile_name=held_name,
                profile=held_profile,
                deployment_id=deployment_id,
                reason_for_change=f"utrzymanie_do_konca_okresu_wstrzymania:{iso_utc(cooldown_until)}",
                canary=self.cfg.enable_canary,
                cooldown_until_iso=iso_utc(cooldown_until),
                rejected_profiles=rejected,
            )
            return "COOLDOWN_HOLD", live_cfg

        self._set_cooldown(state, best_name, now)
        live_cfg = self._build_live_instrument_config(
            instrument=instrument,
            profile_name=best_name,
            profile=best_profile,
            deployment_id=deployment_id,
            reason_for_change=(
                f"manualny_wybor_operatora:{manual_override}|{rank_reason}"
                if manual_override
                else rank_reason
            ),
            canary=self.cfg.enable_canary,
            cooldown_until_iso=state.get("cooldown_until"),
            rejected_profiles=rejected,
        )
        return ("MANUAL_PROFILE_SELECTED" if manual_override else "PROFILE_SELECTED"), live_cfg

    def _rank_profiles(self, iprop: InstrumentProposal, allowed: set[str]) -> List[Tuple[str, ProposalProfile, str, List[Dict[str, Any]]]]:
        ranked: List[Tuple[str, ProposalProfile, str, List[Dict[str, Any]]]] = []
        for profile_name, profile in iprop.profiles.items():
            local_rejected: List[Dict[str, Any]] = []
            if profile_name not in allowed:
                continue

            if profile.sample_count < 10 and profile_name != "conservative":
                local_rejected.append({"profile": profile_name, "reason": "zbyt_malo_prob_do_profilu"})
                continue

            if profile_name == "aggressive" and profile.scores.runtime_safety_score < 0.50:
                local_rejected.append({"profile": profile_name, "reason": "za_niskie_bezpieczenstwo_wykonania"})
                continue

            thresholds = normalize_thresholds(profile.thresholds)
            score_bonus = 0.015 if profile_name == "balanced" else 0.0
            composite = (
                0.45 * profile.scores.overall_score
                + 0.25 * profile.scores.runtime_safety_score
                + 0.20 * profile.scores.stability_score
                + 0.10 * profile.scores.coverage_score
                + score_bonus
            )
            reason = (
                f"wybor:{profile_name}|laczny={composite:.6f}"
                f"|ogolny={profile.scores.overall_score:.6f}"
                f"|wykonanie={profile.scores.runtime_safety_score:.6f}"
                f"|stabilnosc={profile.scores.stability_score:.6f}"
                f"|pokrycie={profile.scores.coverage_score:.6f}"
                f"|proby={profile.sample_count}"
            )
            patched = dataclasses.replace(profile, thresholds=thresholds)
            ranked.append((profile_name, patched, reason, local_rejected))

        ranked.sort(
            key=lambda item: (
                0.45 * item[1].scores.overall_score
                + 0.25 * item[1].scores.runtime_safety_score
                + 0.20 * item[1].scores.stability_score
                + 0.10 * item[1].scores.coverage_score
                + (0.015 if item[0] == "balanced" else 0.0),
                item[1].scores.runtime_safety_score,
                item[1].scores.stability_score,
                item[1].scores.coverage_score,
            ),
            reverse=True,
        )
        return ranked

    def _build_from_profile_or_emergency(
        self,
        instrument: str,
        iprop: InstrumentProposal,
        preferred: str,
        deployment_id: str,
        reason_for_change: str,
        canary: bool,
        rejected_profiles: Optional[List[Dict[str, Any]]] = None,
    ) -> LiveInstrumentConfig:
        if preferred in iprop.profiles:
            return self._build_live_instrument_config(
                instrument=instrument,
                profile_name=preferred,
                profile=iprop.profiles[preferred],
                deployment_id=deployment_id,
                reason_for_change=reason_for_change,
                canary=canary,
                cooldown_until_iso=None,
                rejected_profiles=rejected_profiles or [],
            )
        return self._build_emergency_instrument_config(instrument, deployment_id, reason_for_change)

    def _build_emergency_instrument_config(
        self,
        instrument: str,
        deployment_id: str,
        reason_for_change: str,
    ) -> LiveInstrumentConfig:
        thresholds = normalize_thresholds(self.cfg.emergency_thresholds)
        return LiveInstrumentConfig(
            active_profile="EMERGENCY",
            profile_label_pl=PROFILE_LABEL_PL["EMERGENCY"],
            profile_id=f"{instrument}_EMERGENCY_{utcnow().strftime('%Y%m%dT%H%M%SZ')}",
            canary_mode=False,
            canary_fraction=0.0,
            cooldown_until=iso_utc(utcnow() + timedelta(minutes=self.cfg.profile_cooldown_minutes)),
            thresholds=thresholds,
            reason_for_change=reason_for_change,
            deployment_meta={
                "deployment_type": "awaryjny",
                "deployment_id": deployment_id,
            },
        )

    def _build_live_instrument_config(
        self,
        instrument: str,
        profile_name: str,
        profile: ProposalProfile,
        deployment_id: str,
        reason_for_change: str,
        canary: bool,
        cooldown_until_iso: Optional[str],
        rejected_profiles: List[Dict[str, Any]],
    ) -> LiveInstrumentConfig:
        thresholds = normalize_thresholds(profile.thresholds)
        return LiveInstrumentConfig(
            active_profile=profile_name,
            profile_label_pl=PROFILE_LABEL_PL.get(profile_name, profile.profile_label),
            profile_id=profile.profile_id,
            canary_mode=bool(canary),
            canary_fraction=(self.cfg.default_canary_fraction if canary else 0.0),
            cooldown_until=cooldown_until_iso,
            thresholds=thresholds,
            reason_for_change=reason_for_change,
            rejected_profiles=rejected_profiles,
            deployment_meta={
                "instrument": instrument,
                "proposal_profile_name": profile_name,
                "proposal_profile_label": profile.profile_label,
                "sample_count": profile.sample_count,
                "scores": dataclass_to_dict(profile.scores),
                "deployment_id": deployment_id,
            },
        )

    def _set_cooldown(self, state: Dict[str, Any], profile_name: str, now: datetime):
        state["active_profile"] = profile_name
        state["cooldown_until"] = iso_utc(now + timedelta(minutes=self.cfg.profile_cooldown_minutes))
        state["updated_at"] = iso_utc(now)

    def _audit_instrument_decision(
        self,
        deployment_id: str,
        instrument: str,
        decision: str,
        instr_health: Optional[InstrumentHealth],
        runtime_split: Optional[RuntimeHealthSplit],
        selected: LiveInstrumentConfig,
    ) -> None:
        self.audit.log(
            {
                "event_type": "instrument_decision",
                "ts": iso_utc(),
                "deployment_id": deployment_id,
                "instrument": instrument,
                "decision": decision,
                "selected_profile": selected.active_profile,
                "selected_profile_label_pl": selected.profile_label_pl,
                "profile_id": selected.profile_id,
                "reason_for_change": selected.reason_for_change,
                "rejected_profiles": selected.rejected_profiles,
                "instrument_health": dataclass_to_dict(instr_health) if instr_health else None,
                "runtime_split": dataclass_to_dict(runtime_split) if runtime_split else None,
            }
        )

    def _audit_exception_path(self, deployment_id: str, instrument: str, exc: Exception, fallback: LiveInstrumentConfig) -> None:
        self.audit.log(
            {
                "event_type": "instrument_decision",
                "ts": iso_utc(),
                "deployment_id": deployment_id,
                "instrument": instrument,
                "decision": f"AWARYJNIE_PRZEZ_WYJATEK:{type(exc).__name__}",
                "selected_profile": fallback.active_profile,
                "selected_profile_label_pl": fallback.profile_label_pl,
                "profile_id": fallback.profile_id,
                "reason_for_change": fallback.reason_for_change,
                "exception_text": str(exc),
            }
        )

    def _audit_deployment(
        self,
        deployment_id: str,
        proposal_pack: ProposalPack,
        global_health: GlobalHealth,
        config_hash: str,
        live_obj: Dict[str, Any],
        event: str,
        output_path: str,
        apply_live: bool,
    ) -> None:
        self.audit.log(
            {
                "event_type": "deployment_summary",
                "event": event,
                "ts": iso_utc(),
                "deployment_id": deployment_id,
                "proposal_id": proposal_pack.proposal_id,
                "proposal_schema_version": proposal_pack.schema_version,
                "proposal_integrity_mode": proposal_pack.integrity_mode,
                "proposal_hash": proposal_pack.config_hash,
                "proposal_model_version": proposal_pack.source_model_version,
                "global_health": dataclass_to_dict(global_health),
                "live_config_hash": config_hash,
                "output_path": output_path,
                "apply_live": bool(apply_live),
                "instrument_count": len(live_obj.get("instruments", {})),
                "selected_profiles": {key: value.get("active_profile") for key, value in live_obj.get("instruments", {}).items()},
            }
        )


def dataclass_to_dict(value: Any) -> Any:
    if value is None:
        return None
    if dataclasses.is_dataclass(value):
        return dataclasses.asdict(value)
    return value


def parse_dt(value: Optional[str]) -> Optional[datetime]:
    return parse_iso_utc(value)


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="OANDA_MT5_SYSTEM — ostrożny wdrażacz profili")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]), help="Katalog główny repo")
    parser.add_argument("--lab-data-root", default="", help="Nadpisuje LAB_DATA_ROOT")
    parser.add_argument("--proposal", default="", help="Paczka propozycji (domyślnie stage1_profile_pack_latest.json)")
    parser.add_argument("--approval-file", default="", help="Manual approval JSON")
    parser.add_argument("--live-config", default="", help="Docelowy live_config przy --apply-live")
    parser.add_argument("--dry-run-output", default="", help="Plik wyjściowy dla dry-run")
    parser.add_argument("--cooldown-state", default="", help="Plik stanu cooldown")
    parser.add_argument("--audit-jsonl", default="", help="Plik audit JSONL")
    parser.add_argument("--db-sqlite", default="", help="Ścieżka do DB/decision_events.sqlite")
    parser.add_argument("--audit-trail-jsonl", default="", help="Ścieżka do LOGS/audit_trail.jsonl")
    parser.add_argument("--apply-live", action="store_true", help="Zapisuje do live-config zamiast dry-run")
    parser.add_argument("--lookback-hours", type=int, default=24, help="Zakres godzin do odczytu stanu")
    parser.add_argument("--disable-canary", action="store_true", help="Wyłącza tryb próbny częściowego wdrożenia")
    return parser


def main() -> int:
    args = build_arg_parser().parse_args()
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    reports_stage1 = (lab_data_root / "reports" / "stage1").resolve()
    run_dir = (lab_data_root / "run").resolve()

    proposal_path = (
        Path(args.proposal).resolve()
        if str(args.proposal).strip()
        else (reports_stage1 / "stage1_profile_pack_latest.json").resolve()
    )
    approval_path = (
        Path(args.approval_file).resolve()
        if str(args.approval_file).strip()
        else (run_dir / "stage1_manual_approval.json").resolve()
    )
    live_config_path = (
        Path(args.live_config).resolve()
        if str(args.live_config).strip()
        else (run_dir / "live_config_stage1_apply.json").resolve()
    )
    dry_run_output_path = (
        Path(args.dry_run_output).resolve()
        if str(args.dry_run_output).strip()
        else (run_dir / "live_config_stage1_dry_run.json").resolve()
    )
    cooldown_state_path = (
        Path(args.cooldown_state).resolve()
        if str(args.cooldown_state).strip()
        else (run_dir / "auto_deployer_cooldown_state.json").resolve()
    )
    audit_jsonl_path = (
        Path(args.audit_jsonl).resolve()
        if str(args.audit_jsonl).strip()
        else (run_dir / "auto_deployer_audit.jsonl").resolve()
    )
    db_sqlite_path = (
        Path(args.db_sqlite).resolve()
        if str(args.db_sqlite).strip()
        else (root / "DB" / "decision_events.sqlite").resolve()
    )
    audit_trail_path = (
        Path(args.audit_trail_jsonl).resolve()
        if str(args.audit_trail_jsonl).strip()
        else (root / "LOGS" / "audit_trail.jsonl").resolve()
    )

    live_config_path = ensure_write_parent(live_config_path, root=root, lab_data_root=lab_data_root)
    dry_run_output_path = ensure_write_parent(dry_run_output_path, root=root, lab_data_root=lab_data_root)
    cooldown_state_path = ensure_write_parent(cooldown_state_path, root=root, lab_data_root=lab_data_root)
    audit_jsonl_path = ensure_write_parent(audit_jsonl_path, root=root, lab_data_root=lab_data_root)

    cfg = AutoDeployerConfig(
        root=str(root),
        lab_data_root=str(lab_data_root),
        proposed_config_path=str(proposal_path),
        approval_path=str(approval_path),
        live_config_path=str(live_config_path),
        dry_run_output_path=str(dry_run_output_path),
        apply_live=bool(args.apply_live),
        cooldown_state_path=str(cooldown_state_path),
        audit_jsonl_path=str(audit_jsonl_path),
        lookback_hours=int(args.lookback_hours),
        enable_canary=(not args.disable_canary),
    )
    provider = LocalSQLiteAuditHealthProvider(
        db_path=db_sqlite_path,
        audit_path=audit_trail_path,
    )
    audit_logger = JsonlAuditLogger(cfg.audit_jsonl_path)
    app = AutoDeployerKontraktorzyPL(cfg, provider, audit_logger)
    return app.run()


if __name__ == "__main__":
    raise SystemExit(main())
