from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import json
import re
from typing import Any

import pandas as pd

from .io_utils import first_present, read_table
from .paths import CompatPaths, DEFAULT_SYMBOLS


@dataclass(slots=True)
class SymbolReadiness:
    symbol_alias: str
    candidate_rows: int
    labeled_rows: int
    runtime_rows: int
    outcome_rows: int
    training_mode: str
    local_model_allowed: bool
    notes: list[str]


def _load_json(path: Path | None) -> Any:
    if path is None or not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8-sig"))


def load_active_symbols(paths: CompatPaths) -> list[str]:
    registry_path = paths.config_dir / "microbots_registry.json"
    if not registry_path.exists():
        return DEFAULT_SYMBOLS.copy()

    payload = _load_json(registry_path)
    rows: list[str] = []

    def maybe_add(record: dict[str, Any]) -> None:
        symbol = first_present(record, ("symbol_alias", "symbol", "instrument", "symbolAlias"))
        if symbol is None:
            return
        enabled = first_present(record, ("enabled", "active", "is_active", "isEnabled"), True)
        if isinstance(enabled, str):
            enabled = enabled.strip().lower() not in {"0", "false", "no", "off"}
        if enabled:
            rows.append(str(symbol))

    if isinstance(payload, dict):
        if isinstance(payload.get("microbots"), list):
            for record in payload["microbots"]:
                if isinstance(record, dict):
                    maybe_add(record)
        elif isinstance(payload.get("symbols"), list):
            for record in payload["symbols"]:
                if isinstance(record, dict):
                    maybe_add(record)
                else:
                    rows.append(str(record))
        elif isinstance(payload.get("symbols"), dict):
            for symbol_alias, record in payload["symbols"].items():
                if isinstance(record, dict):
                    record = dict(record)
                    record.setdefault("symbol_alias", symbol_alias)
                    maybe_add(record)
                else:
                    rows.append(str(symbol_alias))
        else:
            for value in payload.values():
                if isinstance(value, dict):
                    maybe_add(value)
    elif isinstance(payload, list):
        for record in payload:
            if isinstance(record, dict):
                maybe_add(record)
            else:
                rows.append(str(record))

    unique = []
    for symbol in rows:
        if symbol not in unique:
            unique.append(symbol)

    return unique or DEFAULT_SYMBOLS.copy()


def load_family_policy_registry(paths: CompatPaths) -> pd.DataFrame:
    path = paths.config_dir / "family_policy_registry.json"
    df = read_table(path)
    if df is None:
        return pd.DataFrame()
    out = df.copy()
    if "symbol_alias" not in out.columns and "family" in out.columns:
        out["symbol_alias"] = out["family"]
    return out


_PROFILE_PATTERN = re.compile(
    r"""
    (?:
        const\s+(?:double|int|string|bool)\s+ |
        input\s+(?:double|int|string|bool)\s+ |
        #define\s+
    )
    (?P<name>[A-Za-z0-9_]+)
    \s*(?:=\s*|\s+)
    (?P<value>[^;]+)
    """,
    re.VERBOSE,
)


def _parse_profile_value(raw: str) -> Any:
    raw = raw.strip().strip('"')
    if raw.lower() in {"true", "false"}:
        return raw.lower() == "true"
    try:
        if "." in raw or "e" in raw.lower():
            return float(raw)
        return int(raw)
    except Exception:
        return raw


def parse_mql_profile(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8", errors="ignore")
    values: dict[str, Any] = {}
    for match in _PROFILE_PATTERN.finditer(text):
        name = match.group("name").strip()
        value = _parse_profile_value(match.group("value"))
        values[name] = value
    values["profile_path"] = str(path)
    symbol_alias = first_present(
        values,
        ("SYMBOL_ALIAS", "SymbolAlias", "symbol_alias", "SYMBOL", "BrokerSymbol"),
    )
    if symbol_alias is None:
        stem = path.stem
        symbol_alias = stem[len("Profile_"):] if stem.lower().startswith("profile_") else stem
    values["symbol_alias"] = str(symbol_alias)
    return values


def load_mql_profiles(paths: CompatPaths, symbols: list[str]) -> pd.DataFrame:
    rows: list[dict[str, Any]] = []
    profiles_dir = paths.mql5_profiles_dir
    if not profiles_dir.exists():
        return pd.DataFrame()
    for path in profiles_dir.glob("Profile_*.mqh"):
        try:
            record = parse_mql_profile(path)
        except Exception:
            continue
        rows.append(record)
    if not rows:
        return pd.DataFrame()
    out = pd.DataFrame(rows)
    out = out.loc[out["symbol_alias"].isin(symbols)].copy() if "symbol_alias" in out.columns else out
    return out


def load_runtime_broker_profiles(paths: CompatPaths, symbols: list[str]) -> pd.DataFrame:
    rows = []
    state_dir = paths.common_state_root / "state"
    if not state_dir.exists():
        return pd.DataFrame()
    for symbol in symbols:
        path = state_dir / symbol / "broker_profile.json"
        payload = _load_json(path)
        if payload is None:
            continue
        if isinstance(payload, dict):
            payload = dict(payload)
            payload.setdefault("symbol_alias", symbol)
            payload["broker_profile_path"] = str(path)
            rows.append(payload)
    return pd.json_normalize(rows) if rows else pd.DataFrame()


def load_execution_summaries(paths: CompatPaths, symbols: list[str]) -> pd.DataFrame:
    rows = []
    state_dir = paths.common_state_root / "state"
    if not state_dir.exists():
        return pd.DataFrame()
    for symbol in symbols:
        path = state_dir / symbol / "execution_summary.json"
        payload = _load_json(path)
        if payload is None:
            continue
        if isinstance(payload, dict):
            payload = dict(payload)
            payload.setdefault("symbol_alias", symbol)
            payload["execution_summary_path"] = str(path)
            rows.append(payload)
    return pd.json_normalize(rows) if rows else pd.DataFrame()


def build_broker_economics_table(paths: CompatPaths, symbols: list[str]) -> pd.DataFrame:
    runtime = load_runtime_broker_profiles(paths, symbols)
    profiles = load_mql_profiles(paths, symbols)
    family = load_family_policy_registry(paths)
    execution = load_execution_summaries(paths, symbols)

    base = pd.DataFrame({"symbol_alias": symbols})
    sources = [
        runtime.rename(columns={
            "tick_value": "tick_value_account_ccy",
            "commission_per_lot": "commission_per_lot_account_ccy",
            "swap_long": "swap_long_account_ccy",
            "swap_short": "swap_short_account_ccy",
            "extra_fee": "extra_fee_account_ccy",
            "spread_points": "spread_points_modeled",
            "slippage_points": "slippage_points_modeled",
        }),
        profiles.rename(columns={
            "TICK_SIZE": "tick_size",
            "TICK_VALUE": "tick_value_account_ccy",
            "CONTRACT_SIZE": "contract_size",
            "BROKER_SYMBOL": "broker_symbol",
            "COMMISSION_PER_LOT": "commission_per_lot_account_ccy",
            "SWAP_LONG": "swap_long_account_ccy",
            "SWAP_SHORT": "swap_short_account_ccy",
            "EXTRA_FEE": "extra_fee_account_ccy",
            "SPREAD_POINTS_MODELED": "spread_points_modeled",
            "SLIPPAGE_POINTS_MODELED": "slippage_points_modeled",
            "SESSION_PROFILE": "session_profile",
            "ACCOUNT_CURRENCY": "account_currency",
            "BROKER_NAME": "broker_name",
            "FX_TO_PLN": "fx_to_pln_default",
        }),
        family,
        execution,
    ]

    out = base.copy()
    for src in sources:
        if src is None or src.empty or "symbol_alias" not in src.columns:
            continue
        src = src.sort_values("symbol_alias").drop_duplicates("symbol_alias", keep="last")
        overlap = [col for col in src.columns if col != "symbol_alias" and col in out.columns]
        if overlap:
            src = src.drop(columns=overlap)
        out = out.merge(src, on="symbol_alias", how="left")

    if "broker_symbol" not in out.columns:
        out["broker_symbol"] = out["symbol_alias"]
    else:
        out["broker_symbol"] = out["broker_symbol"].fillna(out["symbol_alias"])

    if "broker_name" not in out.columns:
        out["broker_name"] = "OANDA_MT5"
    else:
        out["broker_name"] = out["broker_name"].fillna("OANDA_MT5")

    if "account_currency" not in out.columns:
        out["account_currency"] = "PLN"
    else:
        out["account_currency"] = out["account_currency"].fillna("PLN")
    def _num_col(name: str, default: float) -> pd.Series:
        if name not in out.columns:
            return pd.Series([default] * len(out), index=out.index, dtype=float)
        return pd.to_numeric(out[name], errors="coerce").fillna(default)

    out["contract_size"] = _num_col("contract_size", 1.0)
    out["tick_size"] = _num_col("tick_size", 0.0001)
    out["tick_value_account_ccy"] = _num_col("tick_value_account_ccy", 1.0)
    out["commission_per_lot_account_ccy"] = _num_col("commission_per_lot_account_ccy", 0.0)
    out["swap_long_account_ccy"] = _num_col("swap_long_account_ccy", 0.0)
    out["swap_short_account_ccy"] = _num_col("swap_short_account_ccy", 0.0)
    out["extra_fee_account_ccy"] = _num_col("extra_fee_account_ccy", 0.0)
    out["spread_points_modeled"] = _num_col("spread_points_modeled", 0.0)
    out["slippage_points_modeled"] = _num_col("slippage_points_modeled", 0.0)
    out["fx_to_pln_default"] = _num_col("fx_to_pln_default", 1.0)

    if "session_profile" not in out.columns:
        out["session_profile"] = None

    return out


def build_symbol_readiness(
    master_frame: pd.DataFrame,
    all_candidates: pd.DataFrame,
    runtime_frame: pd.DataFrame | None,
    learning_frame: pd.DataFrame | None,
    symbols: list[str],
    min_local_rows: int = 120,
) -> pd.DataFrame:
    rows = []
    runtime_counts = runtime_frame.groupby("symbol_alias").size().to_dict() if runtime_frame is not None and not runtime_frame.empty else {}
    learning_counts = learning_frame.groupby("symbol_alias").size().to_dict() if learning_frame is not None and not learning_frame.empty else {}
    candidate_counts = all_candidates.groupby("symbol_alias").size().to_dict() if not all_candidates.empty else {}
    labeled_counts = master_frame.loc[master_frame["outcome_known"] == 1].groupby("symbol_alias").size().to_dict() if not master_frame.empty else {}

    for symbol in symbols:
        candidate_rows = int(candidate_counts.get(symbol, 0))
        labeled_rows = int(labeled_counts.get(symbol, 0))
        runtime_rows = int(runtime_counts.get(symbol, 0))
        outcome_rows = int(learning_counts.get(symbol, 0))
        notes = []

        if candidate_rows <= 0:
            training_mode = "FALLBACK_ONLY"
            local_model_allowed = False
            notes.append("Brak candidate_signals.")
        elif labeled_rows >= min_local_rows:
            training_mode = "TRAINING_SHADOW_READY"
            local_model_allowed = True
            notes.append("Wystarczająca liczba domkniętych outcome do lokalnego treningu.")
        else:
            training_mode = "LOCAL_TRAINING_LIMITED"
            local_model_allowed = labeled_rows >= 30
            notes.append("Kandydaci istnieją, ale outcome jest jeszcze ograniczony.")

        rows.append(
            {
                "symbol_alias": symbol,
                "candidate_rows": candidate_rows,
                "labeled_rows": labeled_rows,
                "runtime_rows": runtime_rows,
                "outcome_rows": outcome_rows,
                "training_mode": training_mode,
                "local_model_allowed": local_model_allowed,
                "notes": notes,
            }
        )
    return pd.DataFrame(rows)
