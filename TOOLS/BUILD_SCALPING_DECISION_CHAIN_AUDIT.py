from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

import duckdb

from mb_ml_core.paths import CompatPaths
from mb_ml_core.registry import load_paper_live_active_symbols, load_scalping_universe_plan, load_training_universe_symbols
from mb_ml_supervision.io_utils import dump_json, read_json, utc_now_iso
from mb_ml_supervision.paths import OverlayPaths


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Standalone audit lancucha decyzji scalpingu per symbol.")
    parser.add_argument("--project-root", default=r"C:\MAKRO_I_MIKRO_BOT")
    parser.add_argument("--research-root", default=r"C:\TRADING_DATA\RESEARCH")
    parser.add_argument("--common-state-root", default=None)
    parser.add_argument("--output-json", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\scalping_decision_chain_audit_latest.json")
    parser.add_argument("--output-md", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\scalping_decision_chain_audit_latest.md")
    return parser.parse_args()


def _load_items_by_symbol(path: Path) -> dict[str, dict[str, Any]]:
    payload = read_json(path, default={})
    if not isinstance(payload, dict):
        return {}
    items = payload.get("items", [])
    if not isinstance(items, list):
        return {}
    out: dict[str, dict[str, Any]] = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        symbol = str(item.get("symbol_alias") or item.get("symbol") or "").strip()
        if symbol:
            out[symbol] = item
    return out


def _query_exec_stage_counts(candidate_path: Path) -> dict[str, dict[str, int]]:
    if not candidate_path.exists():
        return {}
    con = duckdb.connect()
    try:
        rows = con.execute(
            """
            select
              cast(symbol_alias as varchar) as symbol_alias,
              upper(trim(cast(stage as varchar))) as stage_name,
              count(*) as rows_total
            from read_parquet(?)
            where upper(trim(cast(stage as varchar))) in ('EXEC_SEND_OK', 'EXEC_SEND_ERROR', 'PAPER_OPEN', 'PRECHECK_BLOCK')
            group by 1, 2
            order by 1, 2
            """,
            [str(candidate_path)],
        ).fetchall()
    finally:
        con.close()
    out: dict[str, dict[str, int]] = {}
    for symbol_alias, stage_name, rows_total in rows:
        symbol = str(symbol_alias).strip()
        out.setdefault(symbol, {})[str(stage_name)] = int(rows_total)
    return out


def _query_net_rows(ledger_path: Path) -> dict[str, dict[str, int]]:
    if not ledger_path.exists():
        return {}
    con = duckdb.connect()
    try:
        rows = con.execute(
            """
            select
              cast(symbol_alias as varchar) as symbol_alias,
              count(*) as outcome_rows,
              coalesce(sum(case when net_pln > 0 then 1 else 0 end), 0) as net_positive_rows,
              coalesce(sum(case when net_pln < 0 then 1 else 0 end), 0) as net_negative_rows
            from read_parquet(?)
            where outcome_known = 1
            group by 1
            order by 1
            """,
            [str(ledger_path)],
        ).fetchall()
    finally:
        con.close()
    out: dict[str, dict[str, int]] = {}
    for symbol_alias, outcome_rows, positive_rows, negative_rows in rows:
        out[str(symbol_alias).strip()] = {
            "outcome_rows": int(outcome_rows),
            "net_positive_rows": int(positive_rows),
            "net_negative_rows": int(negative_rows),
        }
    return out


def _resolve_chain_break(
    *,
    paper_live_enabled: bool,
    candidate_rows_final: int,
    precheck_blocked_rows: int,
    paper_open_rows: int,
    execution_send_ok_rows: int,
    execution_send_error_rows: int,
    outcome_rows: int,
    net_positive_rows: int,
    net_negative_rows: int,
    gap_reason_code: str,
) -> tuple[str, str]:
    if not paper_live_enabled:
        return "PAPER_LIVE_DISABLED", "PAPER_LIVE_DISABLED"
    if candidate_rows_final <= 0:
        return gap_reason_code or "ECONOMICS_BLOCK_DOMINANT", "CANDIDATE"
    if paper_open_rows <= 0 and precheck_blocked_rows > 0:
        return "PRECHECK_BLOCK_DOMINANT", "PRECHECK"
    if execution_send_ok_rows <= 0 and execution_send_error_rows > 0:
        return "EXECUTION_BLOCK_DOMINANT", "EXECUTION"
    if outcome_rows <= 0:
        return "OUTCOME_GAP_DOMINANT", "OUTCOME"
    if net_negative_rows >= net_positive_rows:
        return "NEGATIVE_NET_OUTCOME_DOMINANT", "NET"
    return "CHAIN_OK", "NONE"


def main() -> int:
    args = parse_args()
    paths = OverlayPaths.create(
        project_root=args.project_root,
        research_root=args.research_root,
        common_state_root=args.common_state_root,
    )
    compat_paths = CompatPaths.create(
        project_root=args.project_root,
        research_root=args.research_root,
        common_state_root=paths.runtime_root,
    )

    universe_plan = load_scalping_universe_plan(compat_paths)
    training_universe = load_training_universe_symbols(compat_paths)
    paper_live_universe = set(load_paper_live_active_symbols(compat_paths))
    candidate_gap_rows = _load_items_by_symbol(paths.candidate_gap_audit_path)
    exec_stage_rows = _query_exec_stage_counts(paths.candidate_contract_path)
    ledger_rows = _query_net_rows(paths.broker_net_ledger_path)

    items: list[dict[str, Any]] = []
    reason_counts: dict[str, int] = {}
    for symbol in training_universe:
        gap_row = candidate_gap_rows.get(symbol, {})
        stage_row = exec_stage_rows.get(symbol, {})
        ledger_row = ledger_rows.get(symbol, {})
        paper_live_enabled = symbol in paper_live_universe
        candidate_rows_raw = int(gap_row.get("raw_qdm_rows", 0) or 0)
        candidate_rows_final = int(gap_row.get("candidate_rows", 0) or 0)
        precheck_blocked_rows = int(gap_row.get("precheck_block_rows", 0) or 0)
        paper_open_rows = int(gap_row.get("paper_open_rows", 0) or 0)
        execution_send_ok_rows = int(stage_row.get("EXEC_SEND_OK", 0) or 0)
        execution_send_error_rows = int(stage_row.get("EXEC_SEND_ERROR", 0) or 0)
        outcome_rows = int(ledger_row.get("outcome_rows", 0) or 0)
        net_positive_rows = int(ledger_row.get("net_positive_rows", 0) or 0)
        net_negative_rows = int(ledger_row.get("net_negative_rows", 0) or 0)
        dominant_chain_break_reason, advantage_lost_stage = _resolve_chain_break(
            paper_live_enabled=paper_live_enabled,
            candidate_rows_final=candidate_rows_final,
            precheck_blocked_rows=precheck_blocked_rows,
            paper_open_rows=paper_open_rows,
            execution_send_ok_rows=execution_send_ok_rows,
            execution_send_error_rows=execution_send_error_rows,
            outcome_rows=outcome_rows,
            net_positive_rows=net_positive_rows,
            net_negative_rows=net_negative_rows,
            gap_reason_code=str(gap_row.get("gap_reason_code") or ""),
        )
        reason_counts[dominant_chain_break_reason] = reason_counts.get(dominant_chain_break_reason, 0) + 1
        items.append(
            {
                "symbol_alias": symbol,
                "paper_live_enabled": paper_live_enabled,
                "paper_live_bucket": (
                    "FIRST_WAVE" if symbol in paper_live_universe else (
                        "SECOND_WAVE" if symbol in set(universe_plan["paper_live_second_wave"]) else (
                            "HOLD" if symbol in set(universe_plan["paper_live_hold"]) else "GLOBAL_TEACHER_ONLY"
                        )
                    )
                ),
                "candidate_rows_raw": candidate_rows_raw,
                "candidate_rows_final": candidate_rows_final,
                "precheck_blocked_rows": precheck_blocked_rows,
                "paper_open_rows": paper_open_rows,
                "execution_send_ok_rows": execution_send_ok_rows,
                "execution_send_error_rows": execution_send_error_rows,
                "outcome_rows": outcome_rows,
                "net_positive_rows": net_positive_rows,
                "net_negative_rows": net_negative_rows,
                "dominant_chain_break_reason": dominant_chain_break_reason,
                "advantage_lost_stage": advantage_lost_stage,
                "gap_reason_code": str(gap_row.get("gap_reason_code") or ""),
                "dominant_block_reason_code": str(gap_row.get("dominant_block_reason_code") or ""),
            }
        )

    payload = {
        "schema_version": "1.0",
        "generated_at_utc": utc_now_iso(),
        "universe_version": str(universe_plan["universe_version"]),
        "plan_hash": str(universe_plan["plan_hash"]),
        "summary": {
            "total_symbols": len(items),
            "paper_live_enabled_count": sum(1 for item in items if item["paper_live_enabled"]),
            "symbols_with_candidate_rows_final": sum(1 for item in items if item["candidate_rows_final"] > 0),
            "symbols_with_execution_send_ok": sum(1 for item in items if item["execution_send_ok_rows"] > 0),
            "symbols_with_outcome_rows": sum(1 for item in items if item["outcome_rows"] > 0),
            "reason_counts": reason_counts,
        },
        "items": items,
    }

    output_json = Path(args.output_json)
    output_md = Path(args.output_md)
    dump_json(output_json, payload)

    lines = [
        "# Scalping Decision Chain Audit",
        "",
        f"- generated_at_utc: {payload['generated_at_utc']}",
        f"- universe_version: {payload['universe_version']}",
        "",
    ]
    for item in items:
        lines.append(f"## {item['symbol_alias']}")
        lines.append(f"- paper_live_enabled: {item['paper_live_enabled']}")
        lines.append(f"- candidate_rows_raw/final: {item['candidate_rows_raw']} / {item['candidate_rows_final']}")
        lines.append(f"- precheck_blocked_rows: {item['precheck_blocked_rows']}")
        lines.append(f"- paper_open_rows: {item['paper_open_rows']}")
        lines.append(f"- execution_send_ok_rows: {item['execution_send_ok_rows']}")
        lines.append(f"- outcome_rows: {item['outcome_rows']}")
        lines.append(f"- net_positive_rows/net_negative_rows: {item['net_positive_rows']} / {item['net_negative_rows']}")
        lines.append(f"- dominant_chain_break_reason: {item['dominant_chain_break_reason']}")
        lines.append(f"- advantage_lost_stage: {item['advantage_lost_stage']}")
        lines.append("")
    output_md.parent.mkdir(parents=True, exist_ok=True)
    output_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(output_json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
