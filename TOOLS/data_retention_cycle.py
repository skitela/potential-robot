#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


DEFAULT_POLICY = {
    "schema": "oanda_mt5.data_retention_policy.v1",
    "time_basis": "UTC",
    "transactional": {
        "execution_telemetry_days": 180,
        "incident_journal_days": 180,
        "archive_removed_raw": True,
    },
    "maintenance": {
        "audit_trail_days": 14,
        "archive_removed_raw": False,
        "keep_anomaly_packs_days": 90,
    },
    "outputs": {
        "archive_root": "ARCHIVE/retention",
        "reports_root": "EVIDENCE/retention",
        "daily_state_file": "RUN/retention_cycle_state.json",
    },
    "report_retention": {
        "run_reports_keep_days": 30,
        "daily_reports_keep_days": 120,
        "incident_packs_keep_days": 120,
    },
}


TIMESTAMP_KEYS = (
    "ts_utc",
    "timestamp_utc",
    "timestamp",
    "ts",
    "time_utc",
    "time",
)


ANOMALY_KEYWORDS = (
    "FAIL",
    "ERROR",
    "TIMEOUT",
    "REJECT",
    "BLOCK",
    "KILL_SWITCH",
    "STALE",
    "ANOMALY",
)


@dataclass
class RotationSummary:
    target: str
    kind: str
    keep_days: int
    lines_total: int
    lines_kept: int
    lines_removed: int
    lines_removed_anomaly: int
    parse_errors: int
    bytes_before: int
    bytes_after: int


def _utc_now() -> datetime:
    return datetime.now(UTC)


def _iso(dt_obj: datetime) -> str:
    return dt_obj.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def _merge_policy(raw: Dict[str, Any]) -> Dict[str, Any]:
    out = json.loads(json.dumps(DEFAULT_POLICY))
    for key, value in raw.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key].update(value)
        else:
            out[key] = value
    return out


def _parse_ts(raw: Any) -> Optional[datetime]:
    if not raw:
        return None
    s = str(raw).strip()
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(UTC)
    except Exception:
        return None


def _extract_ts(rec: Dict[str, Any]) -> Optional[datetime]:
    for k in TIMESTAMP_KEYS:
        ts = _parse_ts(rec.get(k))
        if ts is not None:
            return ts
    data = rec.get("data")
    if isinstance(data, dict):
        for k in TIMESTAMP_KEYS:
            ts = _parse_ts(data.get(k))
            if ts is not None:
                return ts
    return None


def _is_anomaly(rec: Dict[str, Any]) -> bool:
    event = str(rec.get("event_type") or rec.get("event") or rec.get("type") or "").upper()
    if any(k in event for k in ANOMALY_KEYWORDS):
        return True
    severity = str(rec.get("severity") or "").upper()
    if severity in {"ERROR", "WARN", "CRITICAL"}:
        return True
    reason = str(rec.get("reason_code") or "").upper()
    if reason and reason not in {"NONE", "OK", "UNKNOWN"}:
        return True
    data = rec.get("data")
    if isinstance(data, dict):
        d_reason = str(data.get("reason_code") or data.get("reason") or "").upper()
        if d_reason and d_reason not in {"NONE", "OK", "UNKNOWN"}:
            return True
    return False


def _iter_lines(path: Path) -> Iterable[str]:
    with path.open("r", encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            if line.strip():
                yield line


def _append_line(path: Path, line: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(line if line.endswith("\n") else (line + "\n"))


def _rewrite_lines(path: Path, lines: List[str]) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as handle:
        for line in lines:
            handle.write(line if line.endswith("\n") else (line + "\n"))
    tmp.replace(path)


def _cleanup_old_reports(root: Path, keep_days: int) -> int:
    if not root.exists():
        return 0
    cutoff = _utc_now() - timedelta(days=max(1, int(keep_days)))
    removed = 0
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        mtime = datetime.fromtimestamp(p.stat().st_mtime, tz=UTC)
        if mtime >= cutoff:
            continue
        p.unlink(missing_ok=True)
        removed += 1
    return removed


def _should_skip_daily(state_file: Path, now_utc: datetime) -> bool:
    if not state_file.exists():
        return False
    try:
        state = _load_json(state_file)
    except Exception:
        return False
    last = _parse_ts(state.get("last_run_ts_utc"))
    if last is None:
        return False
    return last.date() == now_utc.date()


def _update_daily_state(state_file: Path, now_utc: datetime, status: str) -> None:
    payload = {"last_run_ts_utc": _iso(now_utc), "last_status": status}
    _write_json(state_file, payload)


def _archive_path(base: Path, kind: str, target_name: str, ts: datetime) -> Path:
    return (
        base
        / kind
        / target_name
        / f"{ts.year:04d}"
        / f"{ts.month:02d}"
        / f"{ts.day:02d}.jsonl"
    )


def rotate_jsonl_file(
    *,
    root: Path,
    rel_path: str,
    kind: str,
    keep_days: int,
    archive_removed_raw: bool,
    archive_root: Path,
    incident_sink: List[Dict[str, Any]],
    apply: bool,
) -> RotationSummary:
    path = (root / rel_path).resolve()
    before = int(path.stat().st_size) if path.exists() else 0
    if not path.exists():
        return RotationSummary(
            target=rel_path,
            kind=kind,
            keep_days=int(keep_days),
            lines_total=0,
            lines_kept=0,
            lines_removed=0,
            lines_removed_anomaly=0,
            parse_errors=0,
            bytes_before=0,
            bytes_after=0,
        )

    cutoff = _utc_now() - timedelta(days=max(1, int(keep_days)))
    kept: List[str] = []
    total = 0
    removed = 0
    removed_anomaly = 0
    parse_errors = 0

    for line in _iter_lines(path):
        total += 1
        raw = line.strip()
        try:
            rec = json.loads(raw)
        except Exception:
            parse_errors += 1
            kept.append(line)
            continue
        ts = _extract_ts(rec)
        if ts is None or ts >= cutoff:
            kept.append(line)
            continue
        removed += 1
        anomaly = _is_anomaly(rec)
        if anomaly:
            removed_anomaly += 1
            incident_sink.append(
                {
                    "source": rel_path,
                    "event_type": str(rec.get("event_type") or rec.get("event") or rec.get("type") or "UNKNOWN"),
                    "reason_code": str(rec.get("reason_code") or (rec.get("data") or {}).get("reason_code") or "UNKNOWN"),
                    "ts_utc": _iso(ts),
                    "retention_reason": f"EXPIRED_{kind.upper()}",
                }
            )
        if apply and archive_removed_raw:
            target_name = path.stem
            ap = _archive_path(archive_root, kind, target_name, ts)
            _append_line(ap, raw)

    if apply and removed > 0:
        _rewrite_lines(path, kept)
    after = int(path.stat().st_size) if path.exists() else 0
    return RotationSummary(
        target=rel_path,
        kind=kind,
        keep_days=int(keep_days),
        lines_total=total,
        lines_kept=len(kept),
        lines_removed=removed,
        lines_removed_anomaly=removed_anomaly,
        parse_errors=parse_errors,
        bytes_before=before,
        bytes_after=after,
    )


def _parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Apply data retention policy with daily report and incident packs.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--policy", default="CONFIG/data_retention_policy.json")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--daily-guard", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--out", default="")
    return ap.parse_args()


def main() -> int:
    args = _parse_args()
    root = Path(args.root).resolve()
    policy_path = Path(args.policy)
    if not policy_path.is_absolute():
        policy_path = (root / policy_path).resolve()

    now_utc = _utc_now()
    policy_raw = _load_json(policy_path) if policy_path.exists() else {}
    policy = _merge_policy(policy_raw)

    outputs = dict(policy.get("outputs") or {})
    archive_root = (root / str(outputs.get("archive_root") or "ARCHIVE/retention")).resolve()
    reports_root = (root / str(outputs.get("reports_root") or "EVIDENCE/retention")).resolve()
    daily_state = (root / str(outputs.get("daily_state_file") or "RUN/retention_cycle_state.json")).resolve()

    if bool(args.daily_guard) and not bool(args.force) and _should_skip_daily(daily_state, now_utc):
        report = {
            "schema": "oanda_mt5.data_retention_cycle.v1",
            "status": "SKIP_ALREADY_RUN_TODAY",
            "ts_utc": _iso(now_utc),
            "root": str(root),
            "policy_path": str(policy_path),
            "apply": bool(args.apply),
            "daily_guard": True,
        }
        out = Path(args.out).resolve() if args.out else (reports_root / "runs" / f"retention_cycle_{now_utc.strftime('%Y%m%dT%H%M%SZ')}.json")
        _write_json(out, report)
        print(f"RETENTION_CYCLE_OK status={report['status']} out={out}")
        return 0

    transactional = dict(policy.get("transactional") or {})
    maintenance = dict(policy.get("maintenance") or {})
    report_ret = dict(policy.get("report_retention") or {})

    incident_rows: List[Dict[str, Any]] = []
    summaries: List[RotationSummary] = []

    summaries.append(
        rotate_jsonl_file(
            root=root,
            rel_path="LOGS/execution_telemetry_v2.jsonl",
            kind="transactional",
            keep_days=int(transactional.get("execution_telemetry_days", 180)),
            archive_removed_raw=bool(transactional.get("archive_removed_raw", True)),
            archive_root=archive_root,
            incident_sink=incident_rows,
            apply=bool(args.apply),
        )
    )
    summaries.append(
        rotate_jsonl_file(
            root=root,
            rel_path="LOGS/incident_journal.jsonl",
            kind="transactional",
            keep_days=int(transactional.get("incident_journal_days", 180)),
            archive_removed_raw=bool(transactional.get("archive_removed_raw", True)),
            archive_root=archive_root,
            incident_sink=incident_rows,
            apply=bool(args.apply),
        )
    )
    summaries.append(
        rotate_jsonl_file(
            root=root,
            rel_path="LOGS/audit_trail.jsonl",
            kind="maintenance",
            keep_days=int(maintenance.get("audit_trail_days", 14)),
            archive_removed_raw=bool(maintenance.get("archive_removed_raw", False)),
            archive_root=archive_root,
            incident_sink=incident_rows,
            apply=bool(args.apply),
        )
    )

    summary_payload = {
        "targets": [s.__dict__ for s in summaries],
        "totals": {
            "lines_total": sum(s.lines_total for s in summaries),
            "lines_removed": sum(s.lines_removed for s in summaries),
            "lines_removed_anomaly": sum(s.lines_removed_anomaly for s in summaries),
            "bytes_before": sum(s.bytes_before for s in summaries),
            "bytes_after": sum(s.bytes_after for s in summaries),
            "bytes_reclaimed_estimate": max(0, sum(s.bytes_before for s in summaries) - sum(s.bytes_after for s in summaries)),
        },
    }

    incident_pack_path = None
    if incident_rows:
        by_event: Dict[str, int] = {}
        by_reason: Dict[str, int] = {}
        for row in incident_rows:
            evt = str(row.get("event_type") or "UNKNOWN")
            by_event[evt] = int(by_event.get(evt, 0)) + 1
            reason = str(row.get("reason_code") or "UNKNOWN")
            by_reason[reason] = int(by_reason.get(reason, 0)) + 1
        incident_payload = {
            "schema": "oanda_mt5.retention_incident_pack.v1",
            "ts_utc": _iso(now_utc),
            "source": "data_retention_cycle",
            "reason": "expired_maintenance_or_transactional_records_with_anomaly_traits",
            "counts": {
                "rows": len(incident_rows),
                "by_event_type": by_event,
                "by_reason_code": by_reason,
            },
            "rows_sample": incident_rows[:2000],
        }
        incident_pack_path = reports_root / "incidents" / f"incident_pack_{now_utc.strftime('%Y%m%dT%H%M%SZ')}.json"
        if args.apply:
            _write_json(incident_pack_path, incident_payload)

    daily_report_path = reports_root / "daily" / f"retention_daily_{now_utc.strftime('%Y%m%d')}.json"
    daily_report: Dict[str, Any]
    if daily_report_path.exists():
        try:
            daily_report = _load_json(daily_report_path)
        except Exception:
            daily_report = {"schema": "oanda_mt5.retention_daily.v1", "date_utc": now_utc.strftime("%Y-%m-%d"), "runs": []}
    else:
        daily_report = {"schema": "oanda_mt5.retention_daily.v1", "date_utc": now_utc.strftime("%Y-%m-%d"), "runs": []}

    run_row = {
        "ts_utc": _iso(now_utc),
        "apply": bool(args.apply),
        "summary": summary_payload["totals"],
        "targets": summary_payload["targets"],
        "incident_pack_path": str(incident_pack_path) if incident_pack_path else "",
    }
    daily_report.setdefault("runs", []).append(run_row)
    daily_report["last_update_utc"] = _iso(now_utc)

    run_report = {
        "schema": "oanda_mt5.data_retention_cycle.v1",
        "status": "PASS",
        "ts_utc": _iso(now_utc),
        "root": str(root),
        "policy_path": str(policy_path),
        "apply": bool(args.apply),
        "daily_guard": bool(args.daily_guard),
        "summary": summary_payload,
        "incident_pack_path": str(incident_pack_path) if incident_pack_path else "",
        "daily_report_path": str(daily_report_path),
    }

    run_report_path = Path(args.out).resolve() if args.out else (reports_root / "runs" / f"retention_cycle_{now_utc.strftime('%Y%m%dT%H%M%SZ')}.json")
    if args.apply:
        _write_json(run_report_path, run_report)
        _write_json(daily_report_path, daily_report)
        _update_daily_state(daily_state, now_utc, "PASS")
        removed_run_reports = _cleanup_old_reports(reports_root / "runs", int(report_ret.get("run_reports_keep_days", 30)))
        removed_daily_reports = _cleanup_old_reports(reports_root / "daily", int(report_ret.get("daily_reports_keep_days", 120)))
        removed_incident_packs = _cleanup_old_reports(
            reports_root / "incidents",
            int(max(int(report_ret.get("incident_packs_keep_days", 120)), int(maintenance.get("keep_anomaly_packs_days", 90)))),
        )
        run_report["report_retention_cleanup"] = {
            "removed_run_reports": int(removed_run_reports),
            "removed_daily_reports": int(removed_daily_reports),
            "removed_incident_packs": int(removed_incident_packs),
        }
        _write_json(run_report_path, run_report)

    print(
        "RETENTION_CYCLE_OK status=PASS apply={0} removed_lines={1} reclaimed_bytes={2} out={3}".format(
            int(bool(args.apply)),
            int(summary_payload["totals"]["lines_removed"]),
            int(summary_payload["totals"]["bytes_reclaimed_estimate"]),
            str(run_report_path),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
