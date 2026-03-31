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
                symbols.add(child.name)

    for payload in (profile_report, chart_manifest):
        if not isinstance(payload, dict):
            continue
        for chart in payload.get("charts", []) or []:
            symbol = str(chart.get("symbol") or chart.get("broker_symbol") or "").strip()
            if symbol:
                symbols.add(symbol)

    if isinstance(cohort_report, dict):
        for item in cohort_report.get("items", []) or []:
            symbol = str(item.get("symbol_alias") or "").strip()
            if symbol:
                symbols.add(symbol)

    return sorted(symbols)


def load_symbol_state(common_root: Path, symbol: str) -> Dict[str, Any]:
    state_dir = common_root / "state" / symbol
    logs_dir = common_root / "logs" / symbol

    supervisor_snapshot_path = state_dir / "supervisor_snapshot_latest.json"
    student_gate_path = state_dir / "student_gate_latest.json"
    execution_snapshot_path = state_dir / "ml_execution_snapshot_latest.json"
    learning_log_path = logs_dir / "learning_observations_v2.csv"
    knowledge_log_path = logs_dir / "broker_net_ledger_runtime.csv"
    onnx_log_path = logs_dir / "onnx_observations.csv"
    decision_log_path = logs_dir / "decision_events.csv"

    supervisor_snapshot = read_json(supervisor_snapshot_path)
    student_gate = read_json(student_gate_path)
    execution_snapshot = read_json(execution_snapshot_path)

    return {
        "symbol": symbol,
        "supervisor_snapshot": supervisor_snapshot,
        "student_gate": student_gate,
        "execution_snapshot": execution_snapshot,
        "files": {
            "supervisor_snapshot": file_probe(supervisor_snapshot_path),
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
    chart_manifest_path = ops_root / "chart_profile_manifest_latest.json"
    profile_report_path = project_root / "EVIDENCE" / "mt5_microbots_profile_setup_report.json"

    wellbeing = read_json(wellbeing_path)
    cohort = read_json(cohort_path)
    chart_manifest = read_json(chart_manifest_path)
    profile_report = read_json(profile_report_path)

    symbols = extract_symbols(common_root, profile_report, chart_manifest, cohort)
    symbol_states = [load_symbol_state(common_root, symbol) for symbol in symbols]

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
