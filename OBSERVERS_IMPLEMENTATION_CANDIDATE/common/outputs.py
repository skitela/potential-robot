from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .contracts import CodexTicket
from .paths import Paths


def _utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    tmp.replace(path)


class ObserverOutputWriter:
    def __init__(self, paths: Paths) -> None:
        self.paths = paths
        self.paths.ensure_roots_exist()

    def write_report(self, agent_name: str, report_name: str, content_dict: dict[str, Any]) -> Path:
        stamp = _utc_stamp()
        out = self.paths.reports_root / agent_name / f"{stamp}_{report_name}.json"
        self.paths.ensure_write_allowed(out)
        payload = {
            "agent_name": agent_name,
            "report_name": report_name,
            "generated_at_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "content": content_dict,
        }
        _atomic_write_json(out, payload)
        return out

    def write_alert(self, agent_name: str, severity: str, alert_payload: dict[str, Any]) -> Path:
        stamp = _utc_stamp()
        digest = hashlib.sha256(json.dumps(alert_payload, sort_keys=True).encode("utf-8")).hexdigest()[:10]
        out = self.paths.alerts_root / agent_name / f"{stamp}_{severity}_{digest}.json"
        self.paths.ensure_write_allowed(out)
        payload = {
            "agent_name": agent_name,
            "severity": severity,
            "generated_at_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "alert": alert_payload,
        }
        _atomic_write_json(out, payload)
        return out

    def write_codex_ticket(self, ticket: CodexTicket) -> Path:
        stamp = _utc_stamp()
        out = self.paths.tickets_root / ticket.agent_name / f"{stamp}_{ticket.ticket_id}.json"
        self.paths.ensure_write_allowed(out)
        _atomic_write_json(out, ticket.to_dict())
        return out

