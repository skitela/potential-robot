from __future__ import annotations

import argparse
import json

from mb_ml_core.adapter import build_server_parity_tail_bridge
from mb_ml_core.paths import CompatPaths


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Buduje most świeżego ogona serwerowego 1:1 dla MAKRO_I_MIKRO_BOT.")
    parser.add_argument("--project-root", default=r"C:\MAKRO_I_MIKRO_BOT")
    parser.add_argument("--research-root", default=r"C:\TRADING_DATA\RESEARCH")
    parser.add_argument("--common-state-root", default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    paths = CompatPaths.create(
        project_root=args.project_root,
        research_root=args.research_root,
        common_state_root=args.common_state_root,
    )
    _, summary = build_server_parity_tail_bridge(paths)
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
