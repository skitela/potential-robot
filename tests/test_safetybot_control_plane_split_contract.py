from __future__ import annotations

import ast
from pathlib import Path
from typing import List


def _class_method_node(source_path: Path, class_name: str, method_name: str) -> ast.FunctionDef:
    tree = ast.parse(source_path.read_text(encoding="utf-8"))
    for node in tree.body:
        if isinstance(node, ast.ClassDef) and node.name == class_name:
            for method in node.body:
                if isinstance(method, ast.FunctionDef) and method.name == method_name:
                    return method
    raise AssertionError(f"Method not found: {class_name}.{method_name}")


def _called_names(fn: ast.FunctionDef) -> List[str]:
    names: List[str] = []
    for node in ast.walk(fn):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            names.append(str(node.func.attr))
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            names.append(str(node.func.id))
    return names


def test_scan_once_no_longer_emits_policy_and_kernel_config() -> None:
    src = Path("BIN/safetybot.py").resolve()
    fn = _class_method_node(src, "SafetyBot", "scan_once")
    called = _called_names(fn)
    assert "_emit_policy_runtime" not in called
    assert "_emit_kernel_config" not in called
    assert "_refresh_live_module_states" not in called
    assert "_refresh_no_live_drift_check" not in called
    assert "_refresh_cost_guard_auto_relax_state" not in called
    assert "_time_anchor_sync_if_due" not in called
    assert "group_budget_state" not in called
    assert "_runtime_cache_control_plane_inputs" in called


def test_runtime_maintenance_step_emits_policy_and_kernel_config() -> None:
    src = Path("BIN/safetybot.py").resolve()
    fn = _class_method_node(src, "SafetyBot", "_runtime_maintenance_step")
    called = _called_names(fn)
    assert "_emit_policy_runtime" in called
    assert "_emit_kernel_config" in called
    assert "_runtime_refresh_control_plane_state" in called
    assert "_runtime_flush_market_snapshot" in called


def test_runtime_refresh_control_plane_state_refreshes_group_policy_cache() -> None:
    src = Path("BIN/safetybot.py").resolve()
    fn = _class_method_node(src, "SafetyBot", "_runtime_refresh_control_plane_state")
    called = _called_names(fn)
    assert "poll_deals" in called
    assert "_runtime_refresh_group_policy_cache" in called
    assert "_runtime_refresh_global_guard_cache" in called
    assert "_runtime_refresh_market_guard_cache" in called


def test_scan_once_no_longer_builds_market_guards_directly() -> None:
    src = Path("BIN/safetybot.py").resolve()
    fn = _class_method_node(src, "SafetyBot", "scan_once")
    called = _called_names(fn)
    assert "_runtime_get_cached_market_guard_state" in called


def test_scan_once_stages_market_snapshot_instead_of_writing_it() -> None:
    src = Path("BIN/safetybot.py").resolve()
    fn = _class_method_node(src, "SafetyBot", "scan_once")
    called = _called_names(fn)
    assert "_runtime_stage_market_snapshot" in called
    assert "atomic_write_json" not in called
