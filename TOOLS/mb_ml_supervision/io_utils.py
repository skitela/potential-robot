from __future__ import annotations

from pathlib import Path
from typing import Any, Iterable
import datetime as dt
import json
import os
import traceback


def utc_now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path: Path, default: Any = None) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def dump_json(path: Path, payload: Any) -> None:
    ensure_parent(path)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def file_age_hours(path: Path) -> float | None:
    if not path.exists():
        return None
    mtime = dt.datetime.fromtimestamp(path.stat().st_mtime, tz=dt.timezone.utc)
    delta = dt.datetime.now(dt.timezone.utc) - mtime
    return round(delta.total_seconds() / 3600.0, 3)


def file_modified_iso(path: Path) -> str | None:
    if not path.exists():
        return None
    return dt.datetime.fromtimestamp(path.stat().st_mtime, tz=dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def try_import_lightgbm() -> bool:
    try:
        import lightgbm  # noqa: F401
        return True
    except Exception:
        return False


def parquet_query_rows(path: Path, sql: str, params: list[Any] | None = None) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    try:
        import duckdb  # type: ignore
    except Exception:
        return []
    con = duckdb.connect()
    try:
        rows = con.execute(sql, params or []).fetchall()
        columns = [str(col[0]) for col in con.description]
        return [dict(zip(columns, row)) for row in rows]
    finally:
        con.close()


def parquet_exists(path: Path) -> bool:
    return path.exists() and path.is_file()


def parquet_count(path: Path) -> int:
    rows = parquet_query_rows(path, "select count(*) as n from read_parquet(?)", [str(path)])
    return int(rows[0]["n"]) if rows else 0


def parquet_symbol_counts(path: Path, symbol_column: str = "symbol_alias") -> dict[str, int]:
    if not path.exists():
        return {}
    rows = parquet_query_rows(
        path,
        f"select cast({symbol_column} as varchar) as symbol_alias, count(*) as n from read_parquet(?) group by 1 order by 1",
        [str(path)],
    )
    return {str(row["symbol_alias"]): int(row["n"]) for row in rows}


def recursive_collect_symbols(payload: Any) -> set[str]:
    found: set[str] = set()
    if isinstance(payload, dict):
        for key, value in payload.items():
            lowered = str(key).lower()
            if lowered in {"symbol", "symbol_alias", "code_symbol"} and isinstance(value, str):
                found.add(value)
            elif lowered in {"symbols", "instruments"}:
                if isinstance(value, list):
                    for item in value:
                        found.update(recursive_collect_symbols(item))
                elif isinstance(value, dict):
                    found.update(recursive_collect_symbols(value))
            else:
                found.update(recursive_collect_symbols(value))
    elif isinstance(payload, list):
        for item in payload:
            found.update(recursive_collect_symbols(item))
    return {item for item in found if item}


def safe_exc_message(exc: BaseException) -> str:
    return "".join(traceback.format_exception_only(type(exc), exc)).strip()


def glob_first(paths: Iterable[Path]) -> Path | None:
    for path in paths:
        if path.exists():
            return path
    return None
