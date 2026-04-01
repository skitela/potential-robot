from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

from classify_learning_blockers import classify_learning_blocker


DEFAULT_PROJECT_ROOT = Path(r"C:\MAKRO_I_MIKRO_BOT")
DEFAULT_COMMON_ROOT = Path(r"C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT")
FRESH_SECONDS = 1800


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build learning supervisor matrix from runtime snapshots.")
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


def probe(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {"present": False, "fresh": False, "age_seconds": None, "path": str(path)}
    stat = path.stat()
    age_seconds = int((datetime.now() - datetime.fromtimestamp(stat.st_mtime)).total_seconds())
    return {
        "present": True,
        "fresh": age_seconds <= FRESH_SECONDS,
        "age_seconds": age_seconds,
        "path": str(path),
    }


def read_last_decision_event(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    try:
        lines = path.read_text(encoding="utf-8-sig", errors="ignore").splitlines()
    except Exception:
        return {}
    for line in reversed(lines[-16:]):
        parts = line.split("\t")
        if len(parts) < 5 or parts[0] == "ts":
            continue
        last_stage = parts[2]
        last_reason_code = parts[4]
        last_scan_source = "TIMER_FALLBACK_SCAN" if last_stage == "DIAGNOSTIC" and last_reason_code == "TIMER_FALLBACK_SCAN" else ""
        return {
            "last_stage": last_stage,
            "last_reason_code": last_reason_code,
            "last_scan_source": last_scan_source,
        }
    return {}


def canonical_symbol(symbol: str) -> str:
    value = str(symbol or "").strip()
    if value.lower().endswith(".pro"):
        value = value[:-4]
    if value.upper() == "COPPERUS":
        value = "COPPER-US"
    return value


def load_contract(path: Path) -> Dict[str, Any]:
    payload = read_json(path) or {}
    symbols = payload.get("symbols")
    return symbols if isinstance(symbols, dict) else {}


def main() -> int:
    args = parse_args()
    project_root = Path(args.project_root)
    common_root = Path(args.common_root)
    ops_root = project_root / "EVIDENCE" / "OPS"

    contract = load_contract(project_root / "CONFIG" / "learning_universe_contract.json")
    first_wave = read_json(ops_root / "first_wave_lesson_closure_latest.json") or {}
    cohort = read_json(ops_root / "global_teacher_cohort_activity_latest.json") or {}

    first_wave_index = {
        canonical_symbol(str(item.get("symbol_alias") or "")): item
        for item in (first_wave.get("results") or [])
        if str(item.get("symbol_alias") or "").strip()
    }
    cohort_index = {
        canonical_symbol(str(item.get("symbol_alias") or "")): item
        for item in (cohort.get("items") or [])
        if str(item.get("symbol_alias") or "").strip()
    }

    items: List[Dict[str, Any]] = []
    for symbol, meta in sorted(contract.items()):
        canonical = canonical_symbol(symbol)
        state_root = common_root / "state" / canonical
        logs_root = common_root / "logs" / canonical
        snapshot = read_json(state_root / "learning_supervisor_snapshot_latest.json") or {}
        gate_payload = read_json(state_root / "student_gate_latest.json") or {}
        last_decision = read_last_decision_event(logs_root / "decision_events.csv")
        gate_probe = probe(state_root / "student_gate_latest.json")
        learning_probe = probe(logs_root / "learning_observations_v2.csv")
        knowledge_probe = probe(logs_root / "broker_net_ledger_runtime.csv")
        decision_probe = probe(logs_root / "decision_events.csv")
        onnx_probe = probe(logs_root / "onnx_observations.csv")

        if not snapshot:
            snapshot = {
                "runtime_heartbeat_alive": bool(decision_probe["fresh"] and onnx_probe["fresh"]),
                "last_stage": last_decision.get("last_stage", ""),
                "last_reason_code": last_decision.get("last_reason_code", ""),
                "last_scan_source": "",
                "setup_type": "",
                "gate_visible": False,
                "paper_open_visible": False,
                "paper_close_visible": False,
                "lesson_write_visible": False,
                "knowledge_write_visible": False,
                "teacher_score": 0.0,
                "student_score": 0.0,
                "local_training_mode": "",
                "contract_present": False,
                "local_model_available": False,
                "global_model_available": False,
                "paper_position_open": False,
            }
        elif last_decision and str(snapshot.get("last_stage") or "").upper() in {"", "BOOTSTRAP", "TIMER"}:
            snapshot["last_stage"] = last_decision.get("last_stage", snapshot.get("last_stage", ""))
            snapshot["last_reason_code"] = last_decision.get("last_reason_code", snapshot.get("last_reason_code", ""))
            if not str(snapshot.get("last_scan_source") or "").strip():
                snapshot["last_scan_source"] = last_decision.get("last_scan_source", "")

        gate_applied = bool(gate_payload.get("gate_applied"))
        effective_gate_visible = bool(
            gate_applied
            or snapshot.get("paper_open_visible")
            or snapshot.get("paper_close_visible")
            or snapshot.get("lesson_write_visible")
            or snapshot.get("knowledge_write_visible")
            or snapshot.get("paper_position_open")
        )
        snapshot["gate_applied"] = gate_applied
        snapshot["gate_visible"] = effective_gate_visible

        blocker_class, blocker_reason = classify_learning_blocker(snapshot)
        full_learning_ok = bool(learning_probe["fresh"] and knowledge_probe["fresh"])
        if canonical in first_wave_index and bool(first_wave_index[canonical].get("fresh_chain_ready")):
            blocker_class, blocker_reason = "FULL_LEARNING_OK", "FIRST_WAVE_FRESH_CHAIN"
            full_learning_ok = True
        elif canonical in cohort_index and bool(cohort_index[canonical].get("fresh_full_lesson")):
            blocker_class, blocker_reason = "FULL_LEARNING_OK", "GLOBAL_COHORT_FRESH_LESSON"
            full_learning_ok = True

        items.append(
            {
                "symbol": canonical,
                "cohort": meta.get("cohort"),
                "family": meta.get("family"),
                "teacher_mode": meta.get("teacher_mode"),
                "policy_profile": meta.get("policy_profile"),
                "snapshot_present": bool(snapshot),
                "runtime_heartbeat_alive": bool(snapshot.get("runtime_heartbeat_alive")),
                "last_stage": snapshot.get("last_stage"),
                "last_reason_code": snapshot.get("last_reason_code"),
                "last_scan_source": snapshot.get("last_scan_source"),
                "setup_type": snapshot.get("setup_type"),
                "gate_visible": effective_gate_visible,
                "gate_applied": gate_applied,
                "paper_open_visible": bool(snapshot.get("paper_open_visible")),
                "paper_close_visible": bool(snapshot.get("paper_close_visible")),
                "paper_position_open": bool(snapshot.get("paper_position_open")),
                "lesson_write_visible": bool(snapshot.get("lesson_write_visible")) or bool(learning_probe["fresh"]),
                "knowledge_write_visible": bool(snapshot.get("knowledge_write_visible")) or bool(knowledge_probe["fresh"]),
                "teacher_score": snapshot.get("teacher_score", 0.0),
                "student_score": snapshot.get("student_score", 0.0),
                "local_training_mode": snapshot.get("local_training_mode", ""),
                "contract_present": bool(snapshot.get("contract_present")),
                "local_model_available": bool(snapshot.get("local_model_available")),
                "global_model_available": bool(snapshot.get("global_model_available")),
                "blocker_class": blocker_class,
                "blocker_reason": blocker_reason,
                "full_learning_ok": full_learning_ok,
                "files": {
                    "decision_log": decision_probe,
                    "onnx_log": onnx_probe,
                    "student_gate": gate_probe,
                    "learning_log": learning_probe,
                    "knowledge_log": knowledge_probe,
                },
            }
        )

    payload = {
        "schema_version": "1.0",
        "generated_at_local": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "summary": {
            "symbol_count": len(items),
            "full_learning_ok_count": sum(1 for item in items if item["blocker_class"] == "FULL_LEARNING_OK"),
            "heartbeat_only_count": sum(1 for item in items if item["blocker_class"] == "HEARTBEAT_ONLY"),
            "wait_new_bar_starved_count": sum(1 for item in items if item["blocker_class"] == "WAIT_NEW_BAR_STARVED"),
            "no_setup_starved_count": sum(1 for item in items if item["blocker_class"] == "NO_SETUP_STARVED"),
            "tuning_freeze_starved_count": sum(1 for item in items if item["blocker_class"] == "TUNING_FREEZE_STARVED"),
            "symbol_policy_starved_count": sum(1 for item in items if item["blocker_class"] == "SYMBOL_POLICY_STARVED"),
            "gate_visible_no_outcome_count": sum(1 for item in items if item["blocker_class"] == "GATE_VISIBLE_NO_OUTCOME"),
            "outcome_write_fail_count": sum(1 for item in items if item["blocker_class"] == "OUTCOME_WRITE_FAIL"),
            "unclassified_count": sum(1 for item in items if item["blocker_class"] == "UNCLASSIFIED"),
        },
        "items": items,
    }

    json_path = ops_root / "learning_supervisor_matrix_latest.json"
    md_path = ops_root / "learning_supervisor_matrix_latest.md"
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "# Learning Supervisor Matrix",
        "",
        f"- generated_at_local: {payload['generated_at_local']}",
        f"- symbol_count: {payload['summary']['symbol_count']}",
        f"- full_learning_ok_count: {payload['summary']['full_learning_ok_count']}",
        f"- heartbeat_only_count: {payload['summary']['heartbeat_only_count']}",
        f"- wait_new_bar_starved_count: {payload['summary']['wait_new_bar_starved_count']}",
        f"- no_setup_starved_count: {payload['summary']['no_setup_starved_count']}",
        f"- tuning_freeze_starved_count: {payload['summary']['tuning_freeze_starved_count']}",
        f"- symbol_policy_starved_count: {payload['summary']['symbol_policy_starved_count']}",
        f"- gate_visible_no_outcome_count: {payload['summary']['gate_visible_no_outcome_count']}",
        f"- outcome_write_fail_count: {payload['summary']['outcome_write_fail_count']}",
        "",
        "## Symbols",
        "",
    ]
    for item in items:
        lines.append(
            f"- {item['symbol']}: class={item['blocker_class']}, reason={item['blocker_reason']}, stage={item['last_stage']}, scan={item['last_scan_source']}, gate={str(item['gate_visible']).lower()}, lesson={str(item['lesson_write_visible']).lower()}, knowledge={str(item['knowledge_write_visible']).lower()}"
        )
    md_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"WROTE {json_path} symbols={len(items)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
