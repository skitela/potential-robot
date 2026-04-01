#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any, Dict, List, Optional


DEFAULT_DEPLOYMENT_BUCKET_BY_SCOPE = {
    "GLOBAL": "GLOBAL_TEACHER_ONLY",
    "PERSONAL": "GLOBAL_TEACHER_ONLY",
}

DEFAULT_LOCAL_TRAINING_MODE_BY_SCOPE = {
    "GLOBAL": "FALLBACK_ONLY",
    "PERSONAL": "PERSONAL_CANDIDATE",
}


def read_json(path: Optional[Path]) -> Dict[str, Any]:
    if path is None:
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def normalize_token(value: Any, fallback: str = "") -> str:
    text = str(value or "").strip()
    return text or fallback


def normalize_scope(curriculum: Dict[str, Any]) -> str:
    return normalize_token(curriculum.get("scope"), "GLOBAL").upper()


def collect_features(value: Any, features: List[str]) -> None:
    if isinstance(value, list):
        for item in value:
            if isinstance(item, str) and item.strip():
                features.append(item.strip())
    elif isinstance(value, dict):
        for nested in value.values():
            collect_features(nested, features)


def flatten_features(curriculum: Dict[str, Any]) -> List[str]:
    features: List[str] = []
    collect_features(curriculum.get("knowledge_bands", {}), features)
    collect_features(curriculum.get("required_features", []), features)
    deduped: List[str] = []
    seen = set()
    for item in features:
        if item in seen:
            continue
        seen.add(item)
        deduped.append(item)
    return deduped


def merge_curriculum(curriculum: Dict[str, Any], global_curriculum: Dict[str, Any]) -> Dict[str, Any]:
    merged = json.loads(json.dumps(curriculum))
    knowledge_bands = merged.setdefault("knowledge_bands", {})
    inherits_global = bool(knowledge_bands.get("inherits_global", False))
    merged["inherits_global"] = inherits_global
    if not inherits_global or not global_curriculum:
        return merged

    merged_bands: Dict[str, Any] = {}
    for key, value in (global_curriculum.get("knowledge_bands") or {}).items():
        if key == "inherits_global":
            continue
        merged_bands[key] = json.loads(json.dumps(value))

    for key, value in knowledge_bands.items():
        if key == "inherits_global":
            continue
        merged_bands[key] = json.loads(json.dumps(value))

    merged["knowledge_bands"] = merged_bands
    merged_required = list(global_curriculum.get("required_features", []))
    merged_required.extend(curriculum.get("required_features", []))
    merged["required_features"] = list(dict.fromkeys(merged_required))
    return merged


def resolve_teacher_package_mode(curriculum: Dict[str, Any]) -> str:
    return normalize_token(curriculum.get("mode"), "GLOBAL_ONLY")


def resolve_deployment_bucket(curriculum: Dict[str, Any], explicit_bucket: str = "") -> str:
    if explicit_bucket.strip():
        return explicit_bucket.strip()
    configured_bucket = normalize_token(curriculum.get("deployment_bucket"))
    if configured_bucket:
        return configured_bucket
    return DEFAULT_DEPLOYMENT_BUCKET_BY_SCOPE.get(normalize_scope(curriculum), "GLOBAL_TEACHER_ONLY")


def resolve_local_training_mode(curriculum: Dict[str, Any]) -> str:
    configured_mode = normalize_token(curriculum.get("local_training_mode"))
    if configured_mode:
        return configured_mode
    return DEFAULT_LOCAL_TRAINING_MODE_BY_SCOPE.get(normalize_scope(curriculum), "FALLBACK_ONLY")


def emit_contract(
    curriculum: Dict[str, Any],
    out_csv: Path,
    deployment_bucket: str,
    policy_payload: Dict[str, Any],
) -> None:
    thresholds = curriculum["thresholds"]
    promotion_gate = curriculum["promotion_gate"]
    teacher_package_mode = resolve_teacher_package_mode(curriculum)
    teacher_scope = normalize_scope(curriculum)
    personal_allowed = teacher_package_mode in {"GLOBAL_PLUS_PERSONAL", "PERSONAL_PRIMARY"} or teacher_scope == "PERSONAL"
    rows = [
        ("enabled", "1"),
        ("student_gate_enabled", "1"),
        ("teacher_required", "1"),
        ("outcome_ready", "1" if promotion_gate.get("require_outcome_ready", True) else "0"),
        ("local_model_available", "1" if teacher_scope == "PERSONAL" else "0"),
        ("global_model_available", "1"),
        ("paper_live_enabled", "0"),
        ("local_training_mode", resolve_local_training_mode(curriculum)),
        ("runtime_scope", normalize_token(curriculum.get("runtime_scope"), "LAPTOP_ONLY")),
        ("paper_live_bucket", deployment_bucket),
        ("teacher_package_mode", teacher_package_mode),
        # Legacy mirror kept for backward compatibility while downstream readers migrate.
        ("teacher_mode", teacher_package_mode),
        ("teacher_scope", teacher_scope),
        ("teacher_id", normalize_token(curriculum.get("teacher_id"))),
        ("symbol", normalize_token(curriculum.get("symbol"))),
        ("symbol_family", normalize_token(curriculum.get("symbol_family"))),
        ("personal_allowed", "1" if personal_allowed else "0"),
        ("teacher_policy_id", normalize_token(policy_payload.get("policy_id"), "TEACHER_PROMOTION_POLICY_V1")),
        ("universe_version", normalize_token(curriculum.get("universe_version"), "TEACHER_PACKAGE_V1")),
        ("plan_hash", normalize_token(curriculum.get("teacher_id"))),
        ("min_gate_probability", str(thresholds["min_gate_probability"])),
        ("min_decision_score_pln", str(thresholds["min_decision_score_pln"])),
        ("max_spread_points", str(thresholds["max_spread_points"])),
        ("max_server_ping_ms", str(thresholds["max_server_ping_ms"])),
        ("max_server_latency_us_avg", str(thresholds["max_server_latency_us_avg"])),
    ]
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerows(rows)


def emit_manifest(
    curriculum: Dict[str, Any],
    out_json: Path,
    deployment_bucket: str,
    policy_payload: Dict[str, Any],
) -> None:
    features = flatten_features(curriculum)
    manifest = {
        "schema_version": "1.0",
        "teacher_id": curriculum["teacher_id"],
        "scope": curriculum["scope"],
        "symbol": curriculum["symbol"],
        "symbol_family": curriculum["symbol_family"],
        "teacher_package_mode": resolve_teacher_package_mode(curriculum),
        "deployment_bucket": deployment_bucket,
        "local_training_mode": resolve_local_training_mode(curriculum),
        "feature_count": len(features),
        "features": features,
        "required_features": curriculum.get("required_features", []),
        "inherits_global": bool(curriculum.get("inherits_global", (curriculum.get("knowledge_bands") or {}).get("inherits_global", False))),
        "thresholds": curriculum["thresholds"],
        "promotion_gate": curriculum["promotion_gate"],
        "policy_ref": {
            "policy_id": normalize_token(policy_payload.get("policy_id"), "TEACHER_PROMOTION_POLICY_V1"),
            "schema_version": normalize_token(policy_payload.get("schema_version"), "1.0"),
        },
        "artifacts": {
            "contract_file": "teacher_package_contract.csv",
            "manifest_file": "teacher_package_manifest_latest.json",
            "promotion_snapshot_file": "teacher_promotion_snapshot_latest.json",
            "knowledge_snapshot_file": "teacher_knowledge_snapshot_latest.json",
        },
    }
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--curriculum", required=True, help="Path to curriculum JSON")
    parser.add_argument("--out-dir", required=True, help="Output directory")
    parser.add_argument("--global-curriculum", help="Optional global curriculum for inheritance")
    parser.add_argument("--policy", help="Optional promotion policy JSON")
    parser.add_argument(
        "--deployment-bucket",
        default="",
        help="Optional deployment bucket. Kept separate from teacher_package_mode.",
    )
    args = parser.parse_args()

    curriculum = read_json(Path(args.curriculum))
    global_curriculum = read_json(Path(args.global_curriculum)) if args.global_curriculum else {}
    curriculum = merge_curriculum(curriculum, global_curriculum)
    policy_payload = read_json(Path(args.policy)) if args.policy else {}
    out_dir = Path(args.out_dir)
    deployment_bucket = resolve_deployment_bucket(curriculum, args.deployment_bucket)

    emit_contract(curriculum, out_dir / "teacher_package_contract.csv", deployment_bucket, policy_payload)
    emit_manifest(curriculum, out_dir / "teacher_package_manifest_latest.json", deployment_bucket, policy_payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
