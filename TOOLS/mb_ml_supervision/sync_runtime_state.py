from __future__ import annotations

from pathlib import Path
from typing import Any
import csv

from .audits import AuditThresholds, build_overlay_audit, load_active_registry_symbols
from .io_utils import dump_json, ensure_parent, recursive_collect_symbols, read_json, utc_now_iso
from .paths import OverlayPaths


def _parse_package_thresholds(paths: OverlayPaths) -> dict[str, float]:
    payload = read_json(paths.package_json_path, default={})
    defaults = {
        "min_gate_probability": 0.53,
        "min_decision_score_pln": 0.0,
        "max_spread_points": 999.0,
        "max_server_ping_ms": 35.0,
        "max_server_latency_us_avg": 250000.0,
    }
    if not isinstance(payload, dict):
        return defaults
    search_keys = {
        "min_gate_probability",
        "min_decision_score_pln",
        "max_spread_points",
        "max_server_ping_ms",
        "max_server_latency_us_avg",
    }

    def walk(node: Any) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                if key in search_keys:
                    try:
                        defaults[key] = float(value)
                    except Exception:
                        pass
                walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(payload)
    return defaults


def _scan_symbol_onnx(paths: OverlayPaths, symbol: str) -> bool:
    model_dir = paths.symbol_models_dir / symbol
    return model_dir.exists() and any(model_dir.glob("*.onnx"))


def _scan_global_onnx(paths: OverlayPaths) -> bool:
    return paths.global_model_onnx_path.exists()


def write_student_gate_contract(
    target_path: Path,
    *,
    symbol: str,
    local_training_mode: str,
    outcome_ready: bool,
    local_model_available: bool,
    global_model_available: bool,
    thresholds: dict[str, float],
    package_exists: bool,
) -> None:
    ensure_parent(target_path)
    rows = [
        ("schema_version", "1.0"),
        ("symbol", symbol),
        ("enabled", "1" if package_exists else "0"),
        ("student_gate_enabled", "1" if (package_exists and local_model_available) else "0"),
        ("teacher_required", "1"),
        ("local_training_mode", local_training_mode),
        ("outcome_ready", "1" if outcome_ready else "0"),
        ("local_model_available", "1" if local_model_available else "0"),
        ("global_model_available", "1" if global_model_available else "0"),
        ("min_gate_probability", f"{thresholds['min_gate_probability']:.6f}"),
        ("min_decision_score_pln", f"{thresholds['min_decision_score_pln']:.6f}"),
        ("max_spread_points", f"{thresholds['max_spread_points']:.6f}"),
        ("max_server_ping_ms", f"{thresholds['max_server_ping_ms']:.6f}"),
        ("max_server_latency_us_avg", f"{thresholds['max_server_latency_us_avg']:.6f}"),
        ("package_generated_at_utc", utc_now_iso()),
    ]
    with target_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerows(rows)


def sync_runtime_state(
    paths: OverlayPaths,
    thresholds: AuditThresholds | None = None,
) -> dict[str, Any]:
    thresholds = thresholds or AuditThresholds()
    audit = build_overlay_audit(paths, thresholds=thresholds)
    runtime_thresholds = _parse_package_thresholds(paths)
    package_exists = paths.package_json_path.exists()
    global_model_available = _scan_global_onnx(paths)

    active_registry = load_active_registry_symbols(paths)
    outputs: dict[str, Any] = {}
    for item in active_registry:
        symbol = item["symbol"]
        mode = audit["symbol_activity"]["training_modes"].get(symbol, "FALLBACK_ONLY")
        outcome_rows = int(audit["symbol_activity"]["outcome_counts"].get(symbol, 0))
        local_model_available = _scan_symbol_onnx(paths, symbol)
        target_path = paths.runtime_symbol_state_root / symbol / "student_gate_contract.csv"
        write_student_gate_contract(
            target_path,
            symbol=symbol,
            local_training_mode=mode,
            outcome_ready=outcome_rows >= thresholds.min_outcome_rows_for_shadow_ready,
            local_model_available=local_model_available,
            global_model_available=global_model_available,
            thresholds=runtime_thresholds,
            package_exists=package_exists,
        )
        outputs[symbol] = {
            "path": str(target_path),
            "local_training_mode": mode,
            "outcome_rows": outcome_rows,
            "local_model_available": local_model_available,
            "global_model_available": global_model_available,
        }

    registry_payload = {
        "schema_version": "1.0",
        "generated_at_utc": utc_now_iso(),
        "package_exists": package_exists,
        "global_model_available": global_model_available,
        "thresholds": runtime_thresholds,
        "symbols": outputs,
    }
    dump_json(paths.sync_runtime_registry_path, registry_payload)
    return registry_payload
