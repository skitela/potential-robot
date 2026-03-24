#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import duckdb
import pandas as pd


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build feedback-loop report for runtime ONNX observations.")
    parser.add_argument("--db-path", default=r"C:\TRADING_DATA\RESEARCH\microbot_research.duckdb")
    parser.add_argument("--research-root", default=r"C:\TRADING_DATA\RESEARCH")
    parser.add_argument("--output-root", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS")
    parser.add_argument(
        "--runtime-logs-root",
        default=r"C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\logs",
    )
    parser.add_argument("--outcome-horizon-sec", type=int, default=21600)
    parser.add_argument("--score-threshold", type=float, default=0.5)
    return parser.parse_args()


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def sql_quote_path(path: str) -> str:
    return path.replace("\\", "/").replace("'", "''")


def scan_runtime_bootstrap(runtime_logs_root: Path) -> list[dict[str, Any]]:
    if not runtime_logs_root.exists():
        return []

    items: list[dict[str, Any]] = []
    for csv_path in sorted(runtime_logs_root.glob("*/onnx_observations.csv")):
        symbol_alias = csv_path.parent.name
        line_count = 0
        try:
            with csv_path.open("r", encoding="utf-8") as handle:
                for _ in handle:
                    line_count += 1
        except OSError:
            continue

        data_rows = max(0, line_count - 1)
        items.append(
            {
                "symbol_alias": symbol_alias,
                "csv_path": str(csv_path),
                "file_size_bytes": int(csv_path.stat().st_size),
                "line_count": line_count,
                "data_rows": data_rows,
                "runtime_initialized": line_count >= 1,
                "has_runtime_rows": data_rows > 0,
            }
        )

    return items


def table_exists(con: duckdb.DuckDBPyConnection, table_name: str) -> bool:
    row = con.execute(
        """
        SELECT 1
        FROM information_schema.tables
        WHERE table_name = ?
        LIMIT 1
        """,
        [table_name],
    ).fetchone()
    return row is not None


def normalized_contract_available(con: duckdb.DuckDBPyConnection) -> bool:
    required = [
        "onnx_observations_norm",
        "candidate_signals_norm",
        "learning_observations_v2_norm",
    ]
    return all(table_exists(con, table_name) for table_name in required)


def read_json_file(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def load_contract_manifest(research_root: Path) -> dict[str, Any]:
    return read_json_file(research_root / "reports" / "research_contract_manifest_latest.json")


def contract_parquet_available(contract_manifest: dict[str, Any]) -> bool:
    if not contract_manifest:
        return False

    items = contract_manifest.get("items", {})
    required = [
        "onnx_observations_norm",
        "candidate_signals_norm",
        "learning_observations_v2_norm",
    ]
    for item_name in required:
        item = items.get(item_name, {})
        path = item.get("path")
        if not path or not Path(str(path)).exists():
            return False
    return True


def empty_report(
    output_root: Path,
    db_path: Path,
    reason: str,
    horizon_sec: int,
    score_threshold: float,
    runtime_bootstrap_items: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    runtime_bootstrap_items = runtime_bootstrap_items or []
    report = {
        "generated_at_local": pd.Timestamp.now(tz="Europe/Warsaw").strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": pd.Timestamp.now(tz="UTC").isoformat(),
        "db_path": str(db_path),
        "outcome_horizon_sec": horizon_sec,
        "score_threshold": score_threshold,
        "summary": {
            "liczba_obserwacji_onnx": 0,
            "liczba_obserwacji_live": 0,
            "liczba_obserwacji_paper": 0,
            "liczba_obserwacji_z_kandydatem": 0,
            "liczba_obserwacji_z_wynikiem_rynku": 0,
            "liczba_symboli": 0,
            "liczba_symboli_z_plikiem_runtime": len(runtime_bootstrap_items),
            "liczba_symboli_zainicjalizowanych_runtime": sum(
                1 for item in runtime_bootstrap_items if item["runtime_initialized"]
            ),
            "liczba_symboli_z_wierszem_runtime": sum(
                1 for item in runtime_bootstrap_items if item["has_runtime_rows"]
            ),
        },
        "powod_braku_danych": reason,
        "runtime_bootstrap": runtime_bootstrap_items,
        "items": [],
    }
    write_report(report, output_root)
    return report


def write_report(report: dict[str, Any], output_root: Path) -> None:
    json_path = output_root / "onnx_feedback_loop_latest.json"
    md_path = output_root / "onnx_feedback_loop_latest.md"
    json_path.write_text(json.dumps(report, indent=2, ensure_ascii=True), encoding="utf-8")

    lines: list[str] = [
        "# Petla Zwrotna ONNX",
        "",
        f"- wygenerowano: {report['generated_at_local']}",
        f"- horyzont_powiazania_sec: {report['outcome_horizon_sec']}",
        f"- prog_oceny: {report['score_threshold']}",
        "",
        "## Podsumowanie",
        "",
        f"- liczba_obserwacji_onnx: {report['summary']['liczba_obserwacji_onnx']}",
        f"- liczba_obserwacji_live: {report['summary']['liczba_obserwacji_live']}",
        f"- liczba_obserwacji_paper: {report['summary']['liczba_obserwacji_paper']}",
        f"- liczba_obserwacji_z_kandydatem: {report['summary']['liczba_obserwacji_z_kandydatem']}",
        f"- liczba_obserwacji_z_wynikiem_rynku: {report['summary']['liczba_obserwacji_z_wynikiem_rynku']}",
        f"- liczba_symboli: {report['summary']['liczba_symboli']}",
        f"- liczba_symboli_z_plikiem_runtime: {report['summary'].get('liczba_symboli_z_plikiem_runtime', 0)}",
        f"- liczba_symboli_zainicjalizowanych_runtime: {report['summary'].get('liczba_symboli_zainicjalizowanych_runtime', 0)}",
        f"- liczba_symboli_z_wierszem_runtime: {report['summary'].get('liczba_symboli_z_wierszem_runtime', 0)}",
    ]

    reason = report.get("powod_braku_danych")
    if reason:
        lines.extend(["", f"- powod_braku_danych: {reason}"])

    runtime_bootstrap = report.get("runtime_bootstrap", [])
    if runtime_bootstrap:
        lines.extend(["", "## Inicjalizacja Runtime", ""])
        for item in runtime_bootstrap:
            lines.extend(
                [
                    f"### {item['symbol_alias']}",
                    f"- runtime_initialized: {item['runtime_initialized']}",
                    f"- has_runtime_rows: {item['has_runtime_rows']}",
                    f"- data_rows: {item['data_rows']}",
                    f"- file_size_bytes: {item['file_size_bytes']}",
                    "",
                ]
            )

    if report["items"]:
        lines.extend(["", "## Symbole", ""])
        for item in report["items"]:
            lines.extend(
                [
                    f"### {item['symbol_alias']}",
                    f"- obserwacje_onnx: {item['obserwacje_onnx']}",
                    f"- obserwacje_live: {item['obserwacje_live']}",
                    f"- obserwacje_paper: {item['obserwacje_paper']}",
                    f"- obserwacje_z_kandydatem: {item['obserwacje_z_kandydatem']}",
                    f"- obserwacje_z_wynikiem_rynku: {item['obserwacje_z_wynikiem_rynku']}",
                    f"- sredni_wynik_malego_onnx: {item['sredni_wynik_malego_onnx']}",
                    f"- sredni_wynik_nauczyciela: {item['sredni_wynik_nauczyciela']}",
                    f"- srednia_latencja_onnx_us: {item['srednia_latencja_onnx_us']}",
                    f"- zgodnosc_maly_vs_nauczyciel: {item['zgodnosc_maly_vs_nauczyciel']}",
                    f"- suma_pnl_powiazanego: {item['suma_pnl_powiazanego']}",
                    f"- skutecznosc_powiazana: {item['skutecznosc_powiazana']}",
                    f"- suma_pnl_gdy_maly_wyzszy: {item['suma_pnl_gdy_maly_wyzszy']}",
                    f"- suma_pnl_gdy_nauczyciel_wyzszy: {item['suma_pnl_gdy_nauczyciel_wyzszy']}",
                    "",
                ]
            )

    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    db_path = Path(args.db_path)
    research_root = Path(args.research_root)
    output_root = ensure_dir(Path(args.output_root))
    runtime_logs_root = Path(args.runtime_logs_root)
    runtime_bootstrap_items = scan_runtime_bootstrap(runtime_logs_root)
    contract_manifest = load_contract_manifest(research_root)
    use_contract_parquet = contract_parquet_available(contract_manifest)

    if (not use_contract_parquet) and (not db_path.exists()):
        empty_report(
            output_root,
            db_path,
            "brak_bazy_duckdb_i_kontraktu",
            args.outcome_horizon_sec,
            args.score_threshold,
            runtime_bootstrap_items,
        )
        return 0

    con: duckdb.DuckDBPyConnection | None = None
    try:
        if use_contract_parquet:
            con = duckdb.connect()
            contract_items = contract_manifest.get("items", {})
            con.execute(
                "CREATE OR REPLACE VIEW onnx_observations_norm AS SELECT * FROM read_parquet('{0}')".format(
                    sql_quote_path(str(contract_items["onnx_observations_norm"]["path"]))
                )
            )
            con.execute(
                "CREATE OR REPLACE VIEW candidate_signals_norm AS SELECT * FROM read_parquet('{0}')".format(
                    sql_quote_path(str(contract_items["candidate_signals_norm"]["path"]))
                )
            )
            con.execute(
                "CREATE OR REPLACE VIEW learning_observations_v2_norm AS SELECT * FROM read_parquet('{0}')".format(
                    sql_quote_path(str(contract_items["learning_observations_v2_norm"]["path"]))
                )
            )
            use_normalized_contract = True
            contract_source = f"parquet_{contract_manifest.get('contract_version', 'v1')}"
        else:
            con = duckdb.connect(str(db_path), read_only=True)
            required_tables = ["onnx_observations", "candidate_signals", "learning_observations_v2"]
            missing_tables = [table for table in required_tables if not table_exists(con, table)]
            if missing_tables:
                empty_report(
                    output_root,
                    db_path,
                    f"brak_tabel: {', '.join(missing_tables)}",
                    args.outcome_horizon_sec,
                    args.score_threshold,
                    runtime_bootstrap_items,
                )
                return 0

            use_normalized_contract = normalized_contract_available(con)
            contract_source = "normalized_v1" if use_normalized_contract else "raw_v0"

        if use_contract_parquet:
            onnx_rows = int(con.execute("SELECT COUNT(*) FROM onnx_observations_norm").fetchone()[0])
            onnx_runtime_rows = int(
                con.execute(
                    """
                    SELECT COUNT(*)
                    FROM onnx_observations_norm
                    WHERE stage = 'EVALUATED'
                      AND available = 1
                      AND reason_code = 'ONNX_OBSERVATION_OK'
                    """
                ).fetchone()[0]
            )
        else:
            onnx_rows = int(con.execute("SELECT COUNT(*) FROM onnx_observations").fetchone()[0])
            onnx_runtime_rows = int(
                con.execute(
                    """
                    SELECT COUNT(*)
                    FROM onnx_observations
                    WHERE stage = 'EVALUATED'
                      AND CAST(available AS BIGINT) = 1
                      AND CAST(reason_code AS VARCHAR) = 'ONNX_OBSERVATION_OK'
                    """
                ).fetchone()[0]
            )

        if onnx_runtime_rows <= 0:
            reason = "brak_obserwacji_onnx"
            if runtime_bootstrap_items:
                if any(item["has_runtime_rows"] for item in runtime_bootstrap_items):
                    reason = "runtime_ma_wiersze_ale_brak_udanej_inferencji_onnx"
                elif any(item["runtime_initialized"] for item in runtime_bootstrap_items):
                    reason = "runtime_onnx_zainicjalizowany_oczekuje_na_pierwsze_wiersze"
            empty_report(
                output_root,
                db_path,
                reason,
                args.outcome_horizon_sec,
                args.score_threshold,
                runtime_bootstrap_items,
            )
            return 0
        if use_normalized_contract:
            onnx_base_select = """
                SELECT
                    ts,
                    symbol_alias,
                    stage,
                    runtime_channel,
                    available,
                    teacher_available,
                    teacher_used,
                    teacher_score,
                    symbol_score,
                    latency_us,
                    reason_code AS onnx_reason_code,
                    signal_valid,
                    setup_type,
                    market_regime,
                    spread_regime,
                    confidence_bucket,
                    score,
                    confidence_score,
                    spread_points,
                    feedback_key
                FROM onnx_observations_norm
                WHERE stage = 'EVALUATED'
                  AND available = 1
                  AND reason_code = 'ONNX_OBSERVATION_OK'
            """
            candidate_base_select = """
                SELECT
                    ts,
                    symbol_alias,
                    stage,
                    accepted,
                    reason_code AS candidate_reason_code,
                    setup_type,
                    side,
                    COALESCE(
                        side_normalized,
                        CASE
                            WHEN UPPER(CAST(side AS VARCHAR)) IN ('BUY', '1', '+1') THEN 'BUY'
                            WHEN UPPER(CAST(side AS VARCHAR)) IN ('SELL', '-1') THEN 'SELL'
                            ELSE 'UNKNOWN'
                        END
                    ) AS side_normalized,
                    score,
                    confidence_score,
                    market_regime,
                    spread_regime,
                    execution_regime,
                    confidence_bucket,
                    candle_bias,
                    candle_quality_grade,
                    candle_score,
                    renko_bias,
                    renko_quality_grade,
                    renko_score,
                    renko_run_length,
                    renko_reversal_flag,
                    spread_points,
                    feedback_key,
                    outcome_key
                FROM candidate_signals_norm
                WHERE stage = 'EVALUATED'
            """
            learning_base_select = """
                SELECT
                    ts,
                    symbol_alias,
                    setup_type,
                    COALESCE(
                        side_normalized,
                        CASE
                            WHEN UPPER(CAST(side AS VARCHAR)) IN ('BUY', '1', '+1') THEN 'BUY'
                            WHEN UPPER(CAST(side AS VARCHAR)) IN ('SELL', '-1') THEN 'SELL'
                            ELSE 'UNKNOWN'
                        END
                    ) AS side_normalized,
                    pnl,
                    close_reason
                FROM learning_observations_v2_norm
            """
            candidate_join = """
                  ON c.ts = o.ts
                 AND c.symbol_alias = o.symbol_alias
                 AND c.feedback_key = o.feedback_key
            """
        else:
            onnx_base_select = """
                SELECT
                    CAST(ts AS BIGINT) AS ts,
                    CAST(symbol AS VARCHAR) AS symbol_alias,
                    CAST(stage AS VARCHAR) AS stage,
                    CAST(COALESCE(runtime_channel, 'UNKNOWN') AS VARCHAR) AS runtime_channel,
                    CAST(available AS BIGINT) AS available,
                    CAST(teacher_available AS BIGINT) AS teacher_available,
                    CAST(teacher_used AS BIGINT) AS teacher_used,
                    CAST(teacher_score AS DOUBLE) AS teacher_score,
                    CAST(symbol_score AS DOUBLE) AS symbol_score,
                    CAST(latency_us AS DOUBLE) AS latency_us,
                    CAST(reason_code AS VARCHAR) AS onnx_reason_code,
                    CAST(signal_valid AS BIGINT) AS signal_valid,
                    CAST(setup_type AS VARCHAR) AS setup_type,
                    CAST(market_regime AS VARCHAR) AS market_regime,
                    CAST(spread_regime AS VARCHAR) AS spread_regime,
                    CAST(confidence_bucket AS VARCHAR) AS confidence_bucket,
                    CAST(score AS DOUBLE) AS score,
                    CAST(confidence_score AS DOUBLE) AS confidence_score,
                    CAST(spread_points AS DOUBLE) AS spread_points
                FROM onnx_observations
                WHERE stage = 'EVALUATED'
                  AND CAST(available AS BIGINT) = 1
                  AND CAST(reason_code AS VARCHAR) = 'ONNX_OBSERVATION_OK'
            """
            candidate_base_select = """
                SELECT
                    CAST(ts AS BIGINT) AS ts,
                    CAST(symbol AS VARCHAR) AS symbol_alias,
                    CAST(stage AS VARCHAR) AS stage,
                    CAST(accepted AS BIGINT) AS accepted,
                    CAST(reason_code AS VARCHAR) AS candidate_reason_code,
                    CAST(setup_type AS VARCHAR) AS setup_type,
                    CAST(side AS VARCHAR) AS side,
                    CASE
                        WHEN UPPER(CAST(side AS VARCHAR)) IN ('BUY', '1', '+1') THEN 'BUY'
                        WHEN UPPER(CAST(side AS VARCHAR)) IN ('SELL', '-1') THEN 'SELL'
                        ELSE 'UNKNOWN'
                    END AS side_normalized,
                    CAST(score AS DOUBLE) AS score,
                    CAST(confidence_score AS DOUBLE) AS confidence_score,
                    CAST(market_regime AS VARCHAR) AS market_regime,
                    CAST(spread_regime AS VARCHAR) AS spread_regime,
                    CAST(execution_regime AS VARCHAR) AS execution_regime,
                    CAST(confidence_bucket AS VARCHAR) AS confidence_bucket,
                    CAST(candle_bias AS VARCHAR) AS candle_bias,
                    CAST(candle_quality_grade AS VARCHAR) AS candle_quality_grade,
                    CAST(candle_score AS DOUBLE) AS candle_score,
                    CAST(renko_bias AS VARCHAR) AS renko_bias,
                    CAST(renko_quality_grade AS VARCHAR) AS renko_quality_grade,
                    CAST(renko_score AS DOUBLE) AS renko_score,
                    CAST(renko_run_length AS BIGINT) AS renko_run_length,
                    CAST(renko_reversal_flag AS BIGINT) AS renko_reversal_flag,
                    CAST(spread_points AS DOUBLE) AS spread_points,
                    CAST(symbol AS VARCHAR) || '|' || CAST(setup_type AS VARCHAR) || '|' || CAST(market_regime AS VARCHAR) || '|' || CAST(spread_regime AS VARCHAR) || '|' || CAST(confidence_bucket AS VARCHAR) AS feedback_key,
                    CAST(symbol AS VARCHAR) || '|' || CAST(setup_type AS VARCHAR) || '|' || CAST(market_regime AS VARCHAR) || '|' || CAST(spread_regime AS VARCHAR) || '|' || CAST(execution_regime AS VARCHAR) || '|' || CAST(confidence_bucket AS VARCHAR) || '|' || CAST(side AS VARCHAR) || '|' || CAST(CAST(renko_run_length AS BIGINT) AS VARCHAR) || '|' || CAST(CAST(renko_reversal_flag AS BIGINT) AS VARCHAR) AS outcome_key
                FROM candidate_signals
                WHERE stage = 'EVALUATED'
            """
            learning_base_select = """
                SELECT
                    CAST(ts AS BIGINT) AS ts,
                    CAST(symbol AS VARCHAR) AS symbol_alias,
                    CAST(setup_type AS VARCHAR) AS setup_type,
                    CASE
                        WHEN UPPER(CAST(side AS VARCHAR)) IN ('BUY', '1', '+1') THEN 'BUY'
                        WHEN UPPER(CAST(side AS VARCHAR)) IN ('SELL', '-1') THEN 'SELL'
                        ELSE 'UNKNOWN'
                    END AS side_normalized,
                    CAST(pnl AS DOUBLE) AS pnl,
                    CAST(close_reason AS VARCHAR) AS close_reason
                FROM learning_observations_v2
            """
            candidate_join = """
                  ON c.ts = o.ts
                 AND c.symbol_alias = o.symbol_alias
                 AND c.setup_type = o.setup_type
                 AND c.market_regime = o.market_regime
                 AND c.spread_regime = o.spread_regime
                 AND c.confidence_bucket = o.confidence_bucket
            """

        query = f"""
            WITH onnx_base AS (
                SELECT
                    ROW_NUMBER() OVER () AS onnx_row_id,
                    *
                FROM (
                    {onnx_base_select}
                )
            ),
            candidate_base AS (
                SELECT
                    ROW_NUMBER() OVER () AS candidate_row_id,
                    *
                FROM (
                    {candidate_base_select}
                )
            ),
            learning_base AS (
                {learning_base_select}
            ),
            linked_candidates_raw AS (
                SELECT
                    o.onnx_row_id,
                    o.ts,
                    o.symbol_alias,
                    o.stage,
                    o.runtime_channel,
                    o.available,
                    o.teacher_available,
                    o.teacher_used,
                    o.teacher_score,
                    o.symbol_score,
                    o.latency_us,
                    o.onnx_reason_code,
                    o.signal_valid,
                    o.setup_type,
                    o.market_regime,
                    o.spread_regime,
                    o.confidence_bucket,
                    o.score,
                    o.confidence_score,
                    o.spread_points,
                    o.feedback_key,
                    c.candidate_row_id,
                    c.accepted,
                    c.candidate_reason_code,
                    c.side,
                    c.side_normalized,
                    c.execution_regime,
                    c.feedback_key AS candidate_feedback_key,
                    c.outcome_key,
                    c.candle_bias,
                    c.candle_quality_grade,
                    c.candle_score,
                    c.renko_bias,
                    c.renko_quality_grade,
                    c.renko_score,
                    c.renko_run_length,
                    c.renko_reversal_flag,
                    ROW_NUMBER() OVER (
                        PARTITION BY o.onnx_row_id
                        ORDER BY
                            CASE WHEN c.candidate_row_id IS NULL THEN 1 ELSE 0 END,
                            CASE WHEN COALESCE(c.accepted, 0) = 1 THEN 0 ELSE 1 END,
                            ABS(COALESCE(c.score, 0.0) - COALESCE(o.symbol_score, 0.0)),
                            COALESCE(c.candidate_row_id, 2147483647)
                    ) AS candidate_rank
                FROM onnx_base o
                LEFT JOIN candidate_base c
                {candidate_join}
            ),
            linked_candidates AS (
                SELECT * EXCLUDE(candidate_rank)
                FROM linked_candidates_raw
                WHERE candidate_rank = 1
            ),
            accepted_candidates AS (
                SELECT *
                FROM linked_candidates
                WHERE accepted = 1 AND candidate_row_id IS NOT NULL
            ),
            ranked_outcomes AS (
                SELECT
                    ac.candidate_row_id,
                    lb.ts AS outcome_ts,
                    lb.pnl AS outcome_pnl,
                    lb.close_reason AS outcome_close_reason,
                    ROW_NUMBER() OVER (
                        PARTITION BY ac.candidate_row_id
                        ORDER BY lb.ts
                    ) AS outcome_rank
                FROM accepted_candidates ac
                LEFT JOIN learning_base lb
                  ON lb.symbol_alias = ac.symbol_alias
                 AND lb.setup_type = ac.setup_type
                 AND lb.side_normalized = ac.side_normalized
                 AND lb.ts >= ac.ts
                 AND lb.ts <= ac.ts + {int(args.outcome_horizon_sec)}
            ),
            resolved_outcomes AS (
                SELECT *
                FROM ranked_outcomes
                WHERE outcome_rank = 1 OR outcome_rank IS NULL
            ),
            resolved AS (
                SELECT
                    lc.*,
                    ro.outcome_ts,
                    ro.outcome_pnl,
                    ro.outcome_close_reason
                FROM linked_candidates lc
                LEFT JOIN resolved_outcomes ro
                  ON ro.candidate_row_id = lc.candidate_row_id
            ),
            enriched AS (
                SELECT
                    *,
                    CASE WHEN symbol_score >= {float(args.score_threshold)} THEN 1 ELSE 0 END AS small_positive,
                    CASE WHEN teacher_score >= {float(args.score_threshold)} THEN 1 ELSE 0 END AS teacher_positive,
                    CASE WHEN outcome_pnl IS NOT NULL AND outcome_pnl >= 0 THEN 1 ELSE 0 END AS outcome_win,
                    CASE WHEN symbol_score > teacher_score THEN 1 ELSE 0 END AS small_higher_than_teacher
                FROM resolved
            )
            SELECT
                symbol_alias,
                COUNT(*) AS obserwacje_onnx,
                SUM(CASE WHEN runtime_channel = 'LIVE' THEN 1 ELSE 0 END) AS obserwacje_live,
                SUM(CASE WHEN runtime_channel = 'PAPER' THEN 1 ELSE 0 END) AS obserwacje_paper,
                SUM(CASE WHEN candidate_row_id IS NOT NULL THEN 1 ELSE 0 END) AS obserwacje_z_kandydatem,
                SUM(CASE WHEN outcome_pnl IS NOT NULL THEN 1 ELSE 0 END) AS obserwacje_z_wynikiem_rynku,
                ROUND(AVG(symbol_score), 6) AS sredni_wynik_malego_onnx,
                ROUND(AVG(teacher_score), 6) AS sredni_wynik_nauczyciela,
                ROUND(AVG(latency_us), 2) AS srednia_latencja_onnx_us,
                ROUND(AVG(CASE WHEN small_positive = teacher_positive THEN 1.0 ELSE 0.0 END), 4) AS zgodnosc_maly_vs_nauczyciel,
                ROUND(COALESCE(SUM(outcome_pnl), 0.0), 4) AS suma_pnl_powiazanego,
                ROUND(AVG(CASE WHEN outcome_pnl IS NOT NULL THEN outcome_win::DOUBLE ELSE NULL END), 4) AS skutecznosc_powiazana,
                ROUND(COALESCE(SUM(CASE WHEN small_higher_than_teacher = 1 THEN outcome_pnl ELSE 0.0 END), 0.0), 4) AS suma_pnl_gdy_maly_wyzszy,
                ROUND(COALESCE(SUM(CASE WHEN small_higher_than_teacher = 0 THEN outcome_pnl ELSE 0.0 END), 0.0), 4) AS suma_pnl_gdy_nauczyciel_wyzszy
            FROM enriched
            GROUP BY symbol_alias
            ORDER BY obserwacje_z_wynikiem_rynku DESC, obserwacje_onnx DESC, symbol_alias
        """

        items_df = con.execute(query).df()

        summary_query = f"""
            WITH onnx_base AS (
                SELECT
                    ROW_NUMBER() OVER () AS onnx_row_id,
                    *
                FROM (
                    {onnx_base_select}
                )
            ),
            candidate_base AS (
                SELECT
                    ROW_NUMBER() OVER () AS candidate_row_id,
                    *
                FROM (
                    {candidate_base_select}
                )
            ),
            learning_base AS (
                {learning_base_select}
            ),
            linked_candidates_raw AS (
                SELECT
                    o.onnx_row_id,
                    o.ts,
                    o.symbol_alias,
                    o.runtime_channel,
                    o.setup_type,
                    c.candidate_row_id,
                    c.accepted,
                    c.side,
                    c.side_normalized,
                    c.execution_regime,
                    c.feedback_key AS candidate_feedback_key,
                    c.outcome_key,
                    c.renko_run_length,
                    c.renko_reversal_flag,
                    o.market_regime,
                    o.spread_regime,
                    o.confidence_bucket,
                    ROW_NUMBER() OVER (
                        PARTITION BY o.onnx_row_id
                        ORDER BY
                            CASE WHEN c.candidate_row_id IS NULL THEN 1 ELSE 0 END,
                            CASE WHEN COALESCE(c.accepted, 0) = 1 THEN 0 ELSE 1 END,
                            COALESCE(c.candidate_row_id, 2147483647)
                    ) AS candidate_rank
                FROM onnx_base o
                LEFT JOIN candidate_base c
                {candidate_join}
            ),
            linked_candidates AS (
                SELECT * EXCLUDE(candidate_rank)
                FROM linked_candidates_raw
                WHERE candidate_rank = 1
            ),
            accepted_candidates AS (
                SELECT *
                FROM linked_candidates
                WHERE accepted = 1 AND candidate_row_id IS NOT NULL
            ),
            ranked_outcomes AS (
                SELECT
                    ac.candidate_row_id,
                    lb.pnl AS outcome_pnl,
                    ROW_NUMBER() OVER (
                        PARTITION BY ac.candidate_row_id
                        ORDER BY lb.ts
                    ) AS outcome_rank
                FROM accepted_candidates ac
                LEFT JOIN learning_base lb
                  ON lb.symbol_alias = ac.symbol_alias
                 AND lb.setup_type = ac.setup_type
                 AND lb.side_normalized = ac.side_normalized
                 AND lb.ts >= ac.ts
                 AND lb.ts <= ac.ts + {int(args.outcome_horizon_sec)}
            ),
            resolved_outcomes AS (
                SELECT *
                FROM ranked_outcomes
                WHERE outcome_rank = 1 OR outcome_rank IS NULL
            ),
            resolved AS (
                SELECT
                    lc.*,
                    ro.outcome_pnl
                FROM linked_candidates lc
                LEFT JOIN resolved_outcomes ro
                  ON ro.candidate_row_id = lc.candidate_row_id
            )
            SELECT
                COUNT(*) AS liczba_obserwacji_onnx,
                SUM(CASE WHEN runtime_channel = 'LIVE' THEN 1 ELSE 0 END) AS liczba_obserwacji_live,
                SUM(CASE WHEN runtime_channel = 'PAPER' THEN 1 ELSE 0 END) AS liczba_obserwacji_paper,
                SUM(CASE WHEN candidate_row_id IS NOT NULL THEN 1 ELSE 0 END) AS liczba_obserwacji_z_kandydatem,
                SUM(CASE WHEN outcome_pnl IS NOT NULL THEN 1 ELSE 0 END) AS liczba_obserwacji_z_wynikiem_rynku,
                COUNT(DISTINCT symbol_alias) AS liczba_symboli
            FROM resolved
        """
        summary_row = con.execute(summary_query).fetchone()
    finally:
        if con is not None:
            con.close()

    summary = {
        "liczba_obserwacji_onnx": int(summary_row[0] or 0),
        "liczba_obserwacji_live": int(summary_row[1] or 0),
        "liczba_obserwacji_paper": int(summary_row[2] or 0),
        "liczba_obserwacji_z_kandydatem": int(summary_row[3] or 0),
        "liczba_obserwacji_z_wynikiem_rynku": int(summary_row[4] or 0),
        "liczba_symboli": int(summary_row[5] or 0),
        "liczba_symboli_z_plikiem_runtime": len(runtime_bootstrap_items),
        "liczba_symboli_zainicjalizowanych_runtime": sum(
            1 for item in runtime_bootstrap_items if item["runtime_initialized"]
        ),
        "liczba_symboli_z_wierszem_runtime": sum(1 for item in runtime_bootstrap_items if item["has_runtime_rows"]),
    }

    report = {
        "generated_at_local": pd.Timestamp.now(tz="Europe/Warsaw").strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": pd.Timestamp.now(tz="UTC").isoformat(),
        "db_path": str(db_path),
        "outcome_horizon_sec": int(args.outcome_horizon_sec),
        "score_threshold": float(args.score_threshold),
        "contract_source": contract_source,
        "summary": summary,
        "powod_braku_danych": (None if summary["liczba_obserwacji_onnx"] > 0 else "brak_obserwacji_po_filtrowaniu"),
        "runtime_bootstrap": runtime_bootstrap_items,
        "items": items_df.to_dict(orient="records"),
    }
    write_report(report, output_root)
    print(
        json.dumps(
            {
                "generated_at_local": report["generated_at_local"],
                "contract_source": contract_source,
                "summary": report["summary"],
            },
            indent=2,
            ensure_ascii=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
