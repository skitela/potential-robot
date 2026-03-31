from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


DEFAULT_PROJECT_ROOT = Path(r"C:\MAKRO_I_MIKRO_BOT")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Builds read-only control action plan.")
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
    config_path = project_root / "CONFIG" / "control_policy_v1.json"

    health_matrix = read_json(ops_root / "symbol_health_matrix_latest.json")
    policy = read_json(config_path) if config_path.exists() else {}
    policy_loaded = bool(policy)
    policy_enabled = bool(policy.get("enabled")) if policy_loaded else False

    actions = []
    for item in health_matrix.get("items", []) or []:
        action = "NO_OP"
        action_reason = "DEFAULT_SAFE_NOOP"

        if policy_enabled:
            status = item.get("status")
            if status in {"RUNTIME_DOWN", "STALL_NO_LESSON"}:
                action = "REFRESH_AUDITS"
                action_reason = f"POLICY_REFRESH_FOR_{status}"
            elif status in {"CONTRACT_MISSING", "MODEL_NOT_READY"}:
                action = "REBUILD_PROFILE"
                action_reason = f"POLICY_REBUILD_FOR_{status}"

        actions.append(
            {
                "symbol": item.get("symbol"),
                "status": item.get("status"),
                "action": action,
                "action_reason": action_reason,
            }
        )

    payload = {
        "schema_version": "1.0",
        "generated_at_local": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "policy_path": str(config_path),
        "policy_loaded": policy_loaded,
        "policy_enabled": policy_enabled,
        "allowed_actions_v1": ["NO_OP", "REFRESH_AUDITS", "REBUILD_PROFILE"],
        "items": actions,
        "summary": {
            "symbol_count": len(actions),
            "no_op_count": sum(1 for row in actions if row["action"] == "NO_OP"),
            "refresh_audits_count": sum(1 for row in actions if row["action"] == "REFRESH_AUDITS"),
            "rebuild_profile_count": sum(1 for row in actions if row["action"] == "REBUILD_PROFILE"),
        },
    }

    out_path = ops_root / "control_action_plan_latest.json"
    out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"WROTE {out_path} symbols={len(actions)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
