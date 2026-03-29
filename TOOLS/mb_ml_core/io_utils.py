from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING, Any, Iterable
import json
import math
import re

try:
    import duckdb
except Exception:  # pragma: no cover - opcjonalna zależność w środowiskach testowych
    duckdb = None

if TYPE_CHECKING:
    import pandas as pd


def _import_pandas():
    import pandas as pd  # type: ignore

    return pd


def ensure_dir(path: str | Path) -> Path:
    path = Path(path)
    path.mkdir(parents=True, exist_ok=True)
    return path


def _json_default(obj: Any) -> Any:
    if isinstance(obj, Path):
        return str(obj)
    if hasattr(obj, "isoformat"):
        try:
            return obj.isoformat()
        except Exception:
            pass
    raise TypeError(f"Object of type {type(obj)!r} is not JSON serializable")


def write_json(path: str | Path, payload: Any) -> Path:
    path = Path(path)
    ensure_dir(path.parent)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False, default=_json_default), encoding="utf-8")
    return path


def to_frame(payload: Any) -> "pd.DataFrame":
    pd = _import_pandas()

    if payload is None:
        return pd.DataFrame()
    if isinstance(payload, list):
        return pd.json_normalize(payload)
    if isinstance(payload, dict):
        for key in ("rows", "data", "items", "records"):
            value = payload.get(key)
            if isinstance(value, list):
                return pd.json_normalize(value)
        if "symbols" in payload and isinstance(payload["symbols"], dict):
            rows = []
            for symbol_alias, info in payload["symbols"].items():
                if isinstance(info, dict):
                    row = dict(info)
                    row.setdefault("symbol_alias", symbol_alias)
                    rows.append(row)
                else:
                    rows.append({"symbol_alias": symbol_alias, "value": info})
            return pd.json_normalize(rows)
        return pd.json_normalize([payload])
    return pd.DataFrame([{"value": payload}])


def _quote_sql(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _sql_timestamp_literal(value: Any) -> str:
    pd = _import_pandas()
    ts = pd.Timestamp(value)
    if ts.tzinfo is None:
        ts = ts.tz_localize("UTC")
    else:
        ts = ts.tz_convert("UTC")
    return _quote_sql(ts.strftime("%Y-%m-%d %H:%M:%S"))


def read_parquet_window(
    path: str | Path,
    *,
    columns: Iterable[str] | None = None,
    symbol_aliases: Iterable[str] | None = None,
    ts_col: str | None = None,
    ts_min: Any = None,
    ts_max: Any = None,
) -> pd.DataFrame:
    pd = _import_pandas()
    path = Path(path)
    if not path.exists():
        return pd.DataFrame()

    cols = list(columns) if columns else None
    use_windowing = bool(symbol_aliases) or ts_col is not None or ts_min is not None or ts_max is not None
    if not use_windowing or duckdb is None:
        try:
            return pd.read_parquet(path, columns=cols)
        except MemoryError:
            pass
        except Exception:
            if duckdb is None:
                raise

    if duckdb is None:
        raise MemoryError(f"Brak duckdb do okienkowego odczytu parquet: {path}")

    select_sql = "*"
    if cols:
        select_sql = ", ".join(f'"{col}"' for col in cols)

    where_parts: list[str] = []
    if symbol_aliases:
        safe_symbols = [str(s) for s in symbol_aliases if str(s).strip()]
        if safe_symbols:
            symbol_sql = ", ".join(_quote_sql(sym) for sym in safe_symbols)
            where_parts.append(f'"symbol_alias" IN ({symbol_sql})')
    if ts_col:
        if ts_min is not None:
            where_parts.append(f'try_cast("{ts_col}" as timestamp) >= TIMESTAMP {_sql_timestamp_literal(ts_min)}')
        if ts_max is not None:
            where_parts.append(f'try_cast("{ts_col}" as timestamp) <= TIMESTAMP {_sql_timestamp_literal(ts_max)}')

    sql = f"SELECT {select_sql} FROM read_parquet({_quote_sql(str(path))})"
    if where_parts:
        sql += " WHERE " + " AND ".join(where_parts)
    return duckdb.sql(sql).df()


def read_table(path: str | Path | None) -> "pd.DataFrame | None":
    pd = _import_pandas()

    if path is None:
        return None
    path = Path(path)
    if not path.exists():
        return None
    suffix = path.suffix.lower()
    if suffix == ".parquet":
        return read_parquet_window(path)
    if suffix == ".csv":
        return pd.read_csv(path)
    if suffix == ".json":
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
        return to_frame(payload)
    if suffix == ".jsonl":
        rows = [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
        return pd.DataFrame(rows)
    return None


def normalize_ts(series: "pd.Series") -> "pd.Series":
    pd = _import_pandas()

    if pd.api.types.is_datetime64_any_dtype(series):
        return pd.to_datetime(series, utc=True)
    s = series.copy()
    if pd.api.types.is_numeric_dtype(s):
        s = pd.to_numeric(s, errors="coerce")
        if s.dropna().empty:
            return pd.to_datetime(s, unit="s", utc=True, errors="coerce")
        sample = float(s.dropna().iloc[0])
        if abs(sample) > 1e11:
            return pd.to_datetime(s, unit="ms", utc=True, errors="coerce")
        return pd.to_datetime(s, unit="s", utc=True, errors="coerce")
    return pd.to_datetime(s, utc=True, errors="coerce")


def coalesce_columns(
    df: "pd.DataFrame",
    names: Iterable[str],
    default: float | str | bool | None = None,
) -> "pd.Series":
    pd = _import_pandas()

    result = None
    for name in names:
        if name in df.columns:
            cur = df[name]
            result = cur if result is None else result.combine_first(cur)
    if result is None:
        return pd.Series([default] * len(df), index=df.index)
    return result.fillna(default)


def first_present(mapping: dict[str, Any], names: Iterable[str], default: Any = None) -> Any:
    for name in names:
        if name in mapping and mapping[name] not in (None, ""):
            return mapping[name]
    return default


def find_optional_file(root: str | Path, filename: str) -> Path | None:
    root = Path(root)
    if not root.exists():
        return None
    direct = root / filename
    if direct.exists():
        return direct
    matches = list(root.rglob(filename))
    return matches[0] if matches else None


def normalize_column_names(df: "pd.DataFrame") -> "pd.DataFrame":
    out = df.copy()
    out.columns = [
        re.sub(r"[^a-zA-Z0-9_]+", "_", str(col)).strip("_").lower()
        for col in out.columns
    ]
    return out


def safe_float(value: Any, default: float = 0.0) -> float:
    try:
        if value is None:
            return default
        if isinstance(value, str) and not value.strip():
            return default
        if isinstance(value, float) and math.isnan(value):
            return default
        return float(value)
    except Exception:
        return default


def safe_int(value: Any, default: int = 0) -> int:
    try:
        return int(float(value))
    except Exception:
        return default
