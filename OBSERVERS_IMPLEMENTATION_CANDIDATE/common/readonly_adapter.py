from __future__ import annotations

import json
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

from .contracts import EventRecord, Snapshot
from .paths import Paths


READ_STATUS_OK = "OK"
READ_STATUS_STALE_OR_INCOMPLETE_ARTIFACT = "STALE_OR_INCOMPLETE_ARTIFACT"
READ_STATUS_STALE_OR_INCOMPLETE = READ_STATUS_STALE_OR_INCOMPLETE_ARTIFACT
READ_STATUS_MISSING = "MISSING"


@dataclass(frozen=True)
class ReadPolicy:
    retries: int = 3
    backoff_sec: float = 0.15
    stale_after_sec: int = 900


class ReadOnlyDataAdapter:
    """Read-only adapter over persisted artifacts.

    No runtime sockets, no MT5 API calls, no mutation methods.
    """

    def __init__(self, paths: Paths, policy: ReadPolicy | None = None) -> None:
        self.paths = paths
        self.policy = policy or ReadPolicy()
        self.snapshot_map: dict[str, Path] = {
            "current_system_state": self.paths.workspace_root / "RUN" / "live_trade_monitor_status.json",
            "asia_preflight_summary": self.paths.workspace_root / "EVIDENCE" / "asia_symbol_preflight.json",
            "no_live_drift_summary": self.paths.workspace_root / "EVIDENCE" / "no_live_drift_check.json",
            "no_strategy_drift_summary": self.paths.workspace_root / "EVIDENCE" / "no_strategy_drift_check.json",
            "ipc_health_summary": self.paths.workspace_root / "RUN" / "live_trade_monitor_status.json",
        }

    def fetch_events(
        self,
        start_utc: str,
        end_utc: str,
        filters: dict[str, Any] | None = None,
    ) -> Iterable[EventRecord]:
        del start_utc, end_utc, filters
        log = self.paths.workspace_root / "LOGS" / "audit_trail.jsonl"
        if not log.exists():
            return []
        events: list[EventRecord] = []
        for row in self._read_jsonl_safe(log):
            event = EventRecord(
                event_type=str(row.get("event_type") or row.get("event") or "UNKNOWN"),
                timestamp_utc=str(row.get("timestamp_utc") or row.get("ts_utc") or ""),
                timestamp_semantics=str(row.get("timestamp_semantics") or "UTC"),
                source=str(log),
                symbol_raw=row.get("symbol_raw") or row.get("symbol"),
                symbol_canonical=row.get("symbol_canonical"),
                correlation_id=row.get("correlation_id"),
                message_id=row.get("message_id"),
                reason_code=row.get("reason_code"),
                payload=row,
            )
            events.append(event)
        return events

    def fetch_latest_snapshot(self, snapshot_name: str) -> Snapshot | None:
        path = self.snapshot_map.get(snapshot_name)
        if path is None:
            return None
        data, status = self._read_json_safe(path)
        if data is None:
            return Snapshot(
                created_at_utc=self._utc_now(),
                name=snapshot_name,
                data={},
                source_path=str(path),
                read_status=READ_STATUS_MISSING if not path.exists() else status,
            )
        return Snapshot(
            created_at_utc=self._utc_now(),
            name=snapshot_name,
            data=data,
            source_path=str(path),
            read_status=status,
        )

    def fetch_aggregate(self, aggregate_name: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        params = params or {}
        if aggregate_name == "execution_and_ipc_anomalies":
            snap = self.fetch_latest_snapshot("current_system_state")
            totals = (snap.data.get("totals") if snap else {}) or {}
            return {
                "aggregate_name": aggregate_name,
                "params": params,
                "rejects": totals.get("rejected", "UNKNOWN"),
                "retcode_10017": totals.get("retcode_10017", "UNKNOWN"),
                "source": snap.source_path if snap else "UNKNOWN",
                "read_status": snap.read_status if snap else READ_STATUS_MISSING,
            }
        return {
            "aggregate_name": aggregate_name,
            "params": params,
            "value": "UNKNOWN",
            "reason": "NO_PROVIDER_IMPLEMENTED",
        }

    def list_artifacts(self, artifact_type: str, limit: int = 50) -> list[Path]:
        roots: dict[str, Path] = {
            "alerts": self.paths.workspace_root / "LOGS",
            "evidence": self.paths.workspace_root / "EVIDENCE",
            "meta": self.paths.workspace_root / "META",
        }
        root = roots.get(artifact_type, self.paths.workspace_root / "EVIDENCE")
        if not root.exists():
            return []
        files = [p for p in root.rglob("*") if p.is_file()]
        files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        return files[:limit]

    def read_artifact_json(self, path: Path) -> dict[str, Any]:
        data, _ = self._read_json_safe(path)
        return data or {}

    def _read_json_safe(self, path: Path) -> tuple[dict[str, Any] | None, str]:
        if not path.exists():
            return None, READ_STATUS_MISSING
        last_exc: Exception | None = None
        for attempt in range(self.policy.retries):
            try:
                raw = path.read_text(encoding="utf-8")
                data = json.loads(raw)
                status = self._freshness_status(path)
                return data, status
            except (json.JSONDecodeError, OSError) as exc:
                last_exc = exc
                if attempt < self.policy.retries - 1:
                    time.sleep(self.policy.backoff_sec * (attempt + 1))
                    continue
        if last_exc is not None:
            return {"error": str(last_exc)}, READ_STATUS_STALE_OR_INCOMPLETE
        return None, READ_STATUS_STALE_OR_INCOMPLETE

    def _read_jsonl_safe(self, path: Path) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        if not path.exists():
            return rows
        for attempt in range(self.policy.retries):
            try:
                with path.open("r", encoding="utf-8", errors="ignore") as f:
                    for line in f:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            rows.append(json.loads(line))
                        except json.JSONDecodeError:
                            # partial append/tail race -> keep read-only behavior and continue
                            continue
                return rows
            except OSError:
                if attempt < self.policy.retries - 1:
                    time.sleep(self.policy.backoff_sec * (attempt + 1))
        return rows

    def _freshness_status(self, path: Path) -> str:
        age = time.time() - path.stat().st_mtime
        if age > self.policy.stale_after_sec:
            return READ_STATUS_STALE_OR_INCOMPLETE
        return READ_STATUS_OK

    @staticmethod
    def _utc_now() -> str:
        return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
