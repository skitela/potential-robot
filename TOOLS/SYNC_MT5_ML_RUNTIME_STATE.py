from __future__ import annotations

import argparse
import json

from mb_ml_supervision.audits import AuditThresholds
from mb_ml_supervision.paths import OverlayPaths
from mb_ml_supervision.sync_runtime_state import sync_runtime_state


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Synchronizuje kontrakty student_gate_contract.csv do Common Files MT5."
    )
    parser.add_argument("--project-root", default=r"C:\MAKRO_I_MIKRO_BOT")
    parser.add_argument("--research-root", default=r"C:\TRADING_DATA\RESEARCH")
    parser.add_argument("--common-state-root", default=None)
    parser.add_argument("--min-outcome-rows-for-shadow-ready", type=int, default=50)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    paths = OverlayPaths.create(
        project_root=args.project_root,
        research_root=args.research_root,
        common_state_root=args.common_state_root,
    )
    payload = sync_runtime_state(
        paths,
        thresholds=AuditThresholds(min_outcome_rows_for_shadow_ready=args.min_outcome_rows_for_shadow_ready),
    )
    print(json.dumps(payload, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
