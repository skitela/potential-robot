from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


DEFAULT_PROJECT_ROOT = Path(r"C:\MAKRO_I_MIKRO_BOT")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Exports compact Codex workbench snapshot.")
    parser.add_argument("--project-root", default=str(DEFAULT_PROJECT_ROOT))
    return parser.parse_args()


def read_json(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main() -> int:
    args = parse_args()
    project_root = Path(args.project_root)
    ops_root = project_root / "EVIDENCE" / "OPS"

    control_state = read_json(ops_root / "control_state_latest.json")
    health_matrix = read_json(ops_root / "symbol_health_matrix_latest.json")
    action_plan = read_json(ops_root / "control_action_plan_latest.json")
    learning_matrix = read_json(ops_root / "learning_supervisor_matrix_latest.json")
    learning_action_plan = read_json(ops_root / "learning_action_plan_latest.json")

    status_by_symbol = {item.get("symbol"): item for item in health_matrix.get("items", []) or []}
    action_by_symbol = {item.get("symbol"): item for item in action_plan.get("items", []) or []}
    learning_by_symbol = {item.get("symbol"): item for item in learning_matrix.get("items", []) or []}
    learning_action_by_symbol = {item.get("symbol"): item for item in learning_action_plan.get("items", []) or []}

    items = []
    for symbol_state in control_state.get("symbols", []) or []:
        symbol = symbol_state.get("symbol")
        items.append(
            {
                "symbol": symbol,
                "status": status_by_symbol.get(symbol, {}).get("status"),
                "reason": status_by_symbol.get(symbol, {}).get("reason"),
                "learning_blocker_class": learning_by_symbol.get(symbol, {}).get("blocker_class"),
                "learning_blocker_reason": learning_by_symbol.get(symbol, {}).get("blocker_reason"),
                "last_stage": ((symbol_state.get("learning_supervisor_snapshot") or {}).get("last_stage") or (symbol_state.get("supervisor_snapshot") or {}).get("last_stage")),
                "last_reason_code": ((symbol_state.get("learning_supervisor_snapshot") or {}).get("last_reason_code") or (symbol_state.get("supervisor_snapshot") or {}).get("last_reason_code")),
                "action": learning_action_by_symbol.get(symbol, {}).get("action", action_by_symbol.get(symbol, {}).get("action", "NO_OP")),
                "action_reason": learning_action_by_symbol.get(symbol, {}).get("action_reason", action_by_symbol.get(symbol, {}).get("action_reason", "MISSING_ACTION_PLAN")),
            }
        )

    payload = {
        "schema_version": "1.0",
        "generated_at_local": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "summary": {
            "symbol_count": len(items),
            "learning_symbols": [item["symbol"] for item in items if item["status"] == "RUNNING_LEARNING"],
            "problem_symbols": [
                item["symbol"]
                for item in items
                if item["status"] in {"RUNTIME_DOWN", "STALL_NO_LESSON", "MODEL_NOT_READY", "CONTRACT_MISSING"}
            ],
        },
        "items": items,
    }

    json_path = ops_root / "codex_workbench_latest.json"
    md_path = ops_root / "codex_workbench_latest.md"
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "# Codex Workbench",
        "",
        f"- generated_at_local: {payload['generated_at_local']}",
        f"- symbol_count: {payload['summary']['symbol_count']}",
        f"- learning_symbols: {', '.join(payload['summary']['learning_symbols']) if payload['summary']['learning_symbols'] else 'BRAK'}",
        f"- problem_symbols: {', '.join(payload['summary']['problem_symbols']) if payload['summary']['problem_symbols'] else 'BRAK'}",
        "",
        "## Symbols",
        "",
    ]
    for item in items:
        lines.append(
            f"- {item['symbol']}: status={item['status']}, reason={item['reason']}, "
            f"learning_class={item['learning_blocker_class']}, learning_reason={item['learning_blocker_reason']}, "
            f"last_stage={item['last_stage']}, action={item['action']}, action_reason={item['action_reason']}"
        )
    md_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"WROTE {json_path} and {md_path} symbols={len(items)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
