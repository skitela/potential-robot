from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import UTC, datetime
from pathlib import Path

import duckdb


def read_json(path: Path):
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8-sig"))


def query_counts(con: duckdb.DuckDBPyConnection, parquet_path: Path) -> dict[str, int]:
    if not parquet_path.exists():
        return {}
    rows = con.execute(
        f"""
        select upper(trim(symbol_alias)) as symbol_alias, count(*) as rows_total
        from read_parquet('{parquet_path.as_posix()}')
        where symbol_alias is not null and trim(symbol_alias) <> ''
        group by 1
        """
    ).fetchall()
    return {str(symbol): int(count) for symbol, count in rows}


def query_qdm_counts(con: duckdb.DuckDBPyConnection, parquet_path: Path) -> dict[str, int]:
    if not parquet_path.exists():
        return {}
    rows = con.execute(
        f"""
        select upper(trim(symbol_alias)) as symbol_alias, count(*) as rows_total
        from read_parquet('{parquet_path.as_posix()}')
        where symbol_alias is not null and trim(symbol_alias) <> ''
        group by 1
        """
    ).fetchall()
    return {str(symbol): int(count) for symbol, count in rows}


def build_qdm_maps(profile: dict | None) -> tuple[dict[str, dict], dict[str, dict]]:
    present_map: dict[str, dict] = {}
    missing_map: dict[str, dict] = {}

    if not profile:
        return present_map, missing_map

    for entry in profile.get("present", []):
        alias = str(entry.get("symbol_alias", "")).strip().upper()
        if alias:
            present_map[alias] = entry

    for entry in profile.get("missing", []):
        alias = str(entry.get("symbol_alias", "")).strip().upper()
        if alias:
            missing_map[alias] = entry

    return present_map, missing_map


def build_paper_map(paper_feedback: dict | None) -> dict[str, dict]:
    result: dict[str, dict] = {}
    if not paper_feedback:
        return result
    for entry in paper_feedback.get("key_instruments", []):
        instrument = str(entry.get("instrument", "")).strip().upper()
        if instrument:
            result[instrument] = entry
    return result


def build_onnx_map(onnx_feedback: dict | None) -> dict[str, dict]:
    result: dict[str, dict] = {}
    if not onnx_feedback:
        return result
    for entry in onnx_feedback.get("items", []):
        alias = str(entry.get("symbol_alias", "")).strip().upper()
        if alias:
            result[alias] = entry
    return result


def get_data_readiness_state(
    raw_history_present: bool,
    active_export_present: bool,
    qdm_contract_rows: int,
    candidate_rows: int,
    learning_rows: int,
    onnx_runtime_rows: int,
    outcome_rows: int,
) -> str:
    if not raw_history_present:
        return "NO_RAW_HISTORY"
    if not active_export_present:
        return "EXPORT_PENDING"
    if qdm_contract_rows <= 0:
        return "CONTRACT_PENDING"
    if outcome_rows > 0:
        return "OUTCOME_READY"
    if onnx_runtime_rows > 0:
        return "RUNTIME_READY"
    if candidate_rows > 0 or learning_rows > 0:
        return "TRAINING_SHADOW_READY"
    return "CONTRACT_READY"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", default=r"C:\MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json")
    parser.add_argument("--qdm-profile", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_missing_only_profile_latest.json")
    parser.add_argument("--paper-feedback", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\paper_live_feedback_latest.json")
    parser.add_argument("--onnx-feedback", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_feedback_loop_latest.json")
    parser.add_argument("--qdm-minute-bars", default=r"C:\TRADING_DATA\RESEARCH\datasets\qdm_minute_bars_latest.parquet")
    parser.add_argument("--candidate-contract", default=r"C:\TRADING_DATA\RESEARCH\datasets\contracts\candidate_signals_norm_latest.parquet")
    parser.add_argument("--learning-contract", default=r"C:\TRADING_DATA\RESEARCH\datasets\contracts\learning_observations_v2_norm_latest.parquet")
    parser.add_argument("--output-json", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_data_readiness_latest.json")
    parser.add_argument("--output-md", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_data_readiness_latest.md")
    args = parser.parse_args()

    registry = read_json(Path(args.registry))
    if not registry:
        raise SystemExit(f"Registry missing or invalid: {args.registry}")

    qdm_profile = read_json(Path(args.qdm_profile))
    paper_feedback = read_json(Path(args.paper_feedback))
    onnx_feedback = read_json(Path(args.onnx_feedback))

    present_map, missing_map = build_qdm_maps(qdm_profile)
    paper_map = build_paper_map(paper_feedback)
    onnx_map = build_onnx_map(onnx_feedback)

    con = duckdb.connect()
    qdm_counts = query_qdm_counts(con, Path(args.qdm_minute_bars))
    candidate_counts = query_counts(con, Path(args.candidate_contract))
    learning_counts = query_counts(con, Path(args.learning_contract))
    con.close()

    items: list[dict] = []
    state_counter: Counter[str] = Counter()

    for symbol_entry in registry.get("symbols", []):
        alias = str(symbol_entry.get("symbol", "")).strip().upper()
        if not alias:
            continue

        present_entry = present_map.get(alias)
        missing_entry = missing_map.get(alias)
        paper_entry = paper_map.get(alias)
        onnx_entry = onnx_map.get(alias)

        raw_history_present = bool(present_entry or (missing_entry and missing_entry.get("history_ready")))
        active_export_present = bool(present_entry)

        qdm_contract_rows = int(qdm_counts.get(alias, 0))
        candidate_rows = int(candidate_counts.get(alias, 0))
        learning_rows = int(learning_counts.get(alias, 0))
        onnx_runtime_rows = int(float((onnx_entry or {}).get("obserwacje_onnx", 0) or 0))
        outcome_rows = int(float((onnx_entry or {}).get("obserwacje_z_wynikiem_rynku", 0) or 0))
        paper_fresh = bool((paper_entry or {}).get("fresh", False))
        paper_freshness_seconds = (paper_entry or {}).get("freshness_seconds")

        raw_history_size_mb = 0.0
        raw_history_last_write_local = None
        export_size_mb = 0.0
        export_last_write_local = None
        export_name = None

        source_entry = present_entry or missing_entry or {}
        if source_entry:
            raw_history_size_mb = float(source_entry.get("history_size_mb", 0.0) or 0.0)
            raw_history_last_write_local = source_entry.get("history_last_write_local")
            export_size_mb = float(source_entry.get("export_size_mb", 0.0) or 0.0)
            export_last_write_local = source_entry.get("export_last_write_local")
            export_name = source_entry.get("export_file") or source_entry.get("mt5_export_name")

        data_readiness_state = get_data_readiness_state(
            raw_history_present=raw_history_present,
            active_export_present=active_export_present,
            qdm_contract_rows=qdm_contract_rows,
            candidate_rows=candidate_rows,
            learning_rows=learning_rows,
            onnx_runtime_rows=onnx_runtime_rows,
            outcome_rows=outcome_rows,
        )
        state_counter[data_readiness_state] += 1

        item = {
            "symbol_alias": alias,
            "broker_symbol": symbol_entry.get("broker_symbol"),
            "expert": symbol_entry.get("expert"),
            "session_profile": symbol_entry.get("session_profile"),
            "raw_history_present": raw_history_present,
            "raw_history_size_mb": round(raw_history_size_mb, 1),
            "raw_history_last_write_local": raw_history_last_write_local,
            "active_export_present": active_export_present,
            "active_export_name": export_name,
            "active_export_size_mb": round(export_size_mb, 1),
            "active_export_last_write_local": export_last_write_local,
            "qdm_contract_rows": qdm_contract_rows,
            "candidate_contract_rows": candidate_rows,
            "learning_contract_rows": learning_rows,
            "onnx_runtime_rows": onnx_runtime_rows,
            "outcome_rows": outcome_rows,
            "paper_live_fresh": paper_fresh,
            "paper_live_freshness_seconds": paper_freshness_seconds,
            "data_readiness_state": data_readiness_state,
        }
        items.append(item)

    items.sort(key=lambda row: (row["data_readiness_state"], row["symbol_alias"]))

    summary = {
        "total_symbols": len(items),
        "raw_history_present_count": sum(1 for item in items if item["raw_history_present"]),
        "active_export_present_count": sum(1 for item in items if item["active_export_present"]),
        "qdm_contract_ready_count": sum(1 for item in items if item["qdm_contract_rows"] > 0),
        "candidate_contract_ready_count": sum(1 for item in items if item["candidate_contract_rows"] > 0),
        "learning_contract_ready_count": sum(1 for item in items if item["learning_contract_rows"] > 0),
        "onnx_runtime_ready_count": sum(1 for item in items if item["onnx_runtime_rows"] > 0),
        "outcome_ready_count": sum(1 for item in items if item["outcome_rows"] > 0),
        "paper_fresh_count": sum(1 for item in items if item["paper_live_fresh"]),
        "export_pending_count": state_counter["EXPORT_PENDING"],
        "contract_pending_count": state_counter["CONTRACT_PENDING"],
        "training_shadow_ready_count": state_counter["TRAINING_SHADOW_READY"],
        "runtime_ready_count": state_counter["RUNTIME_READY"],
        "outcome_ready_state_count": state_counter["OUTCOME_READY"],
    }

    report = {
        "schema_version": "1.0",
        "generated_at_local": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        "summary": summary,
        "top_export_pending": [item for item in items if item["data_readiness_state"] == "EXPORT_PENDING"][:8],
        "top_contract_pending": [item for item in items if item["data_readiness_state"] == "CONTRACT_PENDING"][:8],
        "top_runtime_ready": [item for item in items if item["data_readiness_state"] in {"RUNTIME_READY", "OUTCOME_READY"}][:8],
        "items": items,
    }

    output_json = Path(args.output_json)
    output_md = Path(args.output_md)
    output_json.parent.mkdir(parents=True, exist_ok=True)

    output_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "# Instrument Data Readiness",
        "",
        f"- generated_at_local: {report['generated_at_local']}",
        f"- total_symbols: {summary['total_symbols']}",
        f"- raw_history_present_count: {summary['raw_history_present_count']}",
        f"- active_export_present_count: {summary['active_export_present_count']}",
        f"- qdm_contract_ready_count: {summary['qdm_contract_ready_count']}",
        f"- candidate_contract_ready_count: {summary['candidate_contract_ready_count']}",
        f"- learning_contract_ready_count: {summary['learning_contract_ready_count']}",
        f"- onnx_runtime_ready_count: {summary['onnx_runtime_ready_count']}",
        f"- outcome_ready_count: {summary['outcome_ready_count']}",
        f"- export_pending_count: {summary['export_pending_count']}",
        f"- contract_pending_count: {summary['contract_pending_count']}",
        "",
        "## Export Pending",
        "",
    ]
    export_pending = report["top_export_pending"]
    if not export_pending:
        lines.append("- none")
    else:
        for item in export_pending:
            lines.append(
                f"- {item['symbol_alias']}: raw={item['raw_history_present']}, export={item['active_export_present']}, "
                f"qdm_rows={item['qdm_contract_rows']}, export_name={item['active_export_name']}"
            )
    lines.extend(["", "## Contract Pending", ""])
    contract_pending = report["top_contract_pending"]
    if not contract_pending:
        lines.append("- none")
    else:
        for item in contract_pending:
            lines.append(
                f"- {item['symbol_alias']}: export={item['active_export_present']}, qdm_rows={item['qdm_contract_rows']}, "
                f"candidate_rows={item['candidate_contract_rows']}, learning_rows={item['learning_contract_rows']}"
            )
    lines.extend(["", "## Runtime Ready", ""])
    runtime_ready = report["top_runtime_ready"]
    if not runtime_ready:
        lines.append("- none")
    else:
        for item in runtime_ready:
            lines.append(
                f"- {item['symbol_alias']}: state={item['data_readiness_state']}, onnx_rows={item['onnx_runtime_rows']}, outcome_rows={item['outcome_rows']}, paper_fresh={item['paper_live_fresh']}"
            )

    output_md.write_text("\r\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
