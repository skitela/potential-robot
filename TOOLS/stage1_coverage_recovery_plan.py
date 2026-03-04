#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    from TOOLS.lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from TOOLS.lab_registry import connect_registry, init_registry_schema, insert_job_run
except Exception:  # pragma: no cover
    from lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from lab_registry import connect_registry, init_registry_schema, insert_job_run

UTC = dt.timezone.utc
SCHEMA = "oanda.mt5.stage1_coverage_recovery_plan.v1"


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _latest_by_pattern(base: Path, pattern: str) -> Optional[Path]:
    files = sorted(base.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0] if files else None


def _load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _symbol_action(row: Dict[str, Any], thresholds: Dict[str, Any]) -> Dict[str, Any]:
    symbol = str(row.get("symbol") or "").upper()
    reasons = [str(x) for x in (row.get("reasons") or []) if str(x).strip()]
    return {
        "symbol": symbol,
        "status": "PENDING_DATA_COLLECTION",
        "reasons": reasons,
        "target_thresholds": {
            "min_total_per_symbol": int(thresholds.get("min_total_per_symbol") or 0),
            "min_rejects_per_symbol": int(thresholds.get("min_rejects_per_symbol") or 0),
            "min_trade_events_per_symbol": int(thresholds.get("min_trade_events_per_symbol") or 0),
        },
        "current_metrics": {
            "total_events_n": int(row.get("total_events_n") or 0),
            "rejected_candidates_n": int(row.get("rejected_candidates_n") or 0),
            "trade_events_n": int(row.get("trade_events_n") or 0),
        },
        "actions": [
            "Sprawdzic czy symbol jest aktywny w watchlist i telemetry gate loguje NO_TRADE + TRADE_PATH.",
            "Uruchomic kolejny cykl Stage-1 z wiekszym lookback (np. 48-72h) dla FocusGroup=FX.",
            "Zweryfikowac czy decyzje odrzucone sa zapisywane do decision_rejections (lub fallback log).",
        ],
    }


def _render_txt(report: Dict[str, Any]) -> str:
    lines: List[str] = []
    lines.append("STAGE1_COVERAGE_RECOVERY_PLAN")
    lines.append(f"Status: {report.get('status')}")
    lines.append(f"Reason: {report.get('reason')}")
    lines.append(f"Coverage verdict: {report.get('coverage_verdict')}")
    lines.append("")
    actions = report.get("actions_by_symbol") if isinstance(report.get("actions_by_symbol"), list) else []
    for row in actions:
        if not isinstance(row, dict):
            continue
        lines.append(
            "- {0}: total={1} rejects={2} trades={3} reasons={4}".format(
                row.get("symbol"),
                ((row.get("current_metrics") or {}).get("total_events_n")),
                ((row.get("current_metrics") or {}).get("rejected_candidates_n")),
                ((row.get("current_metrics") or {}).get("trade_events_n")),
                ",".join(row.get("reasons") or []),
            )
        )
    if report.get("operator_decision_required"):
        lines.append("")
        lines.append("OPERATOR_DECISION_REQUIRED:")
        for x in report["operator_decision_required"]:
            lines.append(f"- {x}")
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Create recovery plan for coverage HOLD blockers.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--lookback-hours", type=int, default=24)
    ap.add_argument("--focus-group", default="FX")
    ap.add_argument("--out-report", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    started = dt.datetime.now(tz=UTC)
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    stage1_reports = (lab_data_root / "reports" / "stage1").resolve()
    evidence_coverage = (root / "EVIDENCE" / "learning_coverage").resolve()
    stamp = started.strftime("%Y%m%dT%H%M%SZ")
    run_id = f"STAGE1_COVERAGE_RECOVERY_{stamp}"

    out_report = (
        Path(args.out_report).resolve()
        if str(args.out_report).strip()
        else (stage1_reports / f"stage1_coverage_recovery_{stamp}.json").resolve()
    )
    out_report = ensure_write_parent(out_report, root=root, lab_data_root=lab_data_root)

    cov_path = _latest_by_pattern(evidence_coverage, "rejected_coverage_gate_*.json")
    if cov_path is None:
        report = {
            "schema": SCHEMA,
            "run_id": run_id,
            "started_at_utc": iso_utc(started),
            "finished_at_utc": iso_utc(dt.datetime.now(tz=UTC)),
            "status": "FAIL",
            "reason": "COVERAGE_GATE_MISSING",
            "coverage_verdict": "UNKNOWN",
            "coverage_source": "",
            "coverage_hash": "",
            "actions_by_symbol": [],
            "operator_decision_required": ["coverage_gate_missing"],
        }
        out_report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        out_report.with_suffix(".txt").write_text(_render_txt(report), encoding="utf-8")
        latest_json = ensure_write_parent((stage1_reports / "stage1_coverage_recovery_latest.json").resolve(), root=root, lab_data_root=lab_data_root)
        latest_txt = ensure_write_parent((stage1_reports / "stage1_coverage_recovery_latest.txt").resolve(), root=root, lab_data_root=lab_data_root)
        latest_json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        latest_txt.write_text(_render_txt(report), encoding="utf-8")
        print(f"STAGE1_COVERAGE_RECOVERY_DONE status=FAIL reason=COVERAGE_GATE_MISSING report={out_report}")
        return 1

    cov = _load_json(cov_path)
    cov_verdict = str(((cov.get("verdict") or {}).get("status")) if isinstance(cov.get("verdict"), dict) else (cov.get("verdict") or "")).upper()
    thresholds = cov.get("thresholds") if isinstance(cov.get("thresholds"), dict) else {}
    symbols = cov.get("symbols") if isinstance(cov.get("symbols"), list) else []

    actions: List[Dict[str, Any]] = []
    for row in symbols:
        if not isinstance(row, dict):
            continue
        if str(row.get("status") or "").upper() != "HOLD":
            continue
        actions.append(_symbol_action(row, thresholds))

    hold_ratio = (len(actions) / max(1, len(symbols))) if symbols else 0.0
    operator_required: List[str] = []
    if hold_ratio >= 0.5:
        operator_required.append("scope_narrowing_or_data_collection_decision")

    status = "PASS" if not actions else "WARN"
    reason = "COVERAGE_OK" if not actions else "COVERAGE_GAPS_FOUND"
    report = {
        "schema": SCHEMA,
        "run_id": run_id,
        "started_at_utc": iso_utc(started),
        "finished_at_utc": iso_utc(dt.datetime.now(tz=UTC)),
        "status": status,
        "reason": reason,
        "focus_group": str(args.focus_group or "").upper(),
        "lookback_hours": int(args.lookback_hours),
        "coverage_verdict": cov_verdict or "UNKNOWN",
        "coverage_source": str(cov_path),
        "coverage_hash": file_sha256(cov_path),
        "actions_by_symbol": actions,
        "operator_decision_required": operator_required,
        "suggested_commands": [
            f"powershell -ExecutionPolicy Bypass -File {root}\\TOOLS\\run_stage1_learning_cycle.ps1 -Root {root} -LabDataRoot {lab_data_root} -FocusGroup {str(args.focus_group or '').upper()} -LookbackHours 48",
            f"powershell -ExecutionPolicy Bypass -File {root}\\TOOLS\\run_stage1_learning_cycle.ps1 -Root {root} -LabDataRoot {lab_data_root} -FocusGroup {str(args.focus_group or '').upper()} -LookbackHours 72",
        ],
        "notes": [
            "Plan nie modyfikuje runtime/live execution.",
            "To jest plan uzbierania brakujacej pokrywy danych pod Stage-1 gate.",
        ],
    }

    out_report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    out_report.with_suffix(".txt").write_text(_render_txt(report), encoding="utf-8")
    latest_json = ensure_write_parent((stage1_reports / "stage1_coverage_recovery_latest.json").resolve(), root=root, lab_data_root=lab_data_root)
    latest_txt = ensure_write_parent((stage1_reports / "stage1_coverage_recovery_latest.txt").resolve(), root=root, lab_data_root=lab_data_root)
    latest_json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    latest_txt.write_text(_render_txt(report), encoding="utf-8")

    try:
        registry_path = (lab_data_root / "registry" / "lab_registry.sqlite").resolve()
        conn_reg = connect_registry(registry_path)
        init_registry_schema(conn_reg)
        cfg_hash = canonical_json_hash({"tool": "stage1_coverage_recovery_plan.v1", "focus_group": str(args.focus_group or "").upper(), "lookback_hours": int(args.lookback_hours)})
        insert_job_run(
            conn_reg,
            {
                "run_id": run_id,
                "run_type": "STAGE1_COVERAGE_RECOVERY",
                "started_at_utc": report["started_at_utc"],
                "finished_at_utc": report["finished_at_utc"],
                "status": status,
                "source_type": "MT5_SNAPSHOT",
                "dataset_hash": report["coverage_hash"],
                "config_hash": cfg_hash,
                "readiness": report["coverage_verdict"],
                "reason": reason,
                "evidence_path": str(out_report),
                "details_json": json.dumps({"actions_n": len(actions), "operator_decision_required": operator_required}, ensure_ascii=False),
            },
        )
        conn_reg.close()
    except Exception:
        pass

    print(f"STAGE1_COVERAGE_RECOVERY_DONE status={status} reason={reason} report={out_report}")
    return 0 if status in {"PASS", "WARN"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
