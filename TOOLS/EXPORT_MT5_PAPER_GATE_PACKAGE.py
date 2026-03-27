from __future__ import annotations

import argparse
import json
from pathlib import Path

from mb_ml_core.io_utils import ensure_dir, write_json
from mb_ml_core.paths import CompatPaths
from mb_ml_core.registry import build_symbol_readiness, load_active_symbols
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

    if registry_path.exists():
        registry = json.loads(registry_path.read_text(encoding="utf-8"))
    else:
        registry = {"schema_version": "1.0", "symbols": {}}

    package = {
        "schema_version": "1.0",
        "project_root": str(paths.project_root),
        "research_root": str(paths.research_root),
        "global_model_path": str(paths.global_model_dir / "paper_gate_acceptor_latest.onnx"),
        "global_model_joblib": str(paths.global_model_dir / "paper_gate_acceptor_latest.joblib"),
        "global_metrics_path": str(paths.global_model_dir / "paper_gate_acceptor_latest_metrics.json"),
        "onnx_symbol_registry_latest": str(paths.onnx_symbol_registry_latest),
        "onnx_symbol_registry_latest_alt": str(paths.onnx_symbol_registry_latest_alt),
        "symbols": registry.get("symbols", {}),
        "notes": [
            "Pakiet zachowuje istniejące nazwy paper_gate_acceptor i paper_gate_acceptor_by_symbol.",
            "Runtime MT5 powinien czytać teacher z paper_gate_acceptor_latest.onnx albo fallback do joblib po stronie research.",
            "Każdy symbol ma własne artefakty gate/edge/fill/slippage, o ile trening nie wypadł do trybu FALLBACK_ONLY.",
        ],
    }

    out_path = ensure_dir(paths.models_dir) / "paper_gate_acceptor_mt5_package_latest.json"
    write_json(out_path, package)
    print(json.dumps({"output_path": str(out_path), "symbols": len(package["symbols"])}, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
