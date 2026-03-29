from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from mb_ml_core.io_utils import ensure_dir, write_json
from mb_ml_core.paths import CompatPaths
from mb_ml_core.registry import load_training_universe_symbols


def _count_csv_rows(path: Path) -> int:
    if not path.exists() or not path.is_file():
        return 0
    try:
        with path.open("r", encoding="utf-8", errors="ignore") as handle:
            return max(sum(1 for _ in handle) - 1, 0)
    except Exception:
        return 0


def _collect_spool_state(folder: Path) -> dict[str, Any]:
    files = sorted(folder.glob("*.csv")) if folder.exists() else []
    rows = {path.name: _count_csv_rows(path) for path in files}
    total_rows = sum(rows.values())
    latest_file = max(files, key=lambda item: item.stat().st_mtime, default=None)
    return {
        "path": str(folder),
        "exists": folder.exists(),
        "csv_count": len(files),
        "total_rows": total_rows,
        "latest_file": str(latest_file) if latest_file else "",
        "latest_file_name": latest_file.name if latest_file else "",
        "latest_file_modified": latest_file.stat().st_mtime if latest_file else None,
        "files": [{"name": path.name, "rows": rows[path.name]} for path in files],
    }


def _read_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="ignore")


def _inspect_hooks(project_root: Path, active_symbols: list[str]) -> dict[str, Any]:
    microbots_dir = project_root / "MQL5" / "Experts" / "MicroBots"
    include_pretrade = 0
    include_execution = 0
    call_pretrade = 0
    call_execution = 0
    items: list[dict[str, Any]] = []

    for symbol in active_symbols:
        expert_name = f"MicroBot_{symbol.replace('-', '').replace('_', '')}"
        path_candidates = [
            microbots_dir / f"{expert_name}.mq5",
            microbots_dir / f"MicroBot_{symbol}.mq5",
        ]
        file_path = next((candidate for candidate in path_candidates if candidate.exists()), path_candidates[-1])
        source = _read_text(file_path)
        has_pretrade_include = "MbPreTradeTruth.mqh" in source
        has_execution_include = "MbExecutionTruthFeed.mqh" in source
        has_pretrade_call = "MbPreTradeTruthEvaluateAndWrite(" in source
        has_execution_call = "MbExecutionTruthCapture(" in source

        include_pretrade += int(has_pretrade_include)
        include_execution += int(has_execution_include)
        call_pretrade += int(has_pretrade_call)
        call_execution += int(has_execution_call)

        items.append(
            {
                "symbol_alias": symbol,
                "file_path": str(file_path),
                "pretrade_include": has_pretrade_include,
                "execution_include": has_execution_include,
                "pretrade_call": has_pretrade_call,
                "execution_call": has_execution_call,
            }
        )

    return {
        "summary": {
            "active_symbols_count": len(active_symbols),
            "pretrade_include_count": include_pretrade,
            "execution_include_count": include_execution,
            "pretrade_call_count": call_pretrade,
            "execution_call_count": call_execution,
        },
        "items": items,
    }


def _read_truth_summary(paths: CompatPaths) -> dict[str, Any]:
    summary_path = paths.contracts_dir / "mt5_truth" / "mt5_execution_truth_summary_latest.json"
    if not summary_path.exists():
        return {
            "path": str(summary_path),
            "exists": False,
        }
    try:
        payload = json.loads(summary_path.read_text(encoding="utf-8"))
    except Exception:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    payload["path"] = str(summary_path)
    payload["exists"] = True
    return payload


def _resolve_operational_state(hooks: dict[str, Any], pretrade: dict[str, Any], execution: dict[str, Any], truth_summary: dict[str, Any]) -> str:
    hook_summary = hooks.get("summary", {}) if isinstance(hooks, dict) else {}
    active_symbols_count = int(hook_summary.get("active_symbols_count", 0) or 0)
    fully_implanted = (
        int(hook_summary.get("pretrade_include_count", 0) or 0) == active_symbols_count
        and int(hook_summary.get("execution_include_count", 0) or 0) == active_symbols_count
        and int(hook_summary.get("pretrade_call_count", 0) or 0) == active_symbols_count
        and int(hook_summary.get("execution_call_count", 0) or 0) == active_symbols_count
    )

    pretrade_rows = int(pretrade.get("total_rows", 0) or 0)
    execution_rows = int(execution.get("total_rows", 0) or 0)
    merged_rows = int(truth_summary.get("merged_rows", 0) or 0)
    truth_chain_rows = int(truth_summary.get("truth_chain_rows", 0) or 0)

    if fully_implanted and pretrade_rows == 0 and execution_rows == 0:
        return "IMPLANTED_BUT_DORMANT"
    if fully_implanted and (pretrade_rows > 0 or execution_rows > 0) and merged_rows <= 0:
        return "SPOOL_LIVE_CONTRACT_BUILD_PENDING"
    if fully_implanted and merged_rows > 0 and truth_chain_rows <= 0:
        return "OPERATIONAL_BASE_CONTRACT_ONLY"
    if fully_implanted and truth_chain_rows > 0:
        return "OPERATIONAL_WITH_CONTRACT_CHAIN"
    return "PARTIAL_IMPLANT"


def build(project_root: Path, research_root: Path, common_state_root: Path | None) -> dict[str, Any]:
    compat = CompatPaths.create(
        project_root=project_root,
        research_root=research_root,
        common_state_root=common_state_root,
    )
    active_symbols = load_training_universe_symbols(compat)
    spool_root = compat.common_state_root / "spool"
    pretrade_spool = _collect_spool_state(spool_root / "pretrade_truth")
    execution_spool = _collect_spool_state(spool_root / "execution_truth")
    hook_state = _inspect_hooks(project_root, active_symbols)
    truth_summary = _read_truth_summary(compat)
    operational_state = _resolve_operational_state(hook_state, pretrade_spool, execution_spool, truth_summary)

    notes: list[str] = []
    if operational_state == "IMPLANTED_BUT_DORMANT":
        notes.append("Hooki sa wpiete, ale spool pretrade/execution nie produkuje jeszcze zadnych rekordow.")
    if operational_state == "OPERATIONAL_BASE_CONTRACT_ONLY":
        notes.append("Bazowy kontrakt execution + pretrade dziala, ale contract chain do kandydatow i learningu nie ma jeszcze zywych wierszy.")
    if operational_state == "OPERATIONAL_WITH_CONTRACT_CHAIN":
        notes.append("Contract chain execution -> candidate -> learning jest juz zywy w artefaktach truth.")
    if not pretrade_spool["exists"]:
        notes.append("Brakuje katalogu spool/pretrade_truth.")
    if not execution_spool["exists"]:
        notes.append("Brakuje katalogu spool/execution_truth.")
    if truth_summary.get("exists") and int(truth_summary.get("merged_rows", 0) or 0) <= 0:
        notes.append("Kontrakty truth istnieja, ale nie maja jeszcze polaczonego materialu execution + pretrade.")
    if truth_summary.get("exists") and int(truth_summary.get("truth_chain_rows", 0) or 0) <= 0:
        notes.append("Contract chain do kandydatow, ONNX i learningu nie ma jeszcze zywych wierszy.")
    if not truth_summary.get("exists"):
        notes.append("Builder truth nie wygenerowal jeszcze podsumowania mt5_execution_truth_summary_latest.json.")

    payload = {
        "schema_version": "1.0",
        "generated_at_utc": __import__("datetime").datetime.now(__import__("datetime").UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "project_root": str(project_root),
        "research_root": str(research_root),
        "common_state_root": str(compat.common_state_root),
        "operational_state": operational_state,
        "active_symbols": active_symbols,
        "hooks": hook_state,
        "pretrade_spool": pretrade_spool,
        "execution_spool": execution_spool,
        "truth_summary": truth_summary,
        "notes": notes,
    }
    return payload


def write_reports(payload: dict[str, Any], project_root: Path) -> dict[str, str]:
    output_root = project_root / "EVIDENCE" / "OPS"
    ensure_dir(output_root)
    json_path = output_root / "mt5_pretrade_execution_truth_status_latest.json"
    md_path = output_root / "mt5_pretrade_execution_truth_status_latest.md"
    write_json(json_path, payload)

    hook_summary = payload["hooks"]["summary"]
    pretrade = payload["pretrade_spool"]
    execution = payload["execution_spool"]
    truth_summary = payload["truth_summary"]

    lines = [
        "# MT5 Pretrade Execution Truth Status",
        "",
        f"- generated_at_utc: {payload['generated_at_utc']}",
        f"- operational_state: {payload['operational_state']}",
        f"- active_symbols_count: {hook_summary['active_symbols_count']}",
        f"- pretrade_include_count: {hook_summary['pretrade_include_count']}",
        f"- execution_include_count: {hook_summary['execution_include_count']}",
        f"- pretrade_call_count: {hook_summary['pretrade_call_count']}",
        f"- execution_call_count: {hook_summary['execution_call_count']}",
        f"- pretrade_csv_count: {pretrade['csv_count']}",
        f"- pretrade_total_rows: {pretrade['total_rows']}",
        f"- execution_csv_count: {execution['csv_count']}",
        f"- execution_total_rows: {execution['total_rows']}",
        f"- truth_summary_exists: {truth_summary.get('exists', False)}",
        f"- merged_rows: {truth_summary.get('merged_rows', 0)}",
        f"- truth_chain_rows: {truth_summary.get('truth_chain_rows', 0)}",
        f"- candidate_contract_matched_rows: {truth_summary.get('candidate_contract_matched_rows', 0)}",
        f"- onnx_contract_matched_rows: {truth_summary.get('onnx_contract_matched_rows', 0)}",
        f"- learning_contract_matched_rows: {truth_summary.get('learning_contract_matched_rows', 0)}",
        "",
        "## Notes",
        "",
    ]
    if payload["notes"]:
        lines.extend(f"- {note}" for note in payload["notes"])
    else:
        lines.append("- none")
    lines.extend(["", "## Hook Coverage", ""])
    for item in payload["hooks"]["items"]:
        lines.append(
            "- {symbol_alias}: pretrade_include={pretrade_include}, execution_include={execution_include}, pretrade_call={pretrade_call}, execution_call={execution_call}".format(
                **item
            )
        )

    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return {"json": str(json_path), "md": str(md_path)}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Builds operational status for MT5 pre-trade / execution truth implant.")
    parser.add_argument("--project-root", type=Path, default=Path(r"C:\MAKRO_I_MIKRO_BOT"))
    parser.add_argument("--research-root", type=Path, default=Path(r"C:\TRADING_DATA\RESEARCH"))
    parser.add_argument("--common-state-root", type=Path, default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    payload = build(
        project_root=args.project_root,
        research_root=args.research_root,
        common_state_root=args.common_state_root,
    )
    reports = write_reports(payload, args.project_root)
    payload["reports"] = reports
    print(json.dumps(payload, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
