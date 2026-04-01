from __future__ import annotations

from typing import Any, Dict, Tuple


def _upper(value: Any) -> str:
    return str(value or "").strip().upper()


def classify_learning_blocker(state: Dict[str, Any]) -> Tuple[str, str]:
    last_stage = _upper(state.get("last_stage"))
    last_reason = _upper(state.get("last_reason_code"))
    last_scan_source = _upper(state.get("last_scan_source"))
    setup_type = _upper(state.get("setup_type"))
    gate_visible = bool(state.get("gate_visible"))
    gate_applied = bool(state.get("gate_applied"))
    paper_open_visible = bool(state.get("paper_open_visible"))
    paper_close_visible = bool(state.get("paper_close_visible"))
    paper_position_open = bool(state.get("paper_position_open"))
    lesson_write_visible = bool(state.get("lesson_write_visible"))
    knowledge_write_visible = bool(state.get("knowledge_write_visible"))
    runtime_heartbeat_alive = bool(state.get("runtime_heartbeat_alive"))
    effective_gate_visible = bool(gate_applied or paper_open_visible or paper_close_visible or lesson_write_visible or knowledge_write_visible or paper_position_open)

    if lesson_write_visible and knowledge_write_visible:
        return "FULL_LEARNING_OK", "LESSON_AND_KNOWLEDGE_VISIBLE"

    if (paper_open_visible or paper_position_open) and not (paper_close_visible or lesson_write_visible or knowledge_write_visible):
        return "GATE_VISIBLE_NO_OUTCOME", "PAPER_OPEN_WITHOUT_CLOSE"

    if last_reason.endswith("_FAIL"):
        return "OUTCOME_WRITE_FAIL", last_reason

    if last_scan_source == "TIMER_FALLBACK_SCAN" and last_reason == "WAIT_NEW_BAR":
        return "WAIT_NEW_BAR_STARVED", "TIMER_SCAN_STOPS_AT_WAIT_NEW_BAR"

    if last_reason == "WAIT_NEW_BAR" and not effective_gate_visible:
        return "WAIT_NEW_BAR_STARVED", "WAIT_NEW_BAR_WITHOUT_GATE_PROGRESS"

    if last_stage == "DIAGNOSTIC" and last_reason == "TIMER_FALLBACK_SCAN" and not effective_gate_visible:
        return "WAIT_NEW_BAR_STARVED", "DIAGNOSTIC_TIMER_SCAN_WITHOUT_GATE"

    if last_reason.startswith("NO_SETUP_") or setup_type == "NONE":
        return "NO_SETUP_STARVED", last_reason or "SETUP_NONE"

    if last_stage == "RATE_GUARD" or last_reason in {"BROKER_ORDER_RATE_LIMIT", "BROKER_PRICE_RATE_LIMIT"}:
        return "RATE_GUARD_STARVED", last_reason or last_stage

    if "FREEZE" in last_reason or "DEFENSIVE" in last_reason or "COOL_FLEET" == last_reason:
        return "TUNING_FREEZE_STARVED", last_reason

    if "BLOCK" in last_reason or "DIRTY" in last_reason or "DAILY_LOSS" in last_reason or "PORTFOLIO_HEAT" in last_reason:
        return "SYMBOL_POLICY_STARVED", last_reason

    if last_reason in {"SCORE_BELOW_TRIGGER", "LOW_CONFIDENCE", "CONTEXT_LOW_CONFIDENCE"}:
        return "NO_SIGNAL_LOW_SCORE", last_reason

    if effective_gate_visible and not (paper_open_visible or paper_close_visible or lesson_write_visible or knowledge_write_visible):
        return "GATE_VISIBLE_NO_OUTCOME", "GATE_VISIBLE_WITHOUT_OUTCOME_CHAIN"

    if runtime_heartbeat_alive and last_stage in {"TIMER", "BOOTSTRAP", "POSITION"} and not effective_gate_visible and not paper_position_open:
        return "HEARTBEAT_ONLY", last_stage

    return "UNCLASSIFIED", last_reason or last_stage or "UNKNOWN"
