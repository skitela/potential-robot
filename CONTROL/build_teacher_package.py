#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any, Dict, Iterable, List


def read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def flatten_features(curriculum: Dict[str, Any]) -> List[str]:
    bands = curriculum.get("knowledge_bands", {})
    features: List[str] = []
    for value in bands.values():
        if isinstance(value, list):
            features.extend(value)
    features.extend(curriculum.get("required_features", []))
    deduped: List[str] = []
    seen = set()
    for item in features:
        if item in seen:
            continue
        seen.add(item)
        deduped.append(item)
    return deduped


def merge_curriculum(curriculum: Dict[str, Any], global_curriculum: Dict[str, Any] | None) -> Dict[str, Any]:
    merged = json.loads(json.dumps(curriculum))
    bands = merged.setdefault("knowledge_bands", {})
    inherits_global = bool(bands.get("inherits_global", False))
    if not inherits_global or global_curriculum is None:
        return merged

    merged_bands: Dict[str, Any] = {}
    for key, value in global_curriculum.get("knowledge_bands", {}).items():
        merged_bands[key] = list(value) if isinstance(value, list) else value

    for key, value in bands.items():
        if key == "inherits_global":
            continue
        if isinstance(value, list):
            merged_bands[key] = list(value)
        else:
            merged_bands[key] = value

    merged["knowledge_bands"] = merged_bands
    merged_required = list(global_curriculum.get("required_features", []))
    merged_required.extend(curriculum.get("required_features", []))
    merged["required_features"] = list(dict.fromkeys(merged_required))
    return merged


def emit_contract(curriculum: Dict[str, Any], out_csv: Path) -> None:
    thresholds = curriculum["thresholds"]
    promotion_gate = curriculum["promotion_gate"]
    mode = curriculum["mode"]
    scope = curriculum["scope"]
    personal_allowed = mode in {"GLOBAL_PLUS_PERSONAL", "PERSONAL_PRIMARY"} or scope == "PERSONAL"
    rows = [
        ("enabled", "1"),
        ("student_gate_enabled", "1"),
        ("teacher_required", "1"),
        ("outcome_ready", "1" if promotion_gate.get("require_outcome_ready", True) else "0"),
        ("local_model_available", "1" if scope == "PERSONAL" else "0"),
        ("global_model_available", "1"),
        ("paper_live_enabled", "0"),
        ("local_training_mode", "PERSONAL_CANDIDATE" if scope == "PERSONAL" else "FALLBACK_ONLY"),
        ("runtime_scope", "LAPTOP_ONLY"),
        ("paper_live_bucket", mode),
        ("universe_version", "TEACHER_PACKAGE_V1"),
        ("plan_hash", curriculum["teacher_id"]),
        ("teacher_scope", scope),
        ("teacher_mode", mode),
        ("teacher_id", curriculum["teacher_id"]),
        ("symbol", curriculum["symbol"]),
        ("symbol_family", curriculum["symbol_family"]),
        ("personal_allowed", "1" if personal_allowed else "0"),
        ("min_gate_probability", str(thresholds["min_gate_probability"])),
        ("min_decision_score_pln", str(thresholds["min_decision_score_pln"])),
        ("max_spread_points", str(thresholds["max_spread_points"])),
        ("max_server_ping_ms", str(thresholds["max_server_ping_ms"])),
        ("max_server_latency_us_avg", str(thresholds["max_server_latency_us_avg"]))
    ]
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerows(rows)


def emit_manifest(curriculum: Dict[str, Any], out_json: Path) -> None:
    manifest = {
        "schema_version": "1.0",
        "teacher_id": curriculum["teacher_id"],
        "scope": curriculum["scope"],
        "symbol": curriculum["symbol"],
        "symbol_family": curriculum["symbol_family"],
        "mode": curriculum["mode"],
        "feature_count": len(flatten_features(curriculum)),
        "features": flatten_features(curriculum),
        "thresholds": curriculum["thresholds"],
        "promotion_gate": curriculum["promotion_gate"]
    }
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--curriculum", required=True, help="Path to curriculum JSON")
    parser.add_argument("--out-dir", required=True, help="Output directory")
    parser.add_argument("--global-curriculum", help="Optional global curriculum for inheritance")
    args = parser.parse_args()

    curriculum = read_json(Path(args.curriculum))
    global_curriculum = read_json(Path(args.global_curriculum)) if args.global_curriculum else None
    curriculum = merge_curriculum(curriculum, global_curriculum)
    out_dir = Path(args.out_dir)

    emit_contract(curriculum, out_dir / "teacher_package_contract.csv")
    emit_manifest(curriculum, out_dir / "teacher_package_manifest_latest.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
