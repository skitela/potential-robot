from __future__ import annotations

import argparse
import json

from mb_ml_supervision.audits import write_outcome_closure_audit
from mb_ml_supervision.paths import OverlayPaths


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Buduje audyt domkniecia outcome i prawdy broker-net dla aktywnej floty."
    )
    parser.add_argument("--project-root", default=r"C:\MAKRO_I_MIKRO_BOT")
    parser.add_argument("--research-root", default=r"C:\TRADING_DATA\RESEARCH")
    parser.add_argument("--common-state-root", default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    paths = OverlayPaths.create(
        project_root=args.project_root,
        research_root=args.research_root,
        common_state_root=args.common_state_root,
    )
    payload = write_outcome_closure_audit(paths)
    print(json.dumps(payload, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
