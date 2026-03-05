#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import tempfile
from pathlib import Path
from typing import Any, Dict, List

try:
    from TOOLS.lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from TOOLS.lab_registry import connect_registry, init_registry_schema, insert_job_run
except Exception:  # pragma: no cover
    from lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from lab_registry import connect_registry, init_registry_schema, insert_job_run

UTC = dt.timezone.utc
DEPLOYER_SCHEMA = "oanda.mt5.stage1_shadow_deployer_plan.v1"
APPLY_SCHEMA = "oanda.mt5.stage1_shadow_apply_plan.v1"
STATE_SCHEMA = "oanda.mt5.stage1_shadow_apply_state.v1"


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json_atomic(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
    fd, tmp = tempfile.mkstemp(prefix=".tmp_stage1_apply_", suffix=".json", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(raw + "\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, str(path))
    finally:
        if os.path.exists(tmp):
            try:
                os.remove(tmp)
            except OSError:
                pass


def _append_jsonl(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")


def _load_state(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {"schema": STATE_SCHEMA, "updated_at_utc": iso_utc(dt.datetime.now(tz=UTC)), "last_applied_run_id": "", "last_seen_run_id": ""}
    try:
        payload = _load_json(path)
        if not isinstance(payload, dict):
            raise ValueError("invalid state")
        payload.setdefault("schema", STATE_SCHEMA)
        payload.setdefault("last_applied_run_id", "")
        payload.setdefault("last_seen_run_id", "")
        return payload
    except Exception:
        return {"schema": STATE_SCHEMA, "updated_at_utc": iso_utc(dt.datetime.now(tz=UTC)), "last_applied_run_id": "", "last_seen_run_id": ""}


def _render_txt(report: Dict[str, Any]) -> str:
    lines: List[str] = []
    lines.append("STAGE1_SHADOW_APPLY_PLAN")
    lines.append(f"Status: {report.get('status')}")
    lines.append(f"Reason: {report.get('reason')}")
    lines.append(f"Deployer source: {report.get('deployer_source')}")
    lines.append(f"Mode: {report.get('mode')}")
    lines.append("")
    for a in report.get("actions", []):
        if not isinstance(a, dict):
            continue
        lines.append(
            "- {0}: action={1} profile={2}".format(
                a.get("symbol"),
                a.get("action"),
                a.get("profile"),
            )
        )
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Build apply-ready SHADOW plan from stage1_shadow_deployer output (no runtime mutation).")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--deployer-report", default="")
    ap.add_argument("--state-file", default="")
    ap.add_argument("--audit-jsonl", default="")
    ap.add_argument("--out-report", default="")
    ap.add_argument("--dry-run", action="store_true")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    started = dt.datetime.now(tz=UTC)
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    stage1_reports = (lab_data_root / "reports" / "stage1").resolve()
    run_dir = (lab_data_root / "run").resolve()
    stamp = started.strftime("%Y%m%dT%H%M%SZ")
    run_id = f"STAGE1_SHADOW_APPLY_{stamp}"

    deployer_report = (
        Path(args.deployer_report).resolve()
        if str(args.deployer_report).strip()
        else (stage1_reports / "stage1_shadow_deployer_latest.json").resolve()
    )
    state_file = (
        Path(args.state_file).resolve()
        if str(args.state_file).strip()
        else (run_dir / "stage1_shadow_apply_state.json").resolve()
    )
    audit_jsonl = (
        Path(args.audit_jsonl).resolve()
        if str(args.audit_jsonl).strip()
        else (stage1_reports / "stage1_shadow_apply_audit.jsonl").resolve()
    )
    out_report = (
        Path(args.out_report).resolve()
        if str(args.out_report).strip()
        else (stage1_reports / f"stage1_shadow_apply_plan_{stamp}.json").resolve()
    )
    state_file = ensure_write_parent(state_file, root=root, lab_data_root=lab_data_root)
    audit_jsonl = ensure_write_parent(audit_jsonl, root=root, lab_data_root=lab_data_root)
    out_report = ensure_write_parent(out_report, root=root, lab_data_root=lab_data_root)

    status = "SKIP"
    reason = "DEPLOYER_REPORT_MISSING"
    actions: List[Dict[str, Any]] = []
    deployer_hash = ""
    deployer_run_id = ""
    state = _load_state(state_file)

    if deployer_report.exists():
        payload = _load_json(deployer_report)
        if str(payload.get("schema") or "") != DEPLOYER_SCHEMA:
            reason = "DEPLOYER_SCHEMA_MISMATCH"
        elif str(payload.get("status") or "").upper() != "PASS":
            reason = "DEPLOYER_NOT_READY"
        else:
            deployer_run_id = str(payload.get("run_id") or "").strip()
            state["last_seen_run_id"] = deployer_run_id
            if deployer_run_id and deployer_run_id == str(state.get("last_applied_run_id") or ""):
                reason = "SKIP_ALREADY_APPLIED"
                status = "SKIP"
            else:
                rows = payload.get("instruments") if isinstance(payload.get("instruments"), list) else []
                for row in rows:
                    if not isinstance(row, dict):
                        continue
                    if str(row.get("decision") or "").upper() != "SELECTED_FOR_SHADOW":
                        continue
                    actions.append(
                        {
                            "symbol": str(row.get("symbol") or ""),
                            "action": "SET_PROFILE",
                            "profile": str(row.get("selected_profile") or ""),
                            "thresholds": row.get("thresholds") if isinstance(row.get("thresholds"), dict) else {},
                        }
                    )
                status = "PASS"
                reason = "APPLY_PLAN_READY" if actions else "NO_ACTIONS_SELECTED"
                if actions and deployer_run_id:
                    state["last_applied_run_id"] = deployer_run_id
            try:
                deployer_hash = file_sha256(deployer_report)
            except Exception:
                deployer_hash = ""

    state["schema"] = STATE_SCHEMA
    state["updated_at_utc"] = iso_utc(dt.datetime.now(tz=UTC))

    report = {
        "schema": APPLY_SCHEMA,
        "run_id": run_id,
        "started_at_utc": iso_utc(started),
        "finished_at_utc": iso_utc(dt.datetime.now(tz=UTC)),
        "status": status,
        "reason": reason,
        "mode": "SHADOW_ONLY",
        "dry_run": bool(args.dry_run),
        "runtime_mutation": False,
        "deployer_source": str(deployer_report),
        "deployer_hash": deployer_hash,
        "deployer_run_id": deployer_run_id,
        "actions": actions,
        "state_path": str(state_file),
        "audit_jsonl": str(audit_jsonl),
        "notes": [
            "No runtime config is mutated by this tool.",
            "Output is apply-ready action list for SHADOW executor.",
        ],
    }
    _write_json_atomic(out_report, report)
    out_report.with_suffix(".txt").write_text(_render_txt(report), encoding="utf-8")
    latest_json = ensure_write_parent((stage1_reports / "stage1_shadow_apply_plan_latest.json").resolve(), root=root, lab_data_root=lab_data_root)
    latest_txt = ensure_write_parent((stage1_reports / "stage1_shadow_apply_plan_latest.txt").resolve(), root=root, lab_data_root=lab_data_root)
    _write_json_atomic(latest_json, report)
    latest_txt.write_text(_render_txt(report), encoding="utf-8")
    _write_json_atomic(state_file, state)

    _append_jsonl(
        audit_jsonl,
        {
            "ts_utc": iso_utc(dt.datetime.now(tz=UTC)),
            "run_id": run_id,
            "event_type": "shadow_apply_summary",
            "status": status,
            "reason": reason,
            "actions_n": len(actions),
            "deployer_run_id": deployer_run_id,
        },
    )

    try:
        registry_path = (lab_data_root / "registry" / "lab_registry.sqlite").resolve()
        conn_reg = connect_registry(registry_path)
        init_registry_schema(conn_reg)
        cfg_hash = canonical_json_hash({"tool": "stage1_shadow_apply_plan.v1", "dry_run": bool(args.dry_run)})
        insert_job_run(
            conn_reg,
            {
                "run_id": run_id,
                "run_type": "STAGE1_SHADOW_APPLY_PLAN",
                "started_at_utc": report["started_at_utc"],
                "finished_at_utc": report["finished_at_utc"],
                "status": status,
                "source_type": "MT5_SNAPSHOT",
                "dataset_hash": deployer_hash,
                "config_hash": cfg_hash,
                "readiness": "N/A",
                "reason": reason,
                "evidence_path": str(out_report),
                "details_json": json.dumps({"actions_n": len(actions)}, ensure_ascii=False),
            },
        )
        conn_reg.close()
    except Exception as exc:
        _ = exc
    print(f"STAGE1_SHADOW_APPLY_PLAN_DONE status={status} reason={reason} report={out_report}")
    return 0 if status in {"PASS", "SKIP"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
