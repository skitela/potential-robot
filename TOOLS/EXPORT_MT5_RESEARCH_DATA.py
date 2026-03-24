#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import time
from pathlib import Path
from typing import Iterable

import duckdb
import pandas as pd
from pandas.errors import ParserError


QDM_EXPORT_ALIAS_MAP = {
    "MB_AUDUSD_DUKA": "AUDUSD",
    "MB_COPPER_DUKA": "COPPER-US",
    "MB_DE30_DUKA": "DE30",
    "MB_EURAUD_DUKA": "EURAUD",
    "MB_EURJPY_DUKA": "EURJPY",
    "MB_EURUSD_DUKA": "EURUSD",
    "MB_GBPAUD_DUKA": "GBPAUD",
    "MB_GBPJPY_DUKA": "GBPJPY",
    "MB_GBPUSD_DUKA": "GBPUSD",
    "MB_GOLD_DUKA": "GOLD",
    "MB_NZDUSD_DUKA": "NZDUSD",
    "MB_PLATIN_DUKA": "PLATIN",
    "MB_SILVER_DUKA": "SILVER",
    "MB_US500_DUKA": "US500",
    "MB_USDCAD_DUKA": "USDCAD",
    "MB_USDCHF_DUKA": "USDCHF",
    "MB_USDJPY_DUKA": "USDJPY",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export MT5 runtime and tester data to research-ready parquet/csv/duckdb.")
    parser.add_argument("--project-root", default=r"C:\MAKRO_I_MIKRO_BOT")
    parser.add_argument("--common-root", default=r"C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT")
    parser.add_argument("--output-root", default=r"C:\TRADING_DATA\RESEARCH")
    parser.add_argument("--qdm-export-root", default=r"C:\TRADING_DATA\QDM_EXPORT\MT5")
    return parser.parse_args()


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def discover_related_common_roots(common_root: Path) -> list[Path]:
    roots: list[Path] = []
    if common_root.exists():
        roots.append(common_root)

    parent = common_root.parent
    prefix = common_root.name + "_TESTER_"
    if parent.exists():
        for path in sorted(parent.glob(f"{prefix}*")):
            if path.is_dir():
                roots.append(path)

    return roots


def read_tsv(path: Path) -> pd.DataFrame:
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            raw_lines = [line.rstrip("\r\n") for line in handle if line.strip()]
    except Exception:
        return pd.DataFrame()

    if not raw_lines:
        return pd.DataFrame()

    delimiter_candidates = ["\t", ",", ";"]
    header_line = raw_lines[0]
    header_delimiter = max(delimiter_candidates, key=lambda delim: header_line.count(delim))
    if header_line.count(header_delimiter) <= 0:
        header_delimiter = "\t"

    def parse_line(line: str, delimiter: str) -> list[str]:
        try:
            return next(csv.reader([line], delimiter=delimiter))
        except Exception:
            return [line]

    header = parse_line(header_line, header_delimiter)
    expected_len = max(1, len(header))

    body = []
    for line in raw_lines[1:]:
        best_row = None
        best_score = None
        for delimiter in dict.fromkeys([header_delimiter, ",", "\t", ";"]).keys():
            parsed = parse_line(line, delimiter)
            score = abs(len(parsed) - expected_len)
            if best_row is None or score < best_score or (score == best_score and len(parsed) > len(best_row)):
                best_row = parsed
                best_score = score
                if score == 0:
                    break
        if best_row:
            body.append(best_row)

    if not body:
        return pd.DataFrame(columns=header)

    max_len = max(len(header), *(len(row) for row in body))
    if len(header) < max_len:
        header = header + [f"_extra_col_{idx}" for idx in range(1, max_len - len(header) + 1)]

    normalized_rows = []
    for row in body:
        if len(row) < max_len:
            row = row + [None] * (max_len - len(row))
        elif len(row) > max_len:
            row = row[:max_len]
        normalized_rows.append(row)

    try:
        return pd.DataFrame(normalized_rows, columns=header)
    except Exception:
        return pd.DataFrame()


def read_json_file(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def flatten_records(records: Iterable[dict]) -> pd.DataFrame:
    records = list(records)
    if not records:
        return pd.DataFrame()
    return pd.json_normalize(records, sep=".")


def normalize_frame_for_parquet(df: pd.DataFrame) -> pd.DataFrame:
    if df.empty:
        return df

    normalized = df.copy()
    for column in normalized.columns:
        series = normalized[column]
        if not pd.api.types.is_object_dtype(series.dtype):
            continue

        non_null = series.dropna()
        if non_null.empty:
            continue

        numeric_candidate = pd.to_numeric(series, errors="coerce")
        if int(numeric_candidate.notna().sum()) == int(non_null.shape[0]):
            if (numeric_candidate.dropna() % 1 == 0).all():
                normalized[column] = numeric_candidate.astype("Int64")
            else:
                normalized[column] = numeric_candidate.astype("Float64")
            continue

        normalized[column] = series.astype("string")

    return normalized


def export_frame(df: pd.DataFrame, stem: str, output_dir: Path) -> dict:
    csv_path = output_dir / f"{stem}.csv"
    parquet_path = output_dir / f"{stem}.parquet"
    if df.empty:
        pd.DataFrame().to_csv(csv_path, index=False)
        pd.DataFrame().to_parquet(parquet_path, index=False)
    else:
        df.to_csv(csv_path, index=False)
        normalize_frame_for_parquet(df).to_parquet(parquet_path, index=False)
    return {
        "rows": int(len(df.index)),
        "csv_path": str(csv_path),
        "parquet_path": str(parquet_path),
    }


def export_parquet_only(df: pd.DataFrame, stem: str, output_dir: Path) -> dict:
    csv_path = output_dir / f"{stem}.csv"
    parquet_path = output_dir / f"{stem}.parquet"
    if csv_path.exists():
        csv_path.unlink()
    if df.empty:
        pd.DataFrame().to_parquet(parquet_path, index=False)
    else:
        normalize_frame_for_parquet(df).to_parquet(parquet_path, index=False)
    return {
        "rows": int(len(df.index)),
        "csv_path": None,
        "parquet_path": str(parquet_path),
    }


def collect_runtime_state(common_root: Path) -> pd.DataFrame:
    records = []
    state_root = common_root / "state"
    if not state_root.exists():
        return pd.DataFrame()
    for summary_path in state_root.glob("*\\execution_summary.json"):
        data = read_json_file(summary_path)
        if not data:
            continue
        data["_source_path"] = str(summary_path)
        data["_symbol_dir"] = summary_path.parent.name
        records.append(data)
    return flatten_records(records)


def collect_state_jsons(common_roots: Iterable[Path], file_name: str) -> pd.DataFrame:
    records = []
    for common_root in common_roots:
        state_root = common_root / "state"
        if not state_root.exists():
            continue
        for json_path in state_root.glob(f"*\\{file_name}"):
            data = read_json_file(json_path)
            if not data:
                continue
            data["_source_path"] = str(json_path)
            data["_symbol_dir"] = json_path.parent.name
            data["_root_path"] = str(common_root)
            data["_root_name"] = common_root.name
            data["_root_kind"] = "tester_sandbox" if common_root.name.startswith("MAKRO_I_MIKRO_BOT_TESTER_") else "runtime_root"
            records.append(data)
    return flatten_records(records)


def collect_jsonl_table(common_roots: Iterable[Path], scope_dir: str, file_name: str) -> pd.DataFrame:
    records = []
    for common_root in common_roots:
        root = common_root / scope_dir
        if not root.exists():
            continue
        for jsonl_path in root.glob(f"*\\{file_name}"):
            try:
                lines = jsonl_path.read_text(encoding="utf-8").splitlines()
            except Exception:
                continue
            for line in lines:
                line = line.strip()
                if not line:
                    continue
                try:
                    payload = json.loads(line)
                except Exception:
                    continue
                payload["_source_path"] = str(jsonl_path)
                payload["_symbol_dir"] = jsonl_path.parent.name
                payload["_root_path"] = str(common_root)
                payload["_root_name"] = common_root.name
                payload["_root_kind"] = "tester_sandbox" if common_root.name.startswith("MAKRO_I_MIKRO_BOT_TESTER_") else "runtime_root"
                records.append(payload)
    return flatten_records(records)


def collect_log_table(common_root: Path, relative_name: str) -> pd.DataFrame:
    frames = []
    logs_root = common_root / "logs"
    if not logs_root.exists():
        return pd.DataFrame()
    for table_path in logs_root.rglob(relative_name):
        df = read_tsv(table_path)
        if df.empty:
            continue
        try:
            relative_parts = table_path.relative_to(logs_root).parts
            symbol_dir = relative_parts[0] if relative_parts else table_path.parent.name
            log_scope = "archive" if "archive" in relative_parts else "live"
        except Exception:
            symbol_dir = table_path.parent.name
            log_scope = "unknown"
        df["_source_path"] = str(table_path)
        df["_symbol_dir"] = symbol_dir
        df["_log_scope"] = log_scope
        frames.append(df)
    return pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()


def collect_tester_jsons(project_root: Path, suffix: str) -> pd.DataFrame:
    records = []
    evidence_root = project_root / "EVIDENCE" / "STRATEGY_TESTER"
    if not evidence_root.exists():
        return pd.DataFrame()
    for path in evidence_root.rglob(f"*{suffix}"):
        data = read_json_file(path)
        if not data:
            continue
        data["_source_path"] = str(path)
        records.append(data)
    return flatten_records(records)


def sql_quote(path: str) -> str:
    return path.replace("\\", "/").replace("'", "''")


def read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def build_cached_log_table(common_root: Path, output_root: Path, relative_name: str, stem: str) -> dict:
    datasets_dir = ensure_dir(output_root / "datasets")
    reports_dir = ensure_dir(output_root / "reports")
    cache_root = ensure_dir(output_root / "log_cache" / stem)
    cache_manifest_path = reports_dir / f"{stem}_cache_manifest_latest.json"
    previous_manifest = read_json(cache_manifest_path)
    previous_files = previous_manifest.get("files", {})

    logs_root = common_root / "logs"
    combined_parquet_path = datasets_dir / f"{stem}_latest.parquet"
    file_entries: list[dict] = []
    cached_parquet_paths: list[str] = []
    reused_count = 0
    rebuilt_count = 0

    source_files = sorted(logs_root.rglob(relative_name)) if logs_root.exists() else []
    for table_path in source_files:
        try:
            relative_parts = table_path.relative_to(logs_root).parts
            source_key = "/".join(relative_parts)
            symbol_dir = relative_parts[0] if relative_parts else table_path.parent.name
            log_scope = "archive" if "archive" in relative_parts else "live"
        except Exception:
            source_key = table_path.name
            symbol_dir = table_path.parent.name
            log_scope = "unknown"

        source_stat = table_path.stat()
        cache_name = f"{hashlib.sha1(source_key.encode('utf-8')).hexdigest()}_{table_path.stem}.parquet"
        cache_path = cache_root / cache_name
        previous_entry = previous_files.get(source_key, {})
        reuse_cache = (
            cache_path.exists()
            and previous_entry.get("source_size") == int(source_stat.st_size)
            and previous_entry.get("source_mtime_ns") == int(source_stat.st_mtime_ns)
        )

        if reuse_cache:
            reused_count += 1
            row_count = int(previous_entry.get("rows", 0))
        else:
            df = read_tsv(table_path)
            if not df.empty:
                df["_source_path"] = str(table_path)
                df["_symbol_dir"] = symbol_dir
                df["_log_scope"] = log_scope
                normalize_frame_for_parquet(df).to_parquet(cache_path, index=False)
                row_count = int(len(df.index))
            else:
                pd.DataFrame().to_parquet(cache_path, index=False)
                row_count = 0
            rebuilt_count += 1

        cache_stat = cache_path.stat() if cache_path.exists() else None
        if row_count > 0 and cache_path.exists():
            cached_parquet_paths.append(str(cache_path))
        file_entries.append(
            {
                "source_path": str(table_path),
                "source_key": source_key,
                "source_size": int(source_stat.st_size),
                "source_mtime_ns": int(source_stat.st_mtime_ns),
                "symbol_dir": symbol_dir,
                "log_scope": log_scope,
                "rows": row_count,
                "cache_path": str(cache_path),
                "cache_size": int(cache_stat.st_size) if cache_stat else 0,
            }
        )

    if cached_parquet_paths:
        file_list_sql = "[" + ", ".join(f"'{sql_quote(path)}'" for path in cached_parquet_paths) + "]"
        read_expr = f"read_parquet({file_list_sql}, union_by_name = true)"
        with duckdb.connect() as con:
            con.execute(
                f"""
                COPY (
                    SELECT * FROM {read_expr}
                ) TO '{sql_quote(str(combined_parquet_path))}' (FORMAT PARQUET, COMPRESSION ZSTD)
                """
            )
            combined_rows = int(con.execute(f"SELECT COUNT(*) FROM {read_expr}").fetchone()[0])
    else:
        pd.DataFrame().to_parquet(combined_parquet_path, index=False)
        combined_rows = 0

    cache_manifest = {
        "generated_at_utc": pd.Timestamp.now("UTC").isoformat(),
        "relative_name": relative_name,
        "stem": stem,
        "file_count": len(file_entries),
        "reused_count": reused_count,
        "rebuilt_count": rebuilt_count,
        "files": {entry["source_key"]: entry for entry in file_entries},
    }
    cache_manifest_path.write_text(json.dumps(cache_manifest, indent=2, ensure_ascii=True), encoding="utf-8")

    return {
        "rows": combined_rows,
        "csv_path": None,
        "parquet_path": str(combined_parquet_path),
        "cache_manifest_path": str(cache_manifest_path),
        "source_file_count": len(file_entries),
        "cached_file_reused_count": reused_count,
        "cached_file_rebuilt_count": rebuilt_count,
    }


def build_qdm_minute_bars(qdm_export_root: Path, output_root: Path) -> tuple[dict, pd.DataFrame]:
    datasets_dir = ensure_dir(output_root / "datasets")
    reports_dir = ensure_dir(output_root / "reports")
    cache_root = ensure_dir(output_root / "qdm_cache" / "minute_bars")
    cache_manifest_path = reports_dir / "qdm_cache_manifest_latest.json"
    previous_manifest = read_json(cache_manifest_path)
    previous_files = previous_manifest.get("files", {})

    file_entries: list[dict] = []
    cached_parquet_paths: list[str] = []
    combined_parquet_path = datasets_dir / "qdm_minute_bars_latest.parquet"
    inventory = pd.DataFrame()

    csv_files = sorted(qdm_export_root.glob("MB_*.csv"))
    if not csv_files:
        cached_entries = []
        cached_parquet_paths = []
        for export_name, entry in previous_files.items():
            parquet_path_raw = entry.get("minute_parquet_path")
            if not parquet_path_raw:
                continue
            parquet_path = Path(parquet_path_raw)
            if not parquet_path.exists():
                continue
            cached_entries.append(entry)
            cached_parquet_paths.append(str(parquet_path))

        if not cached_parquet_paths:
            pd.DataFrame().to_parquet(combined_parquet_path, index=False)
            empty_meta = {
                "rows": 0,
                "csv_path": None,
                "parquet_path": str(combined_parquet_path),
                "file_count": 0,
                "cache_manifest_path": str(cache_manifest_path),
            }
            return empty_meta, inventory

        inventory = pd.DataFrame(cached_entries)
        with duckdb.connect() as con:
            file_list_sql = "[" + ", ".join(f"'{sql_quote(path)}'" for path in cached_parquet_paths) + "]"
            con.execute(
                f"""
                COPY (
                    SELECT * FROM read_parquet({file_list_sql})
                ) TO '{sql_quote(str(combined_parquet_path))}' (FORMAT PARQUET, COMPRESSION ZSTD)
                """
            )
            combined_rows = int(con.execute(f"SELECT COUNT(*) FROM read_parquet({file_list_sql})").fetchone()[0])

        metadata = {
            "rows": combined_rows,
            "csv_path": None,
            "parquet_path": str(combined_parquet_path),
            "file_count": len(cached_entries),
            "cache_manifest_path": str(cache_manifest_path),
        }
        return metadata, inventory

    with duckdb.connect() as con:
        for csv_path in csv_files:
            stem = csv_path.stem
            alias = QDM_EXPORT_ALIAS_MAP.get(stem, stem)
            source_stat = csv_path.stat()
            cache_path = cache_root / f"{stem}_minute.parquet"
            prev_entry = previous_files.get(stem, {})
            cached_ok = (
                cache_path.exists()
                and prev_entry.get("source_size") == int(source_stat.st_size)
                and prev_entry.get("source_mtime_ns") == int(source_stat.st_mtime_ns)
            )

            if not cached_ok:
                query = f"""
                    COPY (
                        WITH ticks AS (
                            SELECT
                                tick_ts,
                                bid,
                                ask
                            FROM read_csv(
                                '{sql_quote(str(csv_path))}',
                                columns = {{
                                    'tick_ts': 'TIMESTAMP',
                                    'bid': 'DOUBLE',
                                    'ask': 'DOUBLE'
                                }},
                                header = false,
                                timestampformat = '%Y.%m.%d %H:%M:%S.%f'
                            )
                        )
                        SELECT
                            '{stem}' AS export_name,
                            '{alias}' AS symbol_alias,
                            date_trunc('minute', tick_ts) AS bar_minute,
                            count(*)::BIGINT AS tick_count,
                            first(bid ORDER BY tick_ts) AS bid_open,
                            max(bid) AS bid_high,
                            min(bid) AS bid_low,
                            last(bid ORDER BY tick_ts) AS bid_close,
                            first(ask ORDER BY tick_ts) AS ask_open,
                            max(ask) AS ask_high,
                            min(ask) AS ask_low,
                            last(ask ORDER BY tick_ts) AS ask_close,
                            first((bid + ask) / 2.0 ORDER BY tick_ts) AS mid_open,
                            max((bid + ask) / 2.0) AS mid_high,
                            min((bid + ask) / 2.0) AS mid_low,
                            last((bid + ask) / 2.0 ORDER BY tick_ts) AS mid_close,
                            avg(ask - bid) AS spread_mean,
                            max(ask - bid) AS spread_max,
                            (max((bid + ask) / 2.0) - min((bid + ask) / 2.0)) AS mid_range_1m,
                            (
                                last((bid + ask) / 2.0 ORDER BY tick_ts) -
                                first((bid + ask) / 2.0 ORDER BY tick_ts)
                            ) / nullif(first((bid + ask) / 2.0 ORDER BY tick_ts), 0.0) AS mid_return_1m
                        FROM ticks
                        GROUP BY 1, 2, 3
                    ) TO '{sql_quote(str(cache_path))}' (FORMAT PARQUET, COMPRESSION ZSTD)
                """
                con.execute(query)

            row_count = int(con.execute("SELECT COUNT(*) FROM read_parquet(?)", [str(cache_path)]).fetchone()[0])
            bar_minute_min, bar_minute_max = con.execute(
                "SELECT MIN(bar_minute), MAX(bar_minute) FROM read_parquet(?)",
                [str(cache_path)],
            ).fetchone()
            cache_stat = cache_path.stat()
            entry = {
                "export_name": stem,
                "symbol_alias": alias,
                "source_csv_path": str(csv_path),
                "source_size": int(source_stat.st_size),
                "source_mtime_ns": int(source_stat.st_mtime_ns),
                "minute_parquet_path": str(cache_path),
                "minute_rows": row_count,
                "minute_parquet_size": int(cache_stat.st_size),
                "bar_minute_min": bar_minute_min.isoformat() if bar_minute_min else None,
                "bar_minute_max": bar_minute_max.isoformat() if bar_minute_max else None,
                "cache_reused": cached_ok,
            }
            file_entries.append(entry)
            cached_parquet_paths.append(str(cache_path))

        inventory = pd.DataFrame(file_entries)

        if cached_parquet_paths:
            file_list_sql = "[" + ", ".join(f"'{sql_quote(path)}'" for path in cached_parquet_paths) + "]"
            con.execute(
                f"""
                COPY (
                    SELECT * FROM read_parquet({file_list_sql})
                ) TO '{sql_quote(str(combined_parquet_path))}' (FORMAT PARQUET, COMPRESSION ZSTD)
                """
            )
            combined_rows = int(con.execute(f"SELECT COUNT(*) FROM read_parquet({file_list_sql})").fetchone()[0])
        else:
            pd.DataFrame().to_parquet(combined_parquet_path, index=False)
            combined_rows = 0

    cache_manifest = {
        "generated_at": pd.Timestamp.now("UTC").isoformat(),
        "qdm_export_root": str(qdm_export_root),
        "files": {entry["export_name"]: entry for entry in file_entries},
    }
    cache_manifest_path.write_text(json.dumps(cache_manifest, indent=2, ensure_ascii=True), encoding="utf-8")

    metadata = {
        "rows": combined_rows,
        "csv_path": None,
        "parquet_path": str(combined_parquet_path),
        "file_count": len(file_entries),
        "cache_manifest_path": str(cache_manifest_path),
    }
    return metadata, inventory


def build_duckdb(
    db_path: Path,
    tables: dict[str, tuple[Path, int]],
    lock_retry_attempts: int = 6,
    lock_retry_seconds: int = 10,
) -> dict[str, Any]:
    last_error = ""
    for attempt in range(1, lock_retry_attempts + 1):
        try:
            with duckdb.connect(str(db_path)) as con:
                for table_name, table_meta in tables.items():
                    parquet_path, row_count = table_meta
                    if row_count <= 0:
                        con.execute(f"CREATE OR REPLACE TABLE {table_name} AS SELECT CAST(NULL AS VARCHAR) AS _empty WHERE FALSE")
                        continue
                    con.execute(f"CREATE OR REPLACE TABLE {table_name} AS SELECT * FROM read_parquet(?)", [str(parquet_path)])

            return {
                "updated": True,
                "locked": False,
                "attempts_used": attempt,
                "error": "",
            }
        except duckdb.IOException as exc:
            last_error = str(exc)
            lowered = last_error.lower()
            is_lock = ("used by another process" in lowered or "already open" in lowered)
            if not is_lock:
                raise
            if attempt >= lock_retry_attempts:
                return {
                    "updated": False,
                    "locked": True,
                    "attempts_used": attempt,
                    "error": last_error,
                }
            time.sleep(lock_retry_seconds)


def main() -> int:
    args = parse_args()
    project_root = Path(args.project_root)
    common_root = Path(args.common_root)
    related_common_roots = discover_related_common_roots(common_root)
    output_root = Path(args.output_root)
    qdm_export_root = Path(args.qdm_export_root)
    datasets_dir = ensure_dir(output_root / "datasets")
    ensure_dir(output_root / "notebooks")
    ensure_dir(output_root / "reports")

    manifest: dict[str, object] = {
        "project_root": str(project_root),
        "common_root": str(common_root),
        "related_common_roots": [str(path) for path in related_common_roots],
        "output_root": str(output_root),
        "datasets": {},
    }

    runtime_state = collect_runtime_state(common_root)
    manifest["datasets"]["runtime_state"] = export_frame(runtime_state, "runtime_state_latest", datasets_dir)

    tester_telemetry = collect_state_jsons(related_common_roots, "tester_telemetry_latest.json")
    manifest["datasets"]["tester_telemetry"] = export_frame(tester_telemetry, "tester_telemetry_latest", datasets_dir)

    tester_pass_frames = collect_jsonl_table(related_common_roots, "run", "tester_optimization_passes.jsonl")
    manifest["datasets"]["tester_pass_frames"] = export_parquet_only(tester_pass_frames, "tester_pass_frames_latest", datasets_dir)

    manifest["datasets"]["decision_events"] = build_cached_log_table(
        common_root,
        output_root,
        "decision_events.csv",
        "decision_events",
    )

    manifest["datasets"]["candidate_signals"] = build_cached_log_table(
        common_root,
        output_root,
        "candidate_signals.csv",
        "candidate_signals",
    )

    manifest["datasets"]["learning_observations_v2"] = build_cached_log_table(
        common_root,
        output_root,
        "learning_observations_v2.csv",
        "learning_observations_v2",
    )

    manifest["datasets"]["onnx_observations"] = build_cached_log_table(
        common_root,
        output_root,
        "onnx_observations.csv",
        "onnx_observations",
    )

    manifest["datasets"]["tuning_deckhand"] = build_cached_log_table(
        common_root,
        output_root,
        "tuning_deckhand.csv",
        "tuning_deckhand",
    )

    manifest["datasets"]["tuning_reasoning"] = build_cached_log_table(
        common_root,
        output_root,
        "tuning_reasoning.csv",
        "tuning_reasoning",
    )

    tester_summary = collect_tester_jsons(project_root, "_summary.json")
    manifest["datasets"]["tester_summary"] = export_frame(tester_summary, "tester_summary_latest", datasets_dir)

    tester_knowledge = collect_tester_jsons(project_root, "_knowledge.json")
    manifest["datasets"]["tester_knowledge"] = export_frame(tester_knowledge, "tester_knowledge_latest", datasets_dir)

    qdm_minute_meta, qdm_inventory = build_qdm_minute_bars(qdm_export_root, output_root)
    manifest["datasets"]["qdm_tick_inventory"] = export_frame(qdm_inventory, "qdm_tick_inventory_latest", datasets_dir)
    manifest["datasets"]["qdm_minute_bars"] = qdm_minute_meta

    duckdb_path = output_root / "microbot_research.duckdb"
    duckdb_status = build_duckdb(
        duckdb_path,
        {
            "runtime_state": (datasets_dir / "runtime_state_latest.parquet", int(manifest["datasets"]["runtime_state"]["rows"])),
            "tester_telemetry": (datasets_dir / "tester_telemetry_latest.parquet", int(manifest["datasets"]["tester_telemetry"]["rows"])),
            "tester_pass_frames": (datasets_dir / "tester_pass_frames_latest.parquet", int(manifest["datasets"]["tester_pass_frames"]["rows"])),
            "decision_events": (datasets_dir / "decision_events_latest.parquet", int(manifest["datasets"]["decision_events"]["rows"])),
            "candidate_signals": (datasets_dir / "candidate_signals_latest.parquet", int(manifest["datasets"]["candidate_signals"]["rows"])),
            "learning_observations_v2": (datasets_dir / "learning_observations_v2_latest.parquet", int(manifest["datasets"]["learning_observations_v2"]["rows"])),
            "onnx_observations": (datasets_dir / "onnx_observations_latest.parquet", int(manifest["datasets"]["onnx_observations"]["rows"])),
            "tuning_deckhand": (datasets_dir / "tuning_deckhand_latest.parquet", int(manifest["datasets"]["tuning_deckhand"]["rows"])),
            "tuning_reasoning": (datasets_dir / "tuning_reasoning_latest.parquet", int(manifest["datasets"]["tuning_reasoning"]["rows"])),
            "tester_summary": (datasets_dir / "tester_summary_latest.parquet", int(manifest["datasets"]["tester_summary"]["rows"])),
            "tester_knowledge": (datasets_dir / "tester_knowledge_latest.parquet", int(manifest["datasets"]["tester_knowledge"]["rows"])),
            "qdm_tick_inventory": (datasets_dir / "qdm_tick_inventory_latest.parquet", int(manifest["datasets"]["qdm_tick_inventory"]["rows"])),
            "qdm_minute_bars": (datasets_dir / "qdm_minute_bars_latest.parquet", int(manifest["datasets"]["qdm_minute_bars"]["rows"])),
        },
    )
    manifest["duckdb_path"] = str(duckdb_path)
    manifest["duckdb_status"] = duckdb_status

    manifest_path = output_root / "reports" / "research_export_manifest_latest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=True), encoding="utf-8")

    print(json.dumps(manifest, indent=2, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
