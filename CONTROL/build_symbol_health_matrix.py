from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional


DEFAULT_PROJECT_ROOT = Path(r"C:\MAKRO_I_MIKRO_BOT")
FRESHNESS_THRESHOLD_SECONDS = 1800
PAPER_STUCK_THRESHOLD_SECONDS = 1800


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Builds per-symbol health matrix.")
    parser.add_argument("--project-root", default=str(DEFAULT_PROJECT_ROOT))
    return parser.parse_args()


def read_json(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8-sig"))


def snapshot_age_seconds(snapshot: Optional[Dict[str, Any]]) -> Optional[int]:
    if not isinstance(snapshot, dict):
        return None
    raw = snapshot.get("generated_at_utc")
    if raw in (None, ""):
        return None
    try:
        generated = datetime.fromtimestamp(int(raw), tz=timezone.utc)
    except Exception:
        return None
    return int((datetime.now(timezone.utc) - generated).total_seconds())


def classify_symbol(item: Dict[str, Any]) -> Dict[str, Any]:
    symbol = str(item.get("symbol") or "")
    supervisor = item.get("supervisor_snapshot") or {}
    gate = item.get("student_gate") or {}
    files = item.get("files") or {}
    snapshot_file = files.get("supervisor_snapshot") or {}

    age_seconds = snapshot_age_seconds(supervisor)
    contract_present = bool(supervisor.get("contract_present"))
    local_model_available = bool(supervisor.get("local_model_available"))
    paper_position_open = bool(supervisor.get("paper_position_open"))
    last_stage = str(supervisor.get("last_stage") or "")
    last_reason = str(supervisor.get("last_reason_code") or "")
    local_training_mode = str(supervisor.get("local_training_mode") or gate.get("local_training_mode") or "")

    status = "RUNNING_OBSERVING"
    reason = "SUPERVISOR_SNAPSHOT_OK"

    if not snapshot_file.get("present"):
        status = "RUNTIME_DOWN"
        reason = "SUPERVISOR_SNAPSHOT_MISSING"
    elif age_seconds is not None and age_seconds > FRESHNESS_THRESHOLD_SECONDS:
        status = "RUNTIME_DOWN"
        reason = "SUPERVISOR_SNAPSHOT_STALE"
    elif not contract_present:
        status = "CONTRACT_MISSING"
        reason = "ML_CONTRACT_MISSING"
    elif not local_model_available and local_training_mode not in ("", "FALLBACK_ONLY"):
        status = "MODEL_NOT_READY"
        reason = "LOCAL_MODEL_UNAVAILABLE"
    elif paper_position_open and age_seconds is not None and age_seconds > PAPER_STUCK_THRESHOLD_SECONDS:
        status = "PAPER_POSITION_STUCK"
        reason = "PAPER_POSITION_STALE"
    elif last_stage in {"LESSON_WRITE", "KNOWLEDGE_WRITE", "EXECUTION_TRUTH_CLOSE"}:
        status = "RUNNING_LEARNING"
        reason = last_stage
    elif last_reason in {"WAIT_NEW_BAR", "MARKET_IDLE", "OUTSIDE_TRADE_WINDOW"}:
        status = "MARKET_IDLE"
        reason = last_reason
    elif last_reason in {
        "SCORE_BELOW_TRIGGER",
        "LOW_CONFIDENCE",
        "CONTEXT_LOW_CONFIDENCE",
        "ML_STUDENT_GATE_BLOCK",
    }:
        status = "NO_SIGNAL_LOW_SCORE"
        reason = last_reason
    elif files.get("onnx_log", {}).get("present") and not files.get("learning_log", {}).get("present"):
        status = "STALL_NO_LESSON"
        reason = "OBSERVING_WITHOUT_LESSON"

    return {
        "symbol": symbol,
        "status": status,
        "reason": reason,
        "snapshot_age_seconds": age_seconds,
        "last_stage": last_stage,
        "last_reason_code": last_reason,
        "paper_position_open": paper_position_open,
        "contract_present": contract_present,
        "local_model_available": local_model_available,
        "local_training_mode": local_training_mode,
    }


def main() -> int:
    args = parse_args()
    project_root = Path(args.project_root)
    ops_root = project_root / "EVIDENCE" / "OPS"
    control_state = read_json(ops_root / "control_state_latest.json")
    items = [classify_symbol(item) for item in control_state.get("symbols", []) or []]

    payload = {
        "schema_version": "1.0",
        "generated_at_local": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "summary": {
            "symbol_count": len(items),
            "running_learning_count": sum(1 for item in items if item["status"] == "RUNNING_LEARNING"),
            "running_observing_count": sum(1 for item in items if item["status"] == "RUNNING_OBSERVING"),
            "stalled_count": sum(1 for item in items if item["status"] == "STALL_NO_LESSON"),
            "runtime_down_count": sum(1 for item in items if item["status"] == "RUNTIME_DOWN"),
        },
        "items": items,
    }

    out_path = ops_root / "symbol_health_matrix_latest.json"
    out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"WROTE {out_path} symbols={len(items)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
