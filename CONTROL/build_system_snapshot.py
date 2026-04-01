from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set


DEFAULT_PROJECT_ROOT = Path(r"C:\MAKRO_I_MIKRO_BOT")
DEFAULT_COMMON_ROOT = Path(
    r"C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Builds unified control-state snapshot.")
    parser.add_argument("--project-root", default=str(DEFAULT_PROJECT_ROOT))
    parser.add_argument("--common-root", default=str(DEFAULT_COMMON_ROOT))
    return parser.parse_args()


def read_json(path: Path) -> Optional[Dict[str, Any]]:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception:
        return None


def file_probe(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {
            "present": False,
            "path": str(path),
            "last_write_local": None,
            "age_seconds": None,
            "size_bytes": 0,
        }
    stat = path.stat()
    age_seconds = int((datetime.now() - datetime.fromtimestamp(stat.st_mtime)).total_seconds())
    return {
        "present": True,
        "path": str(path),
        "last_write_local": datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S"),
        "age_seconds": age_seconds,
        "size_bytes": stat.st_size,
    }


def canonical_symbol(symbol: str) -> str:
    normalized = str(symbol or "").strip()
    if normalized.lower().endswith(".pro"):
        normalized = normalized[:-4]
    if normalized.upper() == "COPPERUS":
        normalized = "COPPER-US"
    return normalized


def symbol_aliases(symbol: str) -> List[str]:
    canonical = canonical_symbol(symbol)
    aliases: List[str] = []
    for candidate in (canonical, f"{canonical}.pro", symbol.strip()):
        if candidate and candidate not in aliases:
            aliases.append(candidate)
    return aliases


def pick_best_symbol_dir(root: Path, aliases: List[str], required_files: List[str]) -> Optional[Path]:
    best_dir: Optional[Path] = None
    best_score = -1

    for alias in aliases:
        candidate = root / alias
        if not candidate.exists() or not candidate.is_dir():
            continue
        score = 0
        for file_name in required_files:
            if (candidate / file_name).exists():
                score += 1
        if score > best_score:
            best_score = score
            best_dir = candidate

    return best_dir


def extract_symbols(
    common_root: Path,
    profile_report: Optional[Dict[str, Any]],
    chart_manifest: Optional[Dict[str, Any]],
    cohort_report: Optional[Dict[str, Any]],
) -> List[str]:
    symbols: Set[str] = set()

    state_root = common_root / "state"
    if state_root.exists():
        for child in state_root.iterdir():
            if child.is_dir() and not child.name.startswith("_"):
                symbols.add(canonical_symbol(child.name))

    for payload in (profile_report, chart_manifest):
        if not isinstance(payload, dict):
            continue
        for chart in payload.get("charts", []) or []:
            symbol = str(chart.get("symbol") or chart.get("broker_symbol") or "").strip()
            if symbol:
                symbols.add(canonical_symbol(symbol))

    if isinstance(cohort_report, dict):
        for item in cohort_report.get("items", []) or []:
            symbol = str(item.get("symbol_alias") or "").strip()
            if symbol:
                symbols.add(canonical_symbol(symbol))

    return sorted(symbols)


def build_cohort_index(cohort_report: Optional[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    index: Dict[str, Dict[str, Any]] = {}
    if not isinstance(cohort_report, dict):
        return index
    for item in cohort_report.get("items", []) or []:
        symbol = canonical_symbol(str(item.get("symbol_alias") or ""))
        if symbol:
            index[symbol] = item
    return index


def build_first_wave_index(first_wave_report: Optional[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    index: Dict[str, Dict[str, Any]] = {}
    if not isinstance(first_wave_report, dict):
        return index
    for item in first_wave_report.get("results", []) or []:
        symbol = canonical_symbol(str(item.get("symbol_alias") or ""))
        if symbol:
            index[symbol] = item
    return index


def load_symbol_state(
    common_root: Path,
    symbol: str,
    cohort_index: Dict[str, Dict[str, Any]],
    first_wave_index: Dict[str, Dict[str, Any]],
) -> Dict[str, Any]:
    aliases = symbol_aliases(symbol)
    state_dir = pick_best_symbol_dir(
        common_root / "state",
        aliases,
        [
            "learning_supervisor_snapshot_latest.json",
            "supervisor_snapshot_latest.json",
            "student_gate_latest.json",
            "ml_execution_snapshot_latest.json",
            "runtime_status.json",
        ],
    ) or (common_root / "state" / canonical_symbol(symbol))
    logs_dir = pick_best_symbol_dir(
        common_root / "logs",
        aliases,
        [
            "decision_events.csv",
            "onnx_observations.csv",
            "learning_observations_v2.csv",
            "broker_net_ledger_runtime.csv",
        ],
    ) or (common_root / "logs" / canonical_symbol(symbol))

    supervisor_snapshot_path = state_dir / "supervisor_snapshot_latest.json"
    learning_supervisor_snapshot_path = state_dir / "learning_supervisor_snapshot_latest.json"
    student_gate_path = state_dir / "student_gate_latest.json"
    execution_snapshot_path = state_dir / "ml_execution_snapshot_latest.json"
    learning_log_path = logs_dir / "learning_observations_v2.csv"
    knowledge_log_path = logs_dir / "broker_net_ledger_runtime.csv"
    onnx_log_path = logs_dir / "onnx_observations.csv"
    decision_log_path = logs_dir / "decision_events.csv"

    supervisor_snapshot = read_json(supervisor_snapshot_path)
    learning_supervisor_snapshot = read_json(learning_supervisor_snapshot_path)
    student_gate = read_json(student_gate_path)
    execution_snapshot = read_json(execution_snapshot_path)
    cohort_item = cohort_index.get(canonical_symbol(symbol)) or {}
    first_wave_item = first_wave_index.get(canonical_symbol(symbol)) or {}

    return {
        "symbol": canonical_symbol(symbol),
        "state_alias": state_dir.name if state_dir.exists() else canonical_symbol(symbol),
        "logs_alias": logs_dir.name if logs_dir.exists() else canonical_symbol(symbol),
        "supervisor_snapshot": supervisor_snapshot,
        "learning_supervisor_snapshot": learning_supervisor_snapshot,
        "global_teacher_audit": cohort_item,
        "first_wave_audit": first_wave_item,
        "student_gate": student_gate,
        "execution_snapshot": execution_snapshot,
        "files": {
            "supervisor_snapshot": file_probe(supervisor_snapshot_path),
            "learning_supervisor_snapshot": file_probe(learning_supervisor_snapshot_path),
            "student_gate": file_probe(student_gate_path),
            "execution_snapshot": file_probe(execution_snapshot_path),
            "learning_log": file_probe(learning_log_path),
            "knowledge_log": file_probe(knowledge_log_path),
            "onnx_log": file_probe(onnx_log_path),
            "decision_log": file_probe(decision_log_path),
        },
    }


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> int:
    args = parse_args()
    project_root = Path(args.project_root)
    common_root = Path(args.common_root)
    ops_root = project_root / "EVIDENCE" / "OPS"

    wellbeing_path = ops_root / "learning_wellbeing_latest.json"
    cohort_path = ops_root / "global_teacher_cohort_activity_latest.json"
    first_wave_path = ops_root / "first_wave_lesson_closure_latest.json"
    chart_manifest_path = ops_root / "chart_profile_manifest_latest.json"
    profile_report_path = project_root / "EVIDENCE" / "mt5_microbots_profile_setup_report.json"

    wellbeing = read_json(wellbeing_path)
    cohort = read_json(cohort_path)
    first_wave = read_json(first_wave_path)
    chart_manifest = read_json(chart_manifest_path)
    profile_report = read_json(profile_report_path)
    cohort_index = build_cohort_index(cohort)
    first_wave_index = build_first_wave_index(first_wave)

    symbols = extract_symbols(common_root, profile_report, chart_manifest, cohort)
    symbol_states = [load_symbol_state(common_root, symbol, cohort_index, first_wave_index) for symbol in symbols]

    payload = {
        "schema_version": "1.0",
        "generated_at_local": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "project_root": str(project_root),
        "common_root": str(common_root),
        "summary": {
            "symbol_count": len(symbol_states),
            "supervisor_snapshot_present_count": sum(
                1 for item in symbol_states if item["files"]["supervisor_snapshot"]["present"]
            ),
            "learning_supervisor_snapshot_present_count": sum(
                1 for item in symbol_states if item["files"]["learning_supervisor_snapshot"]["present"]
            ),
            "student_gate_present_count": sum(
                1 for item in symbol_states if item["files"]["student_gate"]["present"]
            ),
            "execution_snapshot_present_count": sum(
                1 for item in symbol_states if item["files"]["execution_snapshot"]["present"]
            ),
        },
        "sources": {
            "learning_wellbeing": {
                "path": str(wellbeing_path),
                "probe": file_probe(wellbeing_path),
                "payload": wellbeing,
            },
            "global_teacher_cohort_activity": {
                "path": str(cohort_path),
                "probe": file_probe(cohort_path),
                "payload": cohort,
            },
            "first_wave_lesson_closure": {
                "path": str(first_wave_path),
                "probe": file_probe(first_wave_path),
                "payload": first_wave,
            },
            "chart_profile_manifest": {
                "path": str(chart_manifest_path),
                "probe": file_probe(chart_manifest_path),
                "payload": chart_manifest,
            },
            "mt5_microbots_profile_setup_report": {
                "path": str(profile_report_path),
                "probe": file_probe(profile_report_path),
                "payload": profile_report,
            },
        },
        "symbols": symbol_states,
    }

    out_path = ops_root / "control_state_latest.json"
    write_json(out_path, payload)
    print(f"WROTE {out_path} symbols={len(symbol_states)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
