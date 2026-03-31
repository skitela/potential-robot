from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


DEFAULT_PROJECT_ROOT = Path(r"C:\MAKRO_I_MIKRO_BOT")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Builds dry-run runtime package manifest.")
    parser.add_argument("--project-root", default=str(DEFAULT_PROJECT_ROOT))
    parser.add_argument("--model-path", default="")
    parser.add_argument("--feature-contract-path", default="")
    parser.add_argument("--thresholds-path", default="")
    parser.add_argument("--apply", action="store_true")
    return parser.parse_args()


def file_info(path_str: str) -> Dict[str, Any]:
    if not path_str:
        return {"path": "", "present": False, "size_bytes": 0, "sha256": ""}
    path = Path(path_str)
    if not path.exists():
        return {"path": str(path), "present": False, "size_bytes": 0, "sha256": ""}
    payload = path.read_bytes()
    return {
        "path": str(path),
        "present": True,
        "size_bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
    }


def main() -> int:
    args = parse_args()
    project_root = Path(args.project_root)
    ops_root = project_root / "EVIDENCE" / "OPS"
    ops_root.mkdir(parents=True, exist_ok=True)

    manifest = {
        "schema_version": "1.0",
        "generated_at_local": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "dry_run": not args.apply,
        "action": "DRY_RUN_ONLY" if not args.apply else "MANIFEST_ONLY",
        "package": {
            "model": file_info(args.model_path),
            "feature_contract": file_info(args.feature_contract_path),
            "thresholds": file_info(args.thresholds_path),
        },
    }

    out_path = ops_root / "runtime_package_manifest_latest.json"
    out_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"WROTE {out_path} dry_run={str(not args.apply).lower()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
