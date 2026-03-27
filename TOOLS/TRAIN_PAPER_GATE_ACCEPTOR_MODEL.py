from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Sequence

from mb_ml_core.paths import CompatPaths
from mb_ml_core.trainer import (
    TrainingThresholds,
    train_all_symbol_models,
    train_global_model,
    train_symbol_model,
    write_training_audits,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Trenuje paper_gate_acceptor 1:1 dla MAKRO_I_MIKRO_BOT: model globalny i/lub lokalne modele per symbol."
    )
    parser.add_argument("--project-root", default=r"C:\MAKRO_I_MIKRO_BOT")
    parser.add_argument("--research-root", default=r"C:\TRADING_DATA\RESEARCH")
    parser.add_argument("--common-state-root", default=None)
    parser.add_argument(
        "--mode",
        choices=("global", "symbols", "full", "symbol"),
        default="global",
        help="global = tylko nauczyciel globalny, symbols = wszyscy uczniowie lokalni, full = global + lokalni, symbol = pojedynczy symbol",
    )
    parser.add_argument("--symbol", default=None, help="Pojedynczy symbol dla --mode symbol.")
    parser.add_argument("--symbols", nargs="*", default=None, help="Lista symboli dla --mode symbols lub full.")
    parser.add_argument("--export-onnx", action="store_true")
    parser.add_argument("--global-train-days", type=int, default=45)
    parser.add_argument("--global-valid-days", type=int, default=5)
    parser.add_argument("--global-step-days", type=int, default=5)
    parser.add_argument("--embargo-minutes", type=int, default=10)
    parser.add_argument("--min-train-rows", type=int, default=250)
    parser.add_argument("--min-valid-rows", type=int, default=50)
    parser.add_argument("--min-symbol-labeled-rows", type=int, default=120)
    parser.add_argument("--min-symbol-train-rows", type=int, default=50)
    parser.add_argument("--min-symbol-valid-rows", type=int, default=20)
    parser.add_argument("--min-gate-probability", type=float, default=0.53)
    parser.add_argument("--min-decision-score-pln", type=float, default=0.0)
    parser.add_argument("--max-spread-points", type=float, default=999.0)
    parser.add_argument("--max-runtime-latency-us", type=float, default=250000.0)
    parser.add_argument("--max-server-ping-ms", type=float, default=35.0)
    return parser.parse_args()


def build_thresholds(args: argparse.Namespace) -> TrainingThresholds:
    return TrainingThresholds(
        global_train_days=args.global_train_days,
        global_valid_days=args.global_valid_days,
        global_step_days=args.global_step_days,
        embargo_minutes=args.embargo_minutes,
        min_train_rows=args.min_train_rows,
        min_valid_rows=args.min_valid_rows,
        min_symbol_labeled_rows=args.min_symbol_labeled_rows,
        min_symbol_train_rows=args.min_symbol_train_rows,
        min_symbol_valid_rows=args.min_symbol_valid_rows,
        min_gate_probability=args.min_gate_probability,
        min_decision_score_pln=args.min_decision_score_pln,
        max_spread_points=args.max_spread_points,
        max_runtime_latency_us=args.max_runtime_latency_us,
        max_server_ping_ms=args.max_server_ping_ms,
    )


def main() -> int:
    args = parse_args()
    paths = CompatPaths.create(
        project_root=args.project_root,
        research_root=args.research_root,
        common_state_root=args.common_state_root,
    )
    thresholds = build_thresholds(args)

    payload: dict[str, object] = {
        "mode": args.mode,
        "project_root": str(paths.project_root),
        "research_root": str(paths.research_root),
    }

    global_payload = None
    symbol_payload = None

    if args.mode in {"global", "full", "symbols"} and args.mode != "symbols":
        global_payload = train_global_model(paths, export_onnx=args.export_onnx, thresholds=thresholds)
        payload["global"] = global_payload

    if args.mode == "global":
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return 0

    if args.mode == "symbol":
        if not args.symbol:
            raise SystemExit("--mode symbol wymaga --symbol")
        if global_payload is None:
            # potrzebny model globalny jako teacher
            global_payload = train_global_model(paths, export_onnx=args.export_onnx, thresholds=thresholds)
            payload["global"] = global_payload
        single = train_symbol_model(paths, symbol=args.symbol, export_onnx=args.export_onnx, thresholds=thresholds)
        symbol_payload = {"symbols": {args.symbol: single}}
        payload["symbols"] = symbol_payload
        payload["audits"] = write_training_audits(paths, global_payload, symbol_payload)
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return 0

    if global_payload is None:
        global_metrics_path = Path(paths.global_model_dir) / "paper_gate_acceptor_latest_metrics.json"
        global_model_path = Path(paths.global_model_dir) / "paper_gate_acceptor_latest.joblib"
        if args.mode == "symbols" and global_metrics_path.exists() and global_model_path.exists():
            global_payload = json.loads(global_metrics_path.read_text(encoding="utf-8"))
            if isinstance(global_payload, dict):
                global_payload["reused_existing_model"] = True
            payload["global"] = global_payload
        else:
            global_payload = train_global_model(paths, export_onnx=args.export_onnx, thresholds=thresholds)
            payload["global"] = global_payload

    all_symbols = train_all_symbol_models(paths, export_onnx=args.export_onnx, thresholds=thresholds)
    if args.symbols:
        selected = {symbol: all_symbols["symbols"][symbol] for symbol in args.symbols if symbol in all_symbols["symbols"]}
        symbol_payload = {"symbols": selected, "registry_path": all_symbols["registry_path"]}
    else:
        symbol_payload = all_symbols

    payload["symbols"] = symbol_payload
    payload["audits"] = write_training_audits(paths, global_payload, symbol_payload)
    print(json.dumps(payload, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
