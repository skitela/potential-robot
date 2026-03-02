#!/usr/bin/env python3
"""
Apply staged strategy influence phases in CONFIG/strategy.json.

This tool only updates feature-flag modes and advisory weights.
It does not change entry/exit strategy formulas.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, UTC
from pathlib import Path
from typing import Any, Dict


PHASES = {
    "phase0_shadow": {
        "session_liquidity_gate_mode": "SHADOW_ONLY",
        "cost_microstructure_gate_mode": "SHADOW_ONLY",
        "candle_adapter_mode": "SHADOW_ONLY",
        "renko_adapter_mode": "SHADOW_ONLY",
    },
    "phase1_advisory": {
        "session_liquidity_gate_mode": "SHADOW_ONLY",
        "cost_microstructure_gate_mode": "SHADOW_ONLY",
        "candle_adapter_mode": "ADVISORY_SCORE",
        "renko_adapter_mode": "ADVISORY_SCORE",
        # Conservative weights for first live influence step.
        "candle_adapter_score_weight": 2.0,
        "renko_adapter_score_weight": 1.5,
    },
    "phase2_session_enforce": {
        "session_liquidity_gate_mode": "GATE_ENFORCE",
        "cost_microstructure_gate_mode": "SHADOW_ONLY",
        "candle_adapter_mode": "ADVISORY_SCORE",
        "renko_adapter_mode": "ADVISORY_SCORE",
        "candle_adapter_score_weight": 2.0,
        "renko_adapter_score_weight": 1.5,
    },
    "phase3_full_enforce": {
        "session_liquidity_gate_mode": "GATE_ENFORCE",
        "cost_microstructure_gate_mode": "GATE_ENFORCE",
        "candle_adapter_mode": "ADVISORY_SCORE",
        "renko_adapter_mode": "ADVISORY_SCORE",
        "candle_adapter_score_weight": 2.0,
        "renko_adapter_score_weight": 1.5,
    },
}


def _load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _dump_json(path: Path, payload: Dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")


def _backup(path: Path) -> Path:
    ts = datetime.now(UTC).strftime("%Y%m%d_%H%M%SZ")
    backup_path = path.with_name(f"{path.stem}.backup_{ts}{path.suffix}")
    backup_path.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    return backup_path


def apply_phase(path: Path, phase: str) -> Dict[str, Any]:
    cfg = _load_json(path)
    patch = PHASES[phase]
    cfg.update(patch)
    _dump_json(path, cfg)
    return patch


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Apply staged strategy feature-flag phase.")
    p.add_argument(
        "--phase",
        choices=sorted(PHASES.keys()),
        default="phase1_advisory",
        help="Rollout phase to apply.",
    )
    p.add_argument(
        "--strategy",
        default="CONFIG/strategy.json",
        help="Path to strategy.json",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Print resulting values without writing.",
    )
    return p


def main() -> int:
    ap = _build_parser()
    args = ap.parse_args()
    strategy_path = Path(args.strategy).resolve()
    if not strategy_path.exists():
        print(f"ERROR: strategy file not found: {strategy_path}")
        return 2
    patch = PHASES[args.phase]
    if args.dry_run:
        print(json.dumps({"phase": args.phase, "strategy": str(strategy_path), "changes": patch}, indent=2))
        return 0
    backup_path = _backup(strategy_path)
    applied = apply_phase(strategy_path, args.phase)
    print(json.dumps({"phase": args.phase, "strategy": str(strategy_path), "backup": str(backup_path), "changes": applied}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
