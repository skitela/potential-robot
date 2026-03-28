from __future__ import annotations

import argparse
import json
import re
from datetime import UTC, datetime
from pathlib import Path

import duckdb


PROFILE_START_RE = re.compile(r"out\.trade_window_start_hour\s*=\s*([0-9]+)\s*;")
PROFILE_END_RE = re.compile(r"out\.trade_window_end_hour\s*=\s*([0-9]+)\s*;")
PROFILE_SPREAD_RE = re.compile(r"out\.max_spread_points\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*;")


def read_json(path: Path):
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8-sig"))


def parse_profile_settings(profile_path: Path) -> dict[str, float | int] | None:
    if not profile_path.exists():
        return None
    text = profile_path.read_text(encoding="utf-8", errors="ignore")
    start_m = PROFILE_START_RE.search(text)
    end_m = PROFILE_END_RE.search(text)
    spread_m = PROFILE_SPREAD_RE.search(text)
    if not start_m or not end_m or not spread_m:
        return None
    return {
        "trade_window_start_hour": int(start_m.group(1)),
        "trade_window_end_hour": int(end_m.group(1)),
        "max_spread_points": float(spread_m.group(1)),
    }


def sql_quote(path: Path) -> str:
    return path.as_posix().replace("'", "''")


def detect_profile_path(project_root: Path, code_symbol: str) -> Path:
    return project_root / "MQL5" / "Include" / "Profiles" / f"Profile_{code_symbol}.mqh"


def get_top_reason(
    con: duckdb.DuckDBPyConnection,
    candidate_path: Path,
    symbol_alias: str,
    stage: str,
) -> str:
    row = con.execute(
        f"""
        select coalesce(nullif(trim(reason_code), ''), 'UNKNOWN') as reason_code, count(*) as rows_total
        from read_parquet('{sql_quote(candidate_path)}')
        where upper(trim(symbol_alias)) = ?
          and upper(trim(stage)) = ?
        group by 1
        order by 2 desc, 1 asc
        limit 1
        """,
        [symbol_alias.upper(), stage.upper()],
    ).fetchone()
    return str(row[0]) if row else ""


def query_qdm_stage_counts(
    con: duckdb.DuckDBPyConnection,
    qdm_path: Path,
    symbol_alias: str,
    window_start: int,
    window_end: int,
    max_spread_points: float,
) -> dict[str, int]:
    if not qdm_path.exists():
        return {
            "raw_qdm_rows": 0,
            "post_session_rows": 0,
            "post_spread_rows": 0,
            "post_latency_rows": 0,
        }

    row = con.execute(
        f"""
        with scoped as (
            select
                upper(trim(symbol_alias)) as symbol_alias,
                bar_minute,
                coalesce(spread_mean, spread_max, 0.0) as spread_points
            from read_parquet('{sql_quote(qdm_path)}')
            where upper(trim(symbol_alias)) = ?
        ),
        staged as (
            select
                count(*) as raw_qdm_rows,
                sum(
                    case
                        when extract(hour from bar_minute) between ? and ?
                        then 1 else 0
                    end
                ) as post_session_rows,
                sum(
                    case
                        when extract(hour from bar_minute) between ? and ?
                         and spread_points <= ?
                        then 1 else 0
                    end
                ) as post_spread_rows
            from scoped
        )
        select
            coalesce(raw_qdm_rows, 0),
            coalesce(post_session_rows, 0),
            coalesce(post_spread_rows, 0)
        from staged
        """,
        [
            symbol_alias.upper(),
            window_start,
            window_end,
            window_start,
            window_end,
            max_spread_points,
        ],
    ).fetchone()

    raw_qdm_rows = int(row[0]) if row else 0
    post_session_rows = int(row[1]) if row else 0
    post_spread_rows = int(row[2]) if row else 0
    return {
        "raw_qdm_rows": raw_qdm_rows,
        "post_session_rows": post_session_rows,
        # Historical latency is not stored per bar in QDM, so we carry the post-spread set forward
        # and mark this audit stage as a runtime-deferred estimate.
        "post_spread_rows": post_spread_rows,
        "post_latency_rows": post_spread_rows,
    }


def query_candidate_stage_counts(
    con: duckdb.DuckDBPyConnection,
    candidate_path: Path,
    symbol_alias: str,
) -> dict[str, int]:
    if not candidate_path.exists():
        return {
            "evaluated_rows": 0,
            "size_block_rows": 0,
            "precheck_block_rows": 0,
            "arbitration_block_rows": 0,
            "paper_open_rows": 0,
        }

    rows = con.execute(
        f"""
        select upper(trim(stage)) as stage_name, count(*) as rows_total
        from read_parquet('{sql_quote(candidate_path)}')
        where upper(trim(symbol_alias)) = ?
        group by 1
        """,
        [symbol_alias.upper()],
    ).fetchall()
    counts = {str(stage): int(total) for stage, total in rows}
    return {
        "evaluated_rows": int(counts.get("EVALUATED", 0)),
        "size_block_rows": int(counts.get("SIZE_BLOCK", 0)),
        "precheck_block_rows": int(counts.get("PRECHECK_BLOCK", 0)),
        "arbitration_block_rows": int(counts.get("ARBITRATION_BLOCK", 0)),
        "paper_open_rows": int(counts.get("PAPER_OPEN", 0)),
    }


def resolve_first_zero_stage(stages: list[tuple[str, int]]) -> str:
    for name, value in stages:
        if value <= 0:
            return name
    return "NONE"


def resolve_gap_reason(
    raw_qdm_rows: int,
    post_session_rows: int,
    post_spread_rows: int,
    post_latency_rows: int,
    post_strategy_rows: int,
    post_risk_rows: int,
    candidate_rows: int,
    precheck_block_rows: int,
    arbitration_block_rows: int,
    size_block_rows: int,
) -> str:
    if raw_qdm_rows <= 0:
        return "NO_QDM_ROWS"
    if post_session_rows <= 0:
        return "SESSION_WINDOW_ZERO"
    if post_spread_rows <= 0:
        return "SPREAD_FILTER_ZERO"
    if post_latency_rows <= 0:
        return "LATENCY_STAGE_ZERO"
    if post_strategy_rows <= 0:
        return "STRATEGY_NO_SIGNAL"
    if post_risk_rows <= 0:
        return "RISK_SIZE_ZERO"
    if candidate_rows <= 0:
        if precheck_block_rows >= arbitration_block_rows and precheck_block_rows >= size_block_rows and precheck_block_rows > 0:
            return "EXECUTION_PRECHECK_BLOCK_DOMINANT"
        if arbitration_block_rows >= size_block_rows and arbitration_block_rows > 0:
            return "ARBITRATION_BLOCK_DOMINANT"
        if size_block_rows > 0:
            return "SIZE_BLOCK_DOMINANT"
        return "FINAL_CANDIDATE_ZERO"
    return "HAS_FINAL_CANDIDATES"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=r"C:\MAKRO_I_MIKRO_BOT")
    parser.add_argument("--research-root", default=r"C:\TRADING_DATA\RESEARCH")
    parser.add_argument("--output-json", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\candidate_gap_audit_latest.json")
    parser.add_argument("--output-md", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\candidate_gap_audit_latest.md")
    args = parser.parse_args()

    project_root = Path(args.project_root)
    research_root = Path(args.research_root)
    registry_path = project_root / "CONFIG" / "microbots_registry.json"
    qdm_path = research_root / "datasets" / "qdm_minute_bars_latest.parquet"
    candidate_path = research_root / "datasets" / "contracts" / "candidate_signals_norm_latest.parquet"

    registry = read_json(registry_path)
    if not registry:
        raise SystemExit(f"Registry missing or invalid: {registry_path}")

    con = duckdb.connect()
    items: list[dict] = []

    for symbol_entry in registry.get("symbols", []):
        symbol_alias = str(symbol_entry.get("symbol", "")).strip().upper()
        if not symbol_alias:
            continue

        code_symbol = str(symbol_entry.get("code_symbol", symbol_alias.replace("-", ""))).strip()
        profile_path = detect_profile_path(project_root, code_symbol)
        profile = parse_profile_settings(profile_path)
        if profile is None:
            profile = {
                "trade_window_start_hour": 0,
                "trade_window_end_hour": 23,
                "max_spread_points": 999999.0,
            }

        qdm_counts = query_qdm_stage_counts(
            con,
            qdm_path,
            symbol_alias,
            int(profile["trade_window_start_hour"]),
            int(profile["trade_window_end_hour"]),
            float(profile["max_spread_points"]),
        )
        candidate_counts = query_candidate_stage_counts(con, candidate_path, symbol_alias)

        post_strategy_rows = int(candidate_counts["evaluated_rows"])
        post_risk_rows = max(0, post_strategy_rows - int(candidate_counts["size_block_rows"]))
        candidate_rows = int(candidate_counts["paper_open_rows"])

        first_zero_stage = resolve_first_zero_stage(
            [
                ("raw_qdm_rows", int(qdm_counts["raw_qdm_rows"])),
                ("post_session_rows", int(qdm_counts["post_session_rows"])),
                ("post_spread_rows", int(qdm_counts["post_spread_rows"])),
                ("post_latency_rows", int(qdm_counts["post_latency_rows"])),
                ("post_strategy_rows", post_strategy_rows),
                ("post_risk_rows", post_risk_rows),
                ("candidate_rows", candidate_rows),
            ]
        )
        gap_reason_code = resolve_gap_reason(
            raw_qdm_rows=int(qdm_counts["raw_qdm_rows"]),
            post_session_rows=int(qdm_counts["post_session_rows"]),
            post_spread_rows=int(qdm_counts["post_spread_rows"]),
            post_latency_rows=int(qdm_counts["post_latency_rows"]),
            post_strategy_rows=post_strategy_rows,
            post_risk_rows=post_risk_rows,
            candidate_rows=candidate_rows,
            precheck_block_rows=int(candidate_counts["precheck_block_rows"]),
            arbitration_block_rows=int(candidate_counts["arbitration_block_rows"]),
            size_block_rows=int(candidate_counts["size_block_rows"]),
        )

        dominant_stage_pairs = [
            ("PRECHECK_BLOCK", int(candidate_counts["precheck_block_rows"])),
            ("ARBITRATION_BLOCK", int(candidate_counts["arbitration_block_rows"])),
            ("SIZE_BLOCK", int(candidate_counts["size_block_rows"])),
        ]
        dominant_block_stage, dominant_block_rows = max(dominant_stage_pairs, key=lambda pair: pair[1])
        dominant_block_reason_code = (
            get_top_reason(con, candidate_path, symbol_alias, dominant_block_stage) if dominant_block_rows > 0 else ""
        )

        items.append(
            {
                "symbol_alias": symbol_alias,
                "broker_symbol": symbol_entry.get("broker_symbol", ""),
                "session_profile": symbol_entry.get("session_profile", ""),
                "expert": symbol_entry.get("expert", ""),
                "profile_path": str(profile_path),
                "trade_window_start_hour": int(profile["trade_window_start_hour"]),
                "trade_window_end_hour": int(profile["trade_window_end_hour"]),
                "max_spread_points": float(profile["max_spread_points"]),
                "latency_stage_mode": "DEFERRED_TO_RUNTIME",
                "raw_qdm_rows": int(qdm_counts["raw_qdm_rows"]),
                "post_session_rows": int(qdm_counts["post_session_rows"]),
                "post_spread_rows": int(qdm_counts["post_spread_rows"]),
                "post_latency_rows": int(qdm_counts["post_latency_rows"]),
                "post_strategy_rows": post_strategy_rows,
                "post_risk_rows": post_risk_rows,
                "candidate_rows": candidate_rows,
                "evaluated_rows": int(candidate_counts["evaluated_rows"]),
                "size_block_rows": int(candidate_counts["size_block_rows"]),
                "precheck_block_rows": int(candidate_counts["precheck_block_rows"]),
                "arbitration_block_rows": int(candidate_counts["arbitration_block_rows"]),
                "paper_open_rows": int(candidate_counts["paper_open_rows"]),
                "first_zero_stage": first_zero_stage,
                "gap_reason_code": gap_reason_code,
                "dominant_block_stage": dominant_block_stage if dominant_block_rows > 0 else "NONE",
                "dominant_block_rows": dominant_block_rows,
                "dominant_block_reason_code": dominant_block_reason_code,
            }
        )

    con.close()

    items.sort(key=lambda row: (row["first_zero_stage"], row["symbol_alias"]))
    stage_zero_counts: dict[str, int] = {}
    reason_counts: dict[str, int] = {}
    for item in items:
        stage_zero_counts[item["first_zero_stage"]] = stage_zero_counts.get(item["first_zero_stage"], 0) + 1
        reason_counts[item["gap_reason_code"]] = reason_counts.get(item["gap_reason_code"], 0) + 1

    summary = {
        "total_symbols": len(items),
        "symbols_with_final_candidates_count": sum(1 for item in items if item["candidate_rows"] > 0),
        "final_zero_count": sum(1 for item in items if item["candidate_rows"] <= 0),
        "strategy_zero_count": sum(1 for item in items if item["post_strategy_rows"] <= 0),
        "risk_zero_count": sum(1 for item in items if item["post_risk_rows"] <= 0),
        "session_zero_count": sum(1 for item in items if item["post_session_rows"] <= 0),
        "spread_zero_count": sum(1 for item in items if item["post_spread_rows"] <= 0),
        "first_zero_stage_counts": stage_zero_counts,
        "gap_reason_counts": reason_counts,
    }

    report = {
        "schema_version": "1.0",
        "generated_at_local": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        "summary": summary,
        "top_final_zero": [item for item in items if item["candidate_rows"] <= 0][:8],
        "top_strategy_zero": [item for item in items if item["post_strategy_rows"] <= 0][:8],
        "items": items,
    }

    output_json = Path(args.output_json)
    output_md = Path(args.output_md)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "# Candidate Gap Audit",
        "",
        f"- generated_at_local: {report['generated_at_local']}",
        f"- total_symbols: {summary['total_symbols']}",
        f"- symbols_with_final_candidates_count: {summary['symbols_with_final_candidates_count']}",
        f"- final_zero_count: {summary['final_zero_count']}",
        f"- strategy_zero_count: {summary['strategy_zero_count']}",
        f"- risk_zero_count: {summary['risk_zero_count']}",
        f"- session_zero_count: {summary['session_zero_count']}",
        f"- spread_zero_count: {summary['spread_zero_count']}",
        "",
        "## Final Zero",
        "",
    ]

    if report["top_final_zero"]:
        for item in report["top_final_zero"]:
            lines.append(
                f"- {item['symbol_alias']}: first_zero_stage={item['first_zero_stage']}, "
                f"gap_reason={item['gap_reason_code']}, dominant_block_stage={item['dominant_block_stage']}, "
                f"dominant_block_reason={item['dominant_block_reason_code'] or 'NONE'}"
            )
    else:
        lines.append("- none")

    lines.extend(["", "## Strategy Zero", ""])
    if report["top_strategy_zero"]:
        for item in report["top_strategy_zero"]:
            lines.append(
                f"- {item['symbol_alias']}: session={item['post_session_rows']}, spread={item['post_spread_rows']}, "
                f"strategy={item['post_strategy_rows']}, reason={item['gap_reason_code']}"
            )
    else:
        lines.append("- none")

    output_md.write_text("\r\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
