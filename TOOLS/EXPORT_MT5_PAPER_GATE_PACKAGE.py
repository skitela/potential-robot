from __future__ import annotations

import argparse
import json
from pathlib import Path

from mb_ml_core.io_utils import ensure_dir, write_json
from mb_ml_core.paths import CompatPaths
from mb_ml_core.registry import load_active_symbols
from mb_ml_core.trainer import train_all_symbol_models, train_global_model, TrainingThresholds


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Buduje pakiet eksportowy MT5/ONNX z istniejących artefaktów paper_gate_acceptor 1:1."
    )
    parser.add_argument("--project-root", default=r"C:\MAKRO_I_MIKRO_BOT")
    parser.add_argument("--research-root", default=r"C:\TRADING_DATA\RESEARCH")
    parser.add_argument("--common-state-root", default=None)
    parser.add_argument("--bootstrap-if-missing", action="store_true", help="Jeżeli brakuje modeli, uruchom trening globalny i lokalny.")
    parser.add_argument("--export-onnx", action="store_true")
    return parser.parse_args()


def _load_registry_payload(path: Path) -> dict:
    if not path.exists():
        return {"schema_version": "1.0", "symbols": {}}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {"schema_version": "1.0", "symbols": {}}
    return payload if isinstance(payload, dict) else {"schema_version": "1.0", "symbols": {}}


def _scan_symbol_entry(paths: CompatPaths, symbol: str) -> dict:
    model_dir = paths.symbol_models_dir / symbol
    metrics_path_obj = model_dir / "paper_gate_acceptor_latest_metrics.json"
    report_path_obj = model_dir / "paper_gate_acceptor_report_latest.md"
    onnx_path_obj = model_dir / "paper_gate_acceptor_latest.onnx"
    joblib_path_obj = model_dir / "paper_gate_acceptor_latest.joblib"

    metrics_payload: dict = {}
    if metrics_path_obj.exists():
        try:
            loaded = json.loads(metrics_path_obj.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                metrics_payload = loaded
        except Exception:
            metrics_payload = {}

    artifacts = metrics_payload.get("artifacts", {}) if isinstance(metrics_payload.get("artifacts"), dict) else {}
    onnx_path = str(artifacts.get("student_gate", {}).get("onnx") or (onnx_path_obj if onnx_path_obj.exists() else ""))
    joblib_path = str(artifacts.get("student_gate", {}).get("joblib") or (joblib_path_obj if joblib_path_obj.exists() else ""))
    metrics_path = str(metrics_path_obj if metrics_path_obj.exists() else "")
    report_path = str(report_path_obj if report_path_obj.exists() else "")

    local_model_available = bool(onnx_path or joblib_path)
    training_mode = str(metrics_payload.get("training_mode", "LOCAL_TRAINING_LIMITED" if local_model_available else "FALLBACK_ONLY"))

    return {
        "symbol_alias": symbol,
        "model_dir": str(model_dir),
        "training_mode": training_mode,
        "local_model_available": local_model_available,
        "metrics": metrics_payload.get("metrics", {}) if isinstance(metrics_payload.get("metrics"), dict) else {},
        "promotion": metrics_payload.get("promotion", {}) if isinstance(metrics_payload.get("promotion"), dict) else {},
        "labeled_rows": int(metrics_payload.get("labeled_rows", 0) or 0),
        "candidate_rows": int(metrics_payload.get("candidate_rows", 0) or 0),
        "artifacts": {
            "joblib_path": joblib_path,
            "onnx_path": onnx_path,
            "metrics_path": metrics_path,
            "report_path": report_path,
        },
    }


def _build_registry_payload(symbol_payload: dict[str, dict]) -> dict:
    items = []
    for symbol, entry in symbol_payload.items():
        metrics = entry.get("metrics", {}) if isinstance(entry.get("metrics"), dict) else {}
        promotion = entry.get("promotion", {}) if isinstance(entry.get("promotion"), dict) else {}
        training_mode = str(entry.get("training_mode", "FALLBACK_ONLY"))
        local_model_available = bool(entry.get("local_model_available", False))
        labeled_rows = int(entry.get("labeled_rows", 0) or 0)
        positive_rate = float(metrics.get("positive_rate_actual", 0.0) or 0.0)
        positive_rows = max(0, int(round(labeled_rows * positive_rate)))
        negative_rows = max(0, labeled_rows - positive_rows)
        status = "MODEL_PER_SYMBOL_READY" if local_model_available and training_mode != "FALLBACK_ONLY" else "GLOBAL_FALLBACK"
        items.append(
            {
                "symbol": symbol,
                "symbol_alias": symbol,
                "status": status,
                "fallback_scope": "GLOBAL_MODEL" if status == "GLOBAL_FALLBACK" else "",
                "reason": "; ".join(str(x) for x in promotion.get("reasons", [])) if status == "GLOBAL_FALLBACK" else training_mode,
                "rows_total": labeled_rows,
                "candidate_rows": int(entry.get("candidate_rows", 0) or 0),
                "positive_rows": positive_rows,
                "negative_rows": negative_rows,
                "roc_auc": float(metrics.get("roc_auc_median", metrics.get("roc_auc", 0.0)) or 0.0),
                "balanced_accuracy": float(metrics.get("balanced_accuracy_median", metrics.get("balanced_accuracy", 0.0)) or 0.0),
                "teacher_enabled": status == "MODEL_PER_SYMBOL_READY",
                "data_source": "BROKER_NET_LEDGER",
                "onnx_path": entry.get("artifacts", {}).get("onnx_path") or None,
                "joblib_path": entry.get("artifacts", {}).get("joblib_path") or None,
                "metrics_path": entry.get("artifacts", {}).get("metrics_path") or None,
                "training_mode": training_mode,
                "promotion_approved": bool(promotion.get("approved", False)),
            }
        )

    ready_count = sum(1 for item in items if item["status"] == "MODEL_PER_SYMBOL_READY")
    return {
        "generated_at_local": __import__("datetime").datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": __import__("datetime").datetime.utcnow().isoformat(),
        "total_symbols": len(items),
        "ready_count": ready_count,
        "fallback_count": len(items) - ready_count,
        "trained_now_count": ready_count,
        "items": items,
        "symbols": {item["symbol"]: item for item in items},
    }


def _build_symbol_payload(paths: CompatPaths, active_symbols: list[str]) -> dict[str, dict]:
    registry = _load_registry_payload(paths.onnx_symbol_registry_latest)
    registry_alt = _load_registry_payload(paths.onnx_symbol_registry_latest_alt)
    registry_symbols = registry.get("symbols", {}) if isinstance(registry.get("symbols"), dict) else {}
    registry_alt_symbols = registry_alt.get("symbols", {}) if isinstance(registry_alt.get("symbols"), dict) else {}

    out: dict[str, dict] = {}
    for symbol in active_symbols:
        entry = _scan_symbol_entry(paths, symbol)
        for source in (registry_symbols, registry_alt_symbols):
            existing = source.get(symbol)
            if isinstance(existing, dict):
                merged = dict(existing)
                merged.setdefault("symbol_alias", symbol)
                merged.setdefault("training_mode", entry["training_mode"])
                merged.setdefault("local_model_available", entry["local_model_available"])
                merged_artifacts = dict(existing.get("artifacts") or {})
                for key, value in entry["artifacts"].items():
                    if not merged_artifacts.get(key) and value:
                        merged_artifacts[key] = value
                merged["artifacts"] = merged_artifacts
                entry = merged
                break
        out[symbol] = entry
    return out


def main() -> int:
    args = parse_args()
    paths = CompatPaths.create(
        project_root=args.project_root,
        research_root=args.research_root,
        common_state_root=args.common_state_root,
    )

    global_joblib = paths.global_model_dir / "paper_gate_acceptor_latest.joblib"
    registry_path = paths.onnx_symbol_registry_latest

    if args.bootstrap_if_missing and (not global_joblib.exists() or not registry_path.exists()):
        thresholds = TrainingThresholds()
        train_global_model(paths, export_onnx=args.export_onnx, thresholds=thresholds)
        train_all_symbol_models(paths, export_onnx=args.export_onnx, thresholds=thresholds)

    active_symbols = load_active_symbols(paths)
    symbol_payload = _build_symbol_payload(paths, active_symbols)

    package = {
        "schema_version": "1.0",
        "project_root": str(paths.project_root),
        "research_root": str(paths.research_root),
        "global_model_path": str(paths.global_model_dir / "paper_gate_acceptor_latest.onnx"),
        "global_model_joblib": str(paths.global_model_dir / "paper_gate_acceptor_latest.joblib"),
        "global_metrics_path": str(paths.global_model_dir / "paper_gate_acceptor_latest_metrics.json"),
        "onnx_symbol_registry_latest": str(paths.onnx_symbol_registry_latest),
        "onnx_symbol_registry_latest_alt": str(paths.onnx_symbol_registry_latest_alt),
        "symbols": symbol_payload,
        "notes": [
            "Pakiet zachowuje istniejące nazwy paper_gate_acceptor i paper_gate_acceptor_by_symbol.",
            "Runtime MT5 powinien czytać teacher z paper_gate_acceptor_latest.onnx albo fallback do joblib po stronie research.",
            "Każdy symbol ma własne artefakty gate/edge/fill/slippage, o ile trening nie wypadł do trybu FALLBACK_ONLY.",
        ],
    }

    out_path = ensure_dir(paths.models_dir) / "paper_gate_acceptor_mt5_package_latest.json"
    write_json(out_path, package)
    registry_payload = _build_registry_payload(symbol_payload)
    write_json(paths.onnx_symbol_registry_latest, registry_payload)
    write_json(paths.onnx_symbol_registry_latest_alt, registry_payload)
    write_json(paths.evidence_onnx_symbol_registry_latest, registry_payload)
    print(json.dumps({"output_path": str(out_path), "symbols": len(package["symbols"])}, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
