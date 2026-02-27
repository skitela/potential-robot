from __future__ import annotations

import argparse
import ctypes
import json
import sys
import threading
import time
from dataclasses import dataclass
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
from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.operator_alerts import (  # noqa: E402
    alert_identity,
    extract_alert_summary,
    should_popup_alert,
)
from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.outputs import ObserverOutputWriter  # noqa: E402
from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.paths import Paths  # noqa: E402
from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.readonly_adapter import ReadOnlyDataAdapter  # noqa: E402
from OBSERVERS_IMPLEMENTATION_CANDIDATE.common.validators import DataContractValidator  # noqa: E402


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)


def append_jsonl(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(payload, ensure_ascii=False))
        f.write("\n")


def show_popup_async(title: str, message: str) -> None:
    def _run() -> None:
        try:
            # Icon warning + system modal.
            ctypes.windll.user32.MessageBoxW(0, message, title, 0x30 | 0x1000)
        except Exception:
            # Never crash service due to UI call.
            pass

    t = threading.Thread(target=_run, daemon=True)
    t.start()


@dataclass
class SchedulerState:
    last_ops: float = 0.0
    last_guardian: float = 0.0
    last_rd_rec: float = 0.0


def build_runtime(ops_every_sec: int, guardian_every_sec: int, rd_rec_every_sec: int) -> dict[str, Any]:
    paths = Paths.from_workspace(WORKSPACE_ROOT)
    paths.ensure_roots_exist()
    ro = ReadOnlyDataAdapter(paths)
    out = ObserverOutputWriter(paths)
    validator = DataContractValidator()
    return {
        "paths": paths,
        "ops": OperationsMonitoringAgent(ro, out, validator),
        "guardian": ConsistencyGuardianAgent(ro, out, validator),
        "rd": ScalpingRDAgent(ro, out, validator),
        "rec": ImprovementRecommendationAgent(ro, out, validator),
        "state": SchedulerState(),
        "intervals": {
            "ops_every_sec": int(ops_every_sec),
            "guardian_every_sec": int(guardian_every_sec),
            "rd_rec_every_sec": int(rd_rec_every_sec),
        },
    }


def collect_output_counts(outputs_root: Path) -> dict[str, int]:
    def _count(dir_path: Path) -> int:
        if not dir_path.exists():
            return 0
        return sum(1 for p in dir_path.rglob("*.json") if p.is_file())

    return {
        "reports_json": _count(outputs_root / "reports"),
        "alerts_json": _count(outputs_root / "alerts"),
        "tickets_json": _count(outputs_root / "tickets"),
    }


def process_new_high_alerts(
    outputs_root: Path,
    seen_ids: set[str],
    popup_enabled: bool,
    popup_log_path: Path,
) -> dict[str, Any]:
    alerts_dir = outputs_root / "alerts"
    new_count = 0
    popup_count = 0
    last_popup: dict[str, Any] | None = None
    if not alerts_dir.exists():
        return {"new_count": 0, "popup_count": 0, "last_popup": None}

    files = sorted((p for p in alerts_dir.rglob("*.json") if p.is_file()), key=lambda p: p.stat().st_mtime)
    for path in files:
        try:
            payload = read_json(path)
        except Exception:
            continue
        identity = alert_identity(path, payload)
        if identity in seen_ids:
            continue
        seen_ids.add(identity)
        new_count += 1
        if should_popup_alert(payload):
            popup_count += 1
            summary = extract_alert_summary(payload)
            last_popup = {
                "ts_utc": utc_now(),
                "path": str(path),
                "summary": summary,
                "severity": str(payload.get("severity", "")).upper(),
            }
            append_jsonl(
                popup_log_path,
                {
                    "ts_utc": utc_now(),
                    "event": "HIGH_ALERT_POPUP_TRIGGERED",
                    "alert_path": str(path),
                    "summary": summary,
                    "popup_enabled": popup_enabled,
                },
            )
            if popup_enabled:
                show_popup_async("OANDA OBSERVER HIGH ALERT", summary)
    return {"new_count": new_count, "popup_count": popup_count, "last_popup": last_popup}


def run_service(
    poll_sec: int,
    ops_every_sec: int,
    guardian_every_sec: int,
    rd_rec_every_sec: int,
    popup_enabled: bool,
) -> int:
    runtime = build_runtime(ops_every_sec, guardian_every_sec, rd_rec_every_sec)
    paths: Paths = runtime["paths"]
    state: SchedulerState = runtime["state"]
    outputs_root = paths.outputs_root
    operator_dir = outputs_root / "operator"
    operator_dir.mkdir(parents=True, exist_ok=True)
    status_path = operator_dir / "operator_runtime_status.json"
    popup_log_path = operator_dir / "operator_popup_events.jsonl"
    pid_path = operator_dir / "operator_runtime.pid"
    write_json(
        pid_path,
        {
            "pid": int(__import__("os").getpid()),
            "started_at_utc": utc_now(),
            "service": "operator_runtime_service",
            "popup_enabled": bool(popup_enabled),
        },
    )

    seen_alert_ids: set[str] = set()
    last_results: list[dict[str, Any]] = []
    last_popup: dict[str, Any] | None = None

    while True:
        now = time.time()
        last_results = []
        try:
            if now - state.last_ops >= ops_every_sec:
                state.last_ops = now
                result = runtime["ops"].run_cycle()
                last_results.append({"agent": "agent_informacyjny", "status": "PASS", "result": result})

            if now - state.last_guardian >= guardian_every_sec:
                state.last_guardian = now
                result = runtime["guardian"].run_cycle()
                last_results.append({"agent": "agent_straznik_spojnosci", "status": "PASS", "result": result})

            if now - state.last_rd_rec >= rd_rec_every_sec:
                state.last_rd_rec = now
                result_rd = runtime["rd"].run_cycle()
                result_rec = runtime["rec"].run_cycle()
                last_results.append({"agent": "agent_rozwoju_scalpingu", "status": "PASS", "result": result_rd})
                last_results.append({"agent": "agent_rekomendacyjny", "status": "PASS", "result": result_rec})
        except Exception as exc:
            last_results.append({"agent": "scheduler", "status": "FAIL", "error": str(exc)})

        alert_info = process_new_high_alerts(
            outputs_root=outputs_root,
            seen_ids=seen_alert_ids,
            popup_enabled=popup_enabled,
            popup_log_path=popup_log_path,
        )
        if alert_info.get("last_popup"):
            last_popup = alert_info["last_popup"]

        status_payload = {
            "schema_version": "oanda_mt5.observers.operator_runtime_status.v1",
            "ts_utc": utc_now(),
            "workspace_root_path": str(WORKSPACE_ROOT),
            "observers_root_path": str(OBS_ROOT),
            "service_state": "RUNNING",
            "popup_enabled": bool(popup_enabled),
            "intervals_sec": runtime["intervals"],
            "last_run_epoch": {
                "ops": state.last_ops,
                "guardian": state.last_guardian,
                "rd_rec": state.last_rd_rec,
            },
            "last_results": last_results,
            "output_counts": collect_output_counts(outputs_root),
            "new_alerts_last_poll": alert_info["new_count"],
            "high_popups_last_poll": alert_info["popup_count"],
            "last_popup": last_popup or {},
        }
        write_json(status_path, status_payload)
        time.sleep(max(1, int(poll_sec)))


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Observers runtime scheduler + operator alert popups.")
    p.add_argument("--poll-sec", type=int, default=5)
    p.add_argument("--ops-every-sec", type=int, default=60)
    p.add_argument("--guardian-every-sec", type=int, default=300)
    p.add_argument("--rd-rec-every-sec", type=int, default=1800)
    p.add_argument("--popup-enabled", action="store_true", default=False)
    return p.parse_args()


def main() -> int:
    args = parse_args()
    return run_service(
        poll_sec=args.poll_sec,
        ops_every_sec=args.ops_every_sec,
        guardian_every_sec=args.guardian_every_sec,
        rd_rec_every_sec=args.rd_rec_every_sec,
        popup_enabled=args.popup_enabled,
    )


if __name__ == "__main__":
    raise SystemExit(main())
