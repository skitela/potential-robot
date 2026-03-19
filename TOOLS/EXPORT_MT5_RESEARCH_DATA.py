#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Iterable

import duckdb
import pandas as pd


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export MT5 runtime and tester data to research-ready parquet/csv/duckdb.")
    parser.add_argument("--project-root", default=r"C:\MAKRO_I_MIKRO_BOT")
    parser.add_argument("--common-root", default=r"C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT")
    parser.add_argument("--output-root", default=r"C:\TRADING_DATA\RESEARCH")
    return parser.parse_args()


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def read_tsv(path: Path) -> pd.DataFrame:
    try:
        return pd.read_csv(path, sep="\t", low_memory=False)
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


def export_frame(df: pd.DataFrame, stem: str, output_dir: Path) -> dict:
    csv_path = output_dir / f"{stem}.csv"
    parquet_path = output_dir / f"{stem}.parquet"
    if df.empty:
        pd.DataFrame().to_csv(csv_path, index=False)
        pd.DataFrame().to_parquet(parquet_path, index=False)
    else:
        df.to_csv(csv_path, index=False)
        df.to_parquet(parquet_path, index=False)
    return {
        "rows": int(len(df.index)),
        "csv_path": str(csv_path),
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


def collect_log_table(common_root: Path, relative_name: str) -> pd.DataFrame:
    frames = []
    logs_root = common_root / "logs"
    if not logs_root.exists():
        return pd.DataFrame()
    for table_path in logs_root.glob(f"*\\{relative_name}"):
        df = read_tsv(table_path)
        if df.empty:
            continue
        df["_source_path"] = str(table_path)
        df["_symbol_dir"] = table_path.parent.name
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


def build_duckdb(db_path: Path, tables: dict[str, tuple[Path, int]]) -> None:
    with duckdb.connect(str(db_path)) as con:
        for table_name, table_meta in tables.items():
            parquet_path, row_count = table_meta
            if row_count <= 0:
                con.execute(f"CREATE OR REPLACE TABLE {table_name} AS SELECT CAST(NULL AS VARCHAR) AS _empty WHERE FALSE")
                continue
            con.execute(f"CREATE OR REPLACE TABLE {table_name} AS SELECT * FROM read_parquet(?)", [str(parquet_path)])


def main() -> int:
    args = parse_args()
    project_root = Path(args.project_root)
    common_root = Path(args.common_root)
    output_root = Path(args.output_root)
    datasets_dir = ensure_dir(output_root / "datasets")
    ensure_dir(output_root / "notebooks")
    ensure_dir(output_root / "reports")

    manifest: dict[str, object] = {
        "project_root": str(project_root),
        "common_root": str(common_root),
        "output_root": str(output_root),
        "datasets": {},
    }

    runtime_state = collect_runtime_state(common_root)
    manifest["datasets"]["runtime_state"] = export_frame(runtime_state, "runtime_state_latest", datasets_dir)

    decision_events = collect_log_table(common_root, "decision_events.csv")
    manifest["datasets"]["decision_events"] = export_frame(decision_events, "decision_events_latest", datasets_dir)

    candidate_signals = collect_log_table(common_root, "candidate_signals.csv")
    manifest["datasets"]["candidate_signals"] = export_frame(candidate_signals, "candidate_signals_latest", datasets_dir)

    tuning_deckhand = collect_log_table(common_root, "tuning_deckhand.csv")
    manifest["datasets"]["tuning_deckhand"] = export_frame(tuning_deckhand, "tuning_deckhand_latest", datasets_dir)

    tuning_reasoning = collect_log_table(common_root, "tuning_reasoning.csv")
    manifest["datasets"]["tuning_reasoning"] = export_frame(tuning_reasoning, "tuning_reasoning_latest", datasets_dir)

    tester_summary = collect_tester_jsons(project_root, "_summary.json")
    manifest["datasets"]["tester_summary"] = export_frame(tester_summary, "tester_summary_latest", datasets_dir)

    tester_knowledge = collect_tester_jsons(project_root, "_knowledge.json")
    manifest["datasets"]["tester_knowledge"] = export_frame(tester_knowledge, "tester_knowledge_latest", datasets_dir)

    duckdb_path = output_root / "microbot_research.duckdb"
    build_duckdb(
        duckdb_path,
        {
            "runtime_state": (datasets_dir / "runtime_state_latest.parquet", int(manifest["datasets"]["runtime_state"]["rows"])),
            "decision_events": (datasets_dir / "decision_events_latest.parquet", int(manifest["datasets"]["decision_events"]["rows"])),
            "candidate_signals": (datasets_dir / "candidate_signals_latest.parquet", int(manifest["datasets"]["candidate_signals"]["rows"])),
            "tuning_deckhand": (datasets_dir / "tuning_deckhand_latest.parquet", int(manifest["datasets"]["tuning_deckhand"]["rows"])),
            "tuning_reasoning": (datasets_dir / "tuning_reasoning_latest.parquet", int(manifest["datasets"]["tuning_reasoning"]["rows"])),
            "tester_summary": (datasets_dir / "tester_summary_latest.parquet", int(manifest["datasets"]["tester_summary"]["rows"])),
            "tester_knowledge": (datasets_dir / "tester_knowledge_latest.parquet", int(manifest["datasets"]["tester_knowledge"]["rows"])),
        },
    )
    manifest["duckdb_path"] = str(duckdb_path)

    manifest_path = output_root / "reports" / "research_export_manifest_latest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=True), encoding="utf-8")

    print(json.dumps(manifest, indent=2, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
