from __future__ import annotations

import argparse
import json

from mb_ml_supervision.audits import AuditThresholds, write_overlay_audit
from mb_ml_supervision.paths import OverlayPaths


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Buduje audyt integracji overlay ML 1:1 dla MAKRO_I_MIKRO_BOT."
    )
    parser.add_argument("--project-root", default=r"C:\MAKRO_I_MIKRO_BOT")
    parser.add_argument("--research-root", default=r"C:\TRADING_DATA\RESEARCH")
    parser.add_argument("--common-state-root", default=None)
    parser.add_argument("--tail-freshness-hours", type=float, default=12.0)
    parser.add_argument("--ledger-freshness-hours", type=float, default=12.0)
    parser.add_argument("--package-freshness-hours", type=float, default=24.0)
    parser.add_argument("--min-labeled-rows-for-rollout", type=int, default=100)
    parser.add_argument("--min-outcome-rows-for-shadow-ready", type=int, default=50)
    parser.add_argument("--natural-drop-ratio-floor", type=float, default=0.85)
    parser.add_argument("--fail-on-rollout-block", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    paths = OverlayPaths.create(
        project_root=args.project_root,
        research_root=args.research_root,
        common_state_root=args.common_state_root,
    )
    thresholds = AuditThresholds(
        tail_freshness_hours=args.tail_freshness_hours,
        ledger_freshness_hours=args.ledger_freshness_hours,
        package_freshness_hours=args.package_freshness_hours,
        min_labeled_rows_for_rollout=args.min_labeled_rows_for_rollout,
        min_outcome_rows_for_shadow_ready=args.min_outcome_rows_for_shadow_ready,
        natural_drop_ratio_floor=args.natural_drop_ratio_floor,
    )
    payload = write_overlay_audit(paths, thresholds=thresholds)
    print(json.dumps(payload, indent=2, ensure_ascii=False))
    if args.fail_on_rollout_block and payload["summary"]["rollout_blocked"]:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
