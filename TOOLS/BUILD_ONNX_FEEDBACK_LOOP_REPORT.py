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
    parser.add_argument("--output-root", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS")
    parser.add_argument("--outcome-horizon-sec", type=int, default=21600)
    parser.add_argument("--score-threshold", type=float, default=0.5)
    return parser.parse_args()


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


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


def empty_report(output_root: Path, db_path: Path, reason: str, horizon_sec: int, score_threshold: float) -> dict[str, Any]:
    report = {
        "generated_at_local": pd.Timestamp.now(tz="Europe/Warsaw").strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": pd.Timestamp.now(tz="UTC").isoformat(),
        "db_path": str(db_path),
        "outcome_horizon_sec": horizon_sec,
        "score_threshold": score_threshold,
        "summary": {
            "liczba_obserwacji_onnx": 0,
            "liczba_obserwacji_z_kandydatem": 0,
            "liczba_obserwacji_z_wynikiem_rynku": 0,
            "liczba_symboli": 0,
        },
        "powod_braku_danych": reason,
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
        f"- liczba_obserwacji_z_kandydatem: {report['summary']['liczba_obserwacji_z_kandydatem']}",
        f"- liczba_obserwacji_z_wynikiem_rynku: {report['summary']['liczba_obserwacji_z_wynikiem_rynku']}",
        f"- liczba_symboli: {report['summary']['liczba_symboli']}",
    ]

    reason = report.get("powod_braku_danych")
    if reason:
        lines.extend(["", f"- powod_braku_danych: {reason}"])

    if report["items"]:
        lines.extend(["", "## Symbole", ""])
        for item in report["items"]:
            lines.extend(
                [
                    f"### {item['symbol_alias']}",
                    f"- obserwacje_onnx: {item['obserwacje_onnx']}",
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
    output_root = ensure_dir(Path(args.output_root))

    if not db_path.exists():
        empty_report(output_root, db_path, "brak_bazy_duckdb", args.outcome_horizon_sec, args.score_threshold)
        return 0

    with duckdb.connect(str(db_path), read_only=True) as con:
        required_tables = ["onnx_observations", "candidate_signals", "learning_observations_v2"]
        missing_tables = [table for table in required_tables if not table_exists(con, table)]
        if missing_tables:
            empty_report(
                output_root,
                db_path,
                f"brak_tabel: {', '.join(missing_tables)}",
                args.outcome_horizon_sec,
                args.score_threshold,
            )
            return 0

        onnx_rows = int(con.execute("SELECT COUNT(*) FROM onnx_observations").fetchone()[0])
        if onnx_rows <= 0:
            empty_report(output_root, db_path, "brak_obserwacji_onnx", args.outcome_horizon_sec, args.score_threshold)
            return 0

        query = f"""
            WITH onnx_base AS (
                SELECT
                    CAST(ts AS BIGINT) AS ts,
                    CAST(symbol AS VARCHAR) AS symbol_alias,
                    CAST(stage AS VARCHAR) AS stage,
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
            ),
            candidate_base AS (
                SELECT
                    CAST(ts AS BIGINT) AS ts,
                    CAST(symbol AS VARCHAR) AS symbol_alias,
                    CAST(stage AS VARCHAR) AS stage,
                    CAST(accepted AS BIGINT) AS accepted,
                    CAST(reason_code AS VARCHAR) AS candidate_reason_code,
                    CAST(setup_type AS VARCHAR) AS setup_type,
                    CAST(side AS BIGINT) AS side,
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
                    CAST(spread_points AS DOUBLE) AS spread_points
                FROM candidate_signals
                WHERE stage = 'EVALUATED'
            ),
            linked_candidates AS (
                SELECT
                    o.*,
                    c.accepted,
                    c.candidate_reason_code,
                    c.side,
                    c.execution_regime,
                    c.candle_bias,
                    c.candle_quality_grade,
                    c.candle_score,
                    c.renko_bias,
                    c.renko_quality_grade,
                    c.renko_score,
                    c.renko_run_length,
                    c.renko_reversal_flag
                FROM onnx_base o
                LEFT JOIN candidate_base c
                  ON c.ts = o.ts
                 AND c.symbol_alias = o.symbol_alias
                 AND c.setup_type = o.setup_type
                 AND c.market_regime = o.market_regime
                 AND c.spread_regime = o.spread_regime
                 AND c.confidence_bucket = o.confidence_bucket
            ),
            ranked_outcomes AS (
                SELECT
                    lc.*,
                    CAST(lo.ts AS BIGINT) AS outcome_ts,
                    CAST(lo.pnl AS DOUBLE) AS outcome_pnl,
                    CAST(lo.close_reason AS VARCHAR) AS outcome_close_reason,
                    ROW_NUMBER() OVER (
                        PARTITION BY lc.ts, lc.symbol_alias, lc.setup_type
                        ORDER BY CAST(lo.ts AS BIGINT)
                    ) AS outcome_rank
                FROM linked_candidates lc
                LEFT JOIN learning_observations_v2 lo
                  ON lo.symbol = lc.symbol_alias
                 AND lo.setup_type = lc.setup_type
                 AND lo.market_regime = lc.market_regime
                 AND lo.spread_regime = COALESCE(lc.spread_regime, lo.spread_regime)
                 AND lo.execution_regime = COALESCE(lc.execution_regime, lo.execution_regime)
                 AND lo.confidence_bucket = COALESCE(lc.confidence_bucket, lo.confidence_bucket)
                 AND CAST(lo.side AS BIGINT) = COALESCE(lc.side, CAST(lo.side AS BIGINT))
                 AND CAST(lo.renko_run_length AS BIGINT) = COALESCE(lc.renko_run_length, CAST(lo.renko_run_length AS BIGINT))
                 AND CAST(lo.renko_reversal_flag AS BIGINT) = COALESCE(lc.renko_reversal_flag, CAST(lo.renko_reversal_flag AS BIGINT))
                 AND CAST(lo.ts AS BIGINT) >= lc.ts
                 AND CAST(lo.ts AS BIGINT) <= lc.ts + {int(args.outcome_horizon_sec)}
            ),
            resolved AS (
                SELECT *
                FROM ranked_outcomes
                WHERE outcome_rank = 1 OR outcome_rank IS NULL
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
                SUM(CASE WHEN accepted IS NOT NULL THEN 1 ELSE 0 END) AS obserwacje_z_kandydatem,
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
                    CAST(ts AS BIGINT) AS ts,
                    CAST(symbol AS VARCHAR) AS symbol_alias,
                    CAST(stage AS VARCHAR) AS stage,
                    CAST(teacher_score AS DOUBLE) AS teacher_score,
                    CAST(symbol_score AS DOUBLE) AS symbol_score,
                    CAST(latency_us AS DOUBLE) AS latency_us,
                    CAST(setup_type AS VARCHAR) AS setup_type,
                    CAST(market_regime AS VARCHAR) AS market_regime,
                    CAST(spread_regime AS VARCHAR) AS spread_regime,
                    CAST(confidence_bucket AS VARCHAR) AS confidence_bucket
                FROM onnx_observations
                WHERE stage = 'EVALUATED'
            ),
            candidate_base AS (
                SELECT
                    CAST(ts AS BIGINT) AS ts,
                    CAST(symbol AS VARCHAR) AS symbol_alias,
                    CAST(setup_type AS VARCHAR) AS setup_type,
                    CAST(market_regime AS VARCHAR) AS market_regime,
                    CAST(spread_regime AS VARCHAR) AS spread_regime,
                    CAST(confidence_bucket AS VARCHAR) AS confidence_bucket,
                    CAST(accepted AS BIGINT) AS accepted,
                    CAST(side AS BIGINT) AS side,
                    CAST(execution_regime AS VARCHAR) AS execution_regime,
                    CAST(renko_run_length AS BIGINT) AS renko_run_length,
                    CAST(renko_reversal_flag AS BIGINT) AS renko_reversal_flag
                FROM candidate_signals
                WHERE stage = 'EVALUATED'
            ),
            linked_candidates AS (
                SELECT
                    o.*,
                    c.accepted,
                    c.side,
                    c.execution_regime,
                    c.renko_run_length,
                    c.renko_reversal_flag
                FROM onnx_base o
                LEFT JOIN candidate_base c
                  ON c.ts = o.ts
                 AND c.symbol_alias = o.symbol_alias
                 AND c.setup_type = o.setup_type
                 AND c.market_regime = o.market_regime
                 AND c.spread_regime = o.spread_regime
                 AND c.confidence_bucket = o.confidence_bucket
            ),
            ranked_outcomes AS (
                SELECT
                    lc.*,
                    CAST(lo.pnl AS DOUBLE) AS outcome_pnl,
                    ROW_NUMBER() OVER (
                        PARTITION BY lc.ts, lc.symbol_alias, lc.setup_type
                        ORDER BY CAST(lo.ts AS BIGINT)
                    ) AS outcome_rank
                FROM linked_candidates lc
                LEFT JOIN learning_observations_v2 lo
                  ON lo.symbol = lc.symbol_alias
                 AND lo.setup_type = lc.setup_type
                 AND lo.market_regime = lc.market_regime
                 AND lo.spread_regime = COALESCE(lc.spread_regime, lo.spread_regime)
                 AND lo.execution_regime = COALESCE(lc.execution_regime, lo.execution_regime)
                 AND lo.confidence_bucket = COALESCE(lc.confidence_bucket, lo.confidence_bucket)
                 AND CAST(lo.side AS BIGINT) = COALESCE(lc.side, CAST(lo.side AS BIGINT))
                 AND CAST(lo.renko_run_length AS BIGINT) = COALESCE(lc.renko_run_length, CAST(lo.renko_run_length AS BIGINT))
                 AND CAST(lo.renko_reversal_flag AS BIGINT) = COALESCE(lc.renko_reversal_flag, CAST(lo.renko_reversal_flag AS BIGINT))
                 AND CAST(lo.ts AS BIGINT) >= lc.ts
                 AND CAST(lo.ts AS BIGINT) <= lc.ts + {int(args.outcome_horizon_sec)}
            ),
            resolved AS (
                SELECT *
                FROM ranked_outcomes
                WHERE outcome_rank = 1 OR outcome_rank IS NULL
            )
            SELECT
                COUNT(*) AS liczba_obserwacji_onnx,
                SUM(CASE WHEN accepted IS NOT NULL THEN 1 ELSE 0 END) AS liczba_obserwacji_z_kandydatem,
                SUM(CASE WHEN outcome_pnl IS NOT NULL THEN 1 ELSE 0 END) AS liczba_obserwacji_z_wynikiem_rynku,
                COUNT(DISTINCT symbol_alias) AS liczba_symboli
            FROM resolved
        """
        summary_row = con.execute(summary_query).fetchone()

    summary = {
        "liczba_obserwacji_onnx": int(summary_row[0] or 0),
        "liczba_obserwacji_z_kandydatem": int(summary_row[1] or 0),
        "liczba_obserwacji_z_wynikiem_rynku": int(summary_row[2] or 0),
        "liczba_symboli": int(summary_row[3] or 0),
    }

    report = {
        "generated_at_local": pd.Timestamp.now(tz="Europe/Warsaw").strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": pd.Timestamp.now(tz="UTC").isoformat(),
        "db_path": str(db_path),
        "outcome_horizon_sec": int(args.outcome_horizon_sec),
        "score_threshold": float(args.score_threshold),
        "summary": summary,
        "powod_braku_danych": (None if summary["liczba_obserwacji_onnx"] > 0 else "brak_obserwacji_po_filtrowaniu"),
        "items": items_df.to_dict(orient="records"),
    }
    write_report(report, output_root)
    print(json.dumps(report, indent=2, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
