from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime
from pathlib import Path

import duckdb


READY_DATA_STATES = {"CONTRACT_READY", "TRAINING_SHADOW_READY", "RUNTIME_READY", "OUTCOME_READY"}


def read_json(path: Path):
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8-sig"))


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def sql_quote(path: Path) -> str:
    return path.as_posix().replace("'", "''")


def build_filtered_parquet(
    con: duckdb.DuckDBPyConnection,
    source_path: Path,
    output_path: Path,
    alias: str,
) -> int:
    rows_total = int(
        con.execute(
            f"""
            select count(*)
            from read_parquet('{sql_quote(source_path)}')
            where upper(trim(symbol_alias)) = ?
            """,
            [alias],
        ).fetchone()[0]
    )
    if rows_total <= 0:
        if output_path.exists():
            output_path.unlink()
        return 0

    ensure_dir(output_path.parent)
    con.execute(
        f"""
        copy (
            select *
            from read_parquet('{sql_quote(source_path)}')
            where upper(trim(symbol_alias)) = ?
        )
        to '{sql_quote(output_path)}' (format parquet)
        """,
        [alias],
    )
    return rows_total


def build_shadow_state(item: dict) -> str:
    if int(item.get("outcome_rows", 0) or 0) > 0:
        return "SHADOW_OUTCOME_READY"
    if int(item.get("onnx_runtime_rows", 0) or 0) > 0:
        return "SHADOW_RUNTIME_READY"
    return "SHADOW_READY"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-readiness", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_data_readiness_latest.json")
    parser.add_argument("--training-readiness", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_training_readiness_latest.json")
    parser.add_argument("--qdm-minute-bars", default=r"C:\TRADING_DATA\RESEARCH\datasets\qdm_minute_bars_latest.parquet")
    parser.add_argument("--candidate-contract", default=r"C:\TRADING_DATA\RESEARCH\datasets\contracts\candidate_signals_norm_latest.parquet")
    parser.add_argument("--learning-contract", default=r"C:\TRADING_DATA\RESEARCH\datasets\contracts\learning_observations_v2_norm_latest.parquet")
    parser.add_argument("--onnx-contract", default=r"C:\TRADING_DATA\RESEARCH\datasets\contracts\onnx_observations_norm_latest.parquet")
    parser.add_argument("--shadow-root", default=r"C:\TRADING_DATA\RESEARCH\datasets\shadow_per_instrument")
    parser.add_argument("--output-json", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_shadow_datasets_latest.json")
    parser.add_argument("--output-md", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_shadow_datasets_latest.md")
    args = parser.parse_args()

    data_readiness = read_json(Path(args.data_readiness))
    training_readiness = read_json(Path(args.training_readiness))
    if not data_readiness:
        raise SystemExit(f"Missing data readiness report: {args.data_readiness}")

    training_map: dict[str, dict] = {}
    if training_readiness:
        for item in training_readiness.get("items", []):
            alias = str(item.get("symbol_alias", "")).strip().upper()
            if alias:
                training_map[alias] = item

    shadow_root = Path(args.shadow_root)
    ensure_dir(shadow_root)
    ensure_dir(Path(args.output_json).parent)

    con = duckdb.connect()

    items: list[dict] = []
    for data_item in data_readiness.get("items", []):
        alias = str(data_item.get("symbol_alias", "")).strip().upper()
        if not alias:
            continue

        training_item = training_map.get(alias, {})
        data_state = str(data_item.get("data_readiness_state", "")).strip()
        qdm_rows = int(data_item.get("qdm_contract_rows", 0) or 0)
        candidate_rows = int(data_item.get("candidate_contract_rows", 0) or 0)
        learning_rows = int(data_item.get("learning_contract_rows", 0) or 0)
        onnx_rows = int(data_item.get("onnx_runtime_rows", 0) or 0)
        outcome_rows = int(data_item.get("outcome_rows", 0) or 0)

        symbol_root = shadow_root / alias
        manifest_path = symbol_root / "shadow_dataset_manifest.json"

        eligible = (
            data_state in READY_DATA_STATES
            and qdm_rows > 0
            and (candidate_rows > 0 or learning_rows > 0 or onnx_rows > 0 or outcome_rows > 0)
        )

        item = {
            "symbol_alias": alias,
            "data_readiness_state": data_state,
            "training_readiness_state": str(training_item.get("training_readiness_state", "")),
            "teacher_dependency_level": str(training_item.get("teacher_dependency_level", "")),
            "eligible_for_shadow_dataset": eligible,
            "shadow_dataset_state": "NOT_READY",
            "shadow_root": str(symbol_root),
            "manifest_path": str(manifest_path),
            "qdm_rows": 0,
            "candidate_rows": 0,
            "learning_rows": 0,
            "onnx_rows": 0,
            "outcome_rows": outcome_rows,
            "files_present": 0,
            "reason": "",
        }

        if not eligible:
            if qdm_rows <= 0:
                item["reason"] = "Brak QDM w kontrakcie."
            else:
                item["reason"] = "Brak wystarczajacego lokalnego materialu do shadow dataset."
            items.append(item)
            continue

        ensure_dir(symbol_root)
        qdm_out = symbol_root / "qdm_minute_bars_latest.parquet"
        candidate_out = symbol_root / "candidate_signals_norm_latest.parquet"
        learning_out = symbol_root / "learning_observations_v2_norm_latest.parquet"
        onnx_out = symbol_root / "onnx_observations_norm_latest.parquet"

        qdm_count = build_filtered_parquet(con, Path(args.qdm_minute_bars), qdm_out, alias)
        candidate_count = build_filtered_parquet(con, Path(args.candidate_contract), candidate_out, alias)
        learning_count = build_filtered_parquet(con, Path(args.learning_contract), learning_out, alias)
        onnx_count = build_filtered_parquet(con, Path(args.onnx_contract), onnx_out, alias)

        shadow_state = build_shadow_state(
            {
                "onnx_runtime_rows": onnx_count,
                "outcome_rows": outcome_rows,
            }
        )

        manifest = {
            "symbol_alias": alias,
            "generated_at_local": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "generated_at_utc": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            "shadow_dataset_state": shadow_state,
            "data_readiness_state": data_state,
            "training_readiness_state": str(training_item.get("training_readiness_state", "")),
            "teacher_dependency_level": str(training_item.get("teacher_dependency_level", "")),
            "files": {
                "qdm_minute_bars": {"path": str(qdm_out), "rows": qdm_count},
                "candidate_signals_norm": {"path": str(candidate_out), "rows": candidate_count},
                "learning_observations_v2_norm": {"path": str(learning_out), "rows": learning_count},
                "onnx_observations_norm": {"path": str(onnx_out), "rows": onnx_count},
            },
        }
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

        item.update(
            {
                "shadow_dataset_state": shadow_state,
                "qdm_rows": qdm_count,
                "candidate_rows": candidate_count,
                "learning_rows": learning_count,
                "onnx_rows": onnx_count,
                "files_present": sum(1 for rows in [qdm_count, candidate_count, learning_count, onnx_count] if rows > 0),
                "reason": "Shadow dataset zbudowany.",
            }
        )
        items.append(item)

    con.close()

    items.sort(key=lambda row: (row["shadow_dataset_state"], row["symbol_alias"]))

    summary = {
        "total_symbols": len(items),
        "shadow_dataset_ready_count": sum(1 for item in items if item["shadow_dataset_state"] == "SHADOW_READY"),
        "shadow_dataset_runtime_ready_count": sum(1 for item in items if item["shadow_dataset_state"] == "SHADOW_RUNTIME_READY"),
        "shadow_dataset_outcome_ready_count": sum(1 for item in items if item["shadow_dataset_state"] == "SHADOW_OUTCOME_READY"),
        "shadow_dataset_not_ready_count": sum(1 for item in items if item["shadow_dataset_state"] == "NOT_READY"),
        "eligible_for_shadow_dataset_count": sum(1 for item in items if item["eligible_for_shadow_dataset"]),
    }

    report = {
        "schema_version": "1.0",
        "generated_at_local": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        "shadow_root": str(shadow_root),
        "summary": summary,
        "top_ready": [item for item in items if item["shadow_dataset_state"] != "NOT_READY"][:8],
        "top_not_ready": [item for item in items if item["shadow_dataset_state"] == "NOT_READY"][:8],
        "items": items,
    }

    output_json = Path(args.output_json)
    output_md = Path(args.output_md)
    output_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "# Instrument Shadow Datasets",
        "",
        f"- generated_at_local: {report['generated_at_local']}",
        f"- total_symbols: {summary['total_symbols']}",
        f"- eligible_for_shadow_dataset_count: {summary['eligible_for_shadow_dataset_count']}",
        f"- shadow_dataset_ready_count: {summary['shadow_dataset_ready_count']}",
        f"- shadow_dataset_runtime_ready_count: {summary['shadow_dataset_runtime_ready_count']}",
        f"- shadow_dataset_outcome_ready_count: {summary['shadow_dataset_outcome_ready_count']}",
        f"- shadow_dataset_not_ready_count: {summary['shadow_dataset_not_ready_count']}",
        "",
        "## Ready",
        "",
    ]
    ready = report["top_ready"]
    if not ready:
        lines.append("- none")
    else:
        for item in ready:
            lines.append(
                f"- {item['symbol_alias']}: state={item['shadow_dataset_state']}, qdm={item['qdm_rows']}, "
                f"candidate={item['candidate_rows']}, learning={item['learning_rows']}, onnx={item['onnx_rows']}"
            )
    lines.extend(["", "## Not Ready", ""])
    not_ready = report["top_not_ready"]
    if not not_ready:
        lines.append("- none")
    else:
        for item in not_ready:
            lines.append(f"- {item['symbol_alias']}: {item['reason']}")

    output_md.write_text("\r\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
