from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, Tuple


DEFAULT_ROOT = Path(r"C:\OANDA_MT5_SYSTEM")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _resolve_paths(root: Path) -> Dict[str, Path]:
    obs_root = root / "OBSERVERS_IMPLEMENTATION_CANDIDATE"
    return {
        "root": root,
        "obs_root": obs_root,
        "status_out": obs_root / "outputs" / "operator" / "agent_refresh_last.json",
    }


def _build_runtime(root: Path) -> Tuple[Any, Dict[str, Any]]:
    sys.path.insert(0, str(root))
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

    paths = Paths.from_workspace(root)
    paths.ensure_roots_exist()
    ro = ReadOnlyDataAdapter(paths)
    out = ObserverOutputWriter(paths)
    validator = DataContractValidator()

    agents: Dict[str, Any] = {
        "agent_informacyjny": OperationsMonitoringAgent(ro, out, validator),
        "agent_rozwoju_scalpingu": ScalpingRDAgent(ro, out, validator),
        "agent_rekomendacyjny": ImprovementRecommendationAgent(ro, out, validator),
        "agent_straznik_spojnosci": ConsistencyGuardianAgent(ro, out, validator),
    }
    return paths, agents


def _iter_targets(agent_arg: str, all_agents: Iterable[str]) -> Iterable[str]:
    if str(agent_arg).strip().lower() == "all":
        return list(all_agents)
    return [str(agent_arg).strip()]


def _run_single(agent_key: str, agent_obj: Any) -> Dict[str, Any]:
    started = utc_now()
    try:
        result = agent_obj.run_cycle()
        return {
            "agent": agent_key,
            "status": "PASS",
            "started_at_utc": started,
            "finished_at_utc": utc_now(),
            "result": result,
        }
    except Exception as exc:  # pragma: no cover - diagnostic path
        return {
            "agent": agent_key,
            "status": "FAIL",
            "started_at_utc": started,
            "finished_at_utc": utc_now(),
            "error": f"{type(exc).__name__}: {exc}",
        }


def _write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Run observer agent(s) once on persisted data.")
    p.add_argument("--root", default=str(DEFAULT_ROOT))
    p.add_argument(
        "--agent",
        default="all",
        help="agent key or 'all' (agent_informacyjny, agent_rozwoju_scalpingu, agent_rekomendacyjny, agent_straznik_spojnosci)",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    paths = _resolve_paths(Path(args.root).resolve())
    root = paths["root"]

    _, agents = _build_runtime(root)
    targets = list(_iter_targets(str(args.agent), agents.keys()))
    invalid = [a for a in targets if a not in agents]
    if invalid:
        out = {
            "schema_version": "oanda_mt5.observers.agent_refresh.v1",
            "generated_at_utc": utc_now(),
            "workspace_root_path": str(root),
            "status": "FAIL",
            "error": f"UNKNOWN_AGENT: {','.join(invalid)}",
            "valid_agents": sorted(agents.keys()),
        }
        _write_json(paths["status_out"], out)
        print(json.dumps(out, ensure_ascii=False))
        return 2

    rows = [_run_single(agent_key, agents[agent_key]) for agent_key in targets]
    status = "PASS" if all(str(r.get("status")) == "PASS" for r in rows) else "PARTIAL_FAIL"
    out = {
        "schema_version": "oanda_mt5.observers.agent_refresh.v1",
        "generated_at_utc": utc_now(),
        "workspace_root_path": str(root),
        "status": status,
        "requested_agent": str(args.agent),
        "runs": rows,
    }
    _write_json(paths["status_out"], out)
    print(json.dumps(out, ensure_ascii=False))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
