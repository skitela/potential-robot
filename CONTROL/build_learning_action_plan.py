from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List


DEFAULT_PROJECT_ROOT = Path(r"C:\MAKRO_I_MIKRO_BOT")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build learning supervision action plan.")
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
    matrix = read_json(ops_root / "learning_supervisor_matrix_latest.json")
    policy = read_json(project_root / "CONFIG" / "learning_supervisor_policy_v1.json")

    rules = {
        str(rule.get("class") or ""): rule
        for rule in (policy.get("rules") or [])
        if str(rule.get("class") or "")
    }
    allowed_actions = set(policy.get("allowed_actions") or ["NO_OP"])
    default_action = str(policy.get("default_action") or "NO_OP")

    items: List[Dict[str, Any]] = []
    for item in matrix.get("items", []) or []:
        blocker_class = str(item.get("blocker_class") or "UNCLASSIFIED")
        rule = rules.get(blocker_class, {})
        action = str(rule.get("action") or default_action)
        if action not in allowed_actions:
            action = default_action
        items.append(
            {
                "symbol": item.get("symbol"),
                "blocker_class": blocker_class,
                "blocker_reason": item.get("blocker_reason"),
                "action": action,
                "action_reason": str(rule.get("reason") or "DEFAULT_POLICY"),
            }
        )

    payload = {
        "schema_version": "1.0",
        "generated_at_local": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "policy_enabled": bool(policy.get("enabled", False)),
        "allowed_actions": sorted(allowed_actions),
        "items": items,
        "summary": {
            "symbol_count": len(items),
            "no_op_count": sum(1 for item in items if item["action"] == "NO_OP"),
            "refresh_audits_count": sum(1 for item in items if item["action"] == "REFRESH_AUDITS"),
            "enable_diag_mode_count": sum(1 for item in items if item["action"] == "ENABLE_DIAG_MODE"),
            "restart_terminal_count": sum(1 for item in items if item["action"] == "RESTART_TERMINAL"),
            "rebuild_profile_count": sum(1 for item in items if item["action"] == "REBUILD_PROFILE"),
            "isolate_symbol_count": sum(1 for item in items if item["action"] == "ISOLATE_SYMBOL"),
        },
    }

    json_path = ops_root / "learning_action_plan_latest.json"
    md_path = ops_root / "learning_action_plan_latest.md"
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "# Learning Action Plan",
        "",
        f"- generated_at_local: {payload['generated_at_local']}",
        f"- policy_enabled: {str(payload['policy_enabled']).lower()}",
        "",
        "## Actions",
        "",
    ]
    for item in items:
        lines.append(f"- {item['symbol']}: class={item['blocker_class']}, action={item['action']}, reason={item['action_reason']}")
    md_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"WROTE {json_path} symbols={len(items)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
