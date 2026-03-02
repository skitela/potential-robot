#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Dict, List


RUNTIME_METRICS_RE = re.compile(
    r"RUNTIME_METRICS_10M .*?scan_p50_ms=(?P<p50>\d+)\s+scan_p95_ms=(?P<p95>\d+)\s+scan_max_ms=(?P<pmax>\d+)"
)


def _utc_now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def _read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _last_runtime_metrics(log_path: Path, limit: int = 5000) -> Dict[str, Any]:
    if not log_path.exists():
        return {"status": "MISSING_LOG"}
    lines = log_path.read_text(encoding="utf-8", errors="ignore").splitlines()[-max(200, int(limit)) :]
    for line in reversed(lines):
        m = RUNTIME_METRICS_RE.search(line)
        if not m:
            continue
        return {
            "status": "OK",
            "line": line,
            "scan_p50_ms": int(m.group("p50")),
            "scan_p95_ms": int(m.group("p95")),
            "scan_max_ms": int(m.group("pmax")),
        }
    return {"status": "NOT_FOUND"}


def build_report(root: Path) -> Dict[str, Any]:
    system_status_path = root / "RUN" / "system_control_last.json"
    strategy_path = root / "CONFIG" / "strategy.json"
    safetybot_path = root / "BIN" / "safetybot.py"
    bridge_path = root / "BIN" / "zeromq_bridge.py"
    safety_log = root / "LOGS" / "safetybot.log"

    system = _read_json(system_status_path) if system_status_path.exists() else {}
    strategy = _read_json(strategy_path) if strategy_path.exists() else {}
    component_state = {
        str(c.get("name")): bool(c.get("running"))
        for c in (system.get("components") or [])
        if isinstance(c, dict)
    }
    all_stopped = all(not v for v in component_state.values()) if component_state else False

    section_map = [
        "tick_ingest",
        "session_gate",
        "cost_gate",
        "decision_core",
        "bridge_send",
        "bridge_wait",
        "io_log",
        "execution_call",
        "full_loop",
    ]
    runtime_last = _last_runtime_metrics(safety_log)

    freeze = {
        "session_liquidity_gate_mode": strategy.get("session_liquidity_gate_mode", "UNKNOWN"),
        "cost_microstructure_gate_mode": strategy.get("cost_microstructure_gate_mode", "UNKNOWN"),
        "candle_adapter_mode": strategy.get("candle_adapter_mode", "UNKNOWN"),
        "renko_adapter_mode": strategy.get("renko_adapter_mode", "UNKNOWN"),
        "candle_adapter_score_weight": strategy.get("candle_adapter_score_weight", "UNKNOWN"),
        "renko_adapter_score_weight": strategy.get("renko_adapter_score_weight", "UNKNOWN"),
        "execution_queue_submit_timeout_sec": strategy.get("execution_queue_submit_timeout_sec", "UNKNOWN"),
    }

    hashes = {}
    for p in [strategy_path, safetybot_path, bridge_path]:
        if p.exists():
            hashes[str(p)] = _sha256(p)

    return {
        "schema": "oanda_mt5.latency_stage1_baseline.v1",
        "ts_utc": _utc_now(),
        "workspace_root_path": str(root),
        "step": "STAGE_1_FREEZE_AND_BASELINE",
        "system_precondition": {
            "source": str(system_status_path),
            "all_components_stopped": all_stopped,
            "component_state": component_state,
            "confidence": "HIGH" if system_status_path.exists() else "LOW",
        },
        "hot_path_sections": section_map,
        "current_runtime_snapshot": runtime_last,
        "frozen_config_snapshot": freeze,
        "frozen_file_hashes_sha256": hashes,
        "target_latency_budget_ms": {
            "policy": "OPEN_DECISION",
            "note": "Budzety P95/P99 ustalic po etapie 2 (pomiar sekcyjny na aktywnym rynku).",
            "candidate_defaults": {
                "full_loop_p95_ms": "OPEN_DECISION",
                "full_loop_p99_ms": "OPEN_DECISION",
                "bridge_wait_p95_ms": "OPEN_DECISION",
            },
        },
        "next_step": "STAGE_2_SECTIONAL_PROFILING",
        "notes": [
            "Etap 1 nie zmienia strategii i nie wlacza tradingu.",
            "Celem jest zamrozenie punktu odniesienia przed profilingiem.",
        ],
    }


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Create stage-1 latency baseline/freeze report.")
    p.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    p.add_argument("--out", default="")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    report = build_report(root)
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    out = Path(args.out).resolve() if args.out else (root / "EVIDENCE" / "latency_stage1" / f"latency_stage1_baseline_{stamp}.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"LATENCY_STAGE1_BASELINE_OK out={out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
