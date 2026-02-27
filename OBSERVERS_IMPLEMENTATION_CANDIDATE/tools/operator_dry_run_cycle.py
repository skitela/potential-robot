from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


WORKSPACE_ROOT = Path(r"C:\OANDA_MT5_SYSTEM")
OBS_ROOT = WORKSPACE_ROOT / "OBSERVERS_IMPLEMENTATION_CANDIDATE"

# Local package import without installation.
sys.path.insert(0, str(WORKSPACE_ROOT))

from OBSERVERS_IMPLEMENTATION_CANDIDATE.agent_informacyjny.agent_ops_monitor import (  # noqa: E402
    OperationsMonitoringAgent,
)
from OBSERVERS_IMPLEMENTATION_CANDIDATE.agent_rekomendacyjny.agent_recommendations import (  # noqa: E402
    ImprovementRecommendationAgent,
)
from OBSERVERS_IMPLEMENTATION_CANDIDATE.agent_rozwoju_scalpingu.agent_scalping_rd import (  # noqa: E402
    ScalpingRDAgent,
)
from OBSERVERS_IMPLEMENTATION_CANDIDATE.agent_straznik_spojnosci.agent_consistency_guardian import (  # noqa: E402
    ConsistencyGuardianAgent,
)
from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.outputs import ObserverOutputWriter  # noqa: E402
from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.paths import Paths  # noqa: E402
from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.readonly_adapter import ReadOnlyDataAdapter  # noqa: E402
from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.validators import DataContractValidator  # noqa: E402


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _snapshot_outputs(outputs_root: Path) -> set[str]:
    if not outputs_root.exists():
        return set()
    return {str(p.resolve()) for p in outputs_root.rglob("*") if p.is_file()}


def _is_under(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def run() -> dict[str, Any]:
    paths = Paths.from_workspace(WORKSPACE_ROOT)
    paths.ensure_roots_exist()
    ro = ReadOnlyDataAdapter(paths)
    out = ObserverOutputWriter(paths)
    validator = DataContractValidator()

    agents: list[tuple[str, Any]] = [
        ("agent_informacyjny", OperationsMonitoringAgent(ro, out, validator)),
        ("agent_rozwoju_scalpingu", ScalpingRDAgent(ro, out, validator)),
        ("agent_rekomendacyjny", ImprovementRecommendationAgent(ro, out, validator)),
        ("agent_straznik_spojnosci", ConsistencyGuardianAgent(ro, out, validator)),
    ]

    before = _snapshot_outputs(paths.outputs_root)
    runs: list[dict[str, Any]] = []

    for name, agent in agents:
        started = utc_now()
        try:
            result = agent.run_cycle()
            runs.append(
                {
                    "agent": name,
                    "status": "PASS",
                    "started_at_utc": started,
                    "finished_at_utc": utc_now(),
                    "result": result,
                }
            )
        except Exception as exc:  # pragma: no cover - diagnostic path
            runs.append(
                {
                    "agent": name,
                    "status": "FAIL",
                    "started_at_utc": started,
                    "finished_at_utc": utc_now(),
                    "error": str(exc),
                }
            )

    after = _snapshot_outputs(paths.outputs_root)
    created = sorted(after - before)
    outside = [p for p in created if not _is_under(Path(p), paths.outputs_root)]

    status = "PASS" if all(r["status"] == "PASS" for r in runs) and not outside else "REVIEW_REQUIRED"
    return {
        "schema_version": "oanda_mt5.observers.operator_dry_run.v1",
        "generated_at_utc": utc_now(),
        "workspace_root_path": str(WORKSPACE_ROOT),
        "observers_root_path": str(OBS_ROOT),
        "status": status,
        "agent_runs": runs,
        "created_output_files": created,
        "write_boundary_outside_outputs": outside,
        "notes": [
            "Dry-run only, no runtime integration.",
            "Read persisted data only.",
            "No SafetyBot/EA/bridge mutation.",
        ],
    }


def main() -> int:
    report = run()
    out_dir = OBS_ROOT / "docs" / "onboarding"
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    json_path = out_dir / f"operator_dry_run_cycle_{stamp}.json"
    txt_path = out_dir / f"operator_dry_run_cycle_{stamp}.txt"
    json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "OPERATOR DRY RUN CYCLE",
        f"generated_at_utc: {report['generated_at_utc']}",
        f"workspace_root_path: {report['workspace_root_path']}",
        f"status: {report['status']}",
        "",
    ]
    for row in report["agent_runs"]:
        lines.append(
            f"- {row['agent']}: {row['status']}"
            + (f" | error={row['error']}" if row["status"] != "PASS" else "")
        )
    lines.append("")
    lines.append(f"created_output_files: {len(report['created_output_files'])}")
    lines.append(f"write_boundary_outside_outputs: {len(report['write_boundary_outside_outputs'])}")
    txt_path.write_text("\n".join(lines), encoding="utf-8")

    print(f"WORKSPACE_ROOT_PATH: {WORKSPACE_ROOT}")
    print(f"REPORT_JSON_PATH: {json_path}")
    print(f"REPORT_TXT_PATH: {txt_path}")
    print(f"VERDICT: {report['status']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
