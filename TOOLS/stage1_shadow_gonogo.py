#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    from TOOLS.lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from TOOLS.lab_registry import connect_registry, init_registry_schema, insert_job_run
except Exception:  # pragma: no cover
    from lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from lab_registry import connect_registry, init_registry_schema, insert_job_run

UTC = dt.timezone.utc
CHECK_PASS = "PASS"
CHECK_WARN = "WARN"
CHECK_FAIL = "FAIL"


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _latest_by_pattern(base: Path, pattern: str) -> Optional[Path]:
    files = sorted(base.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0] if files else None


def _render_txt(report: Dict[str, Any]) -> str:
    lines: List[str] = []
    lines.append("STAGE1_SHADOW_GONOGO")
    lines.append(f"Verdict: {report.get('verdict')}")
    lines.append(f"Status: {report.get('status')}")
    lines.append(f"Reason: {report.get('reason')}")
    lines.append("")
    for c in report.get("checks", []):
        if not isinstance(c, dict):
            continue
        lines.append("- {0}: {1} ({2})".format(c.get("name"), c.get("result"), c.get("reason")))
    if report.get("operator_decisions_required"):
        lines.append("")
        lines.append("OPERATOR_DECISION_REQUIRED:")
        for item in report.get("operator_decisions_required", []):
            lines.append(f"- {item}")
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Stage-1 SHADOW go/no-go gate.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument(
        "--dataset-quality-hold-mode",
        choices=["fail", "warn"],
        default="fail",
        help="How to treat dataset_quality verdict HOLD.",
    )
    ap.add_argument("--out-report", default="")
    return ap.parse_args()


def _add_check(checks: List[Dict[str, Any]], name: str, result: str, reason: str, source: str = "") -> None:
    checks.append({"name": name, "result": result, "reason": reason, "source": source})


def _verdict_status(payload: Dict[str, Any]) -> str:
    v = payload.get("verdict")
    if isinstance(v, dict):
        return str(v.get("status") or "").upper().strip()
    return str(v or "").upper().strip()


def main() -> int:
    args = parse_args()
    started = dt.datetime.now(tz=UTC)
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)

    evidence_quality = (root / "EVIDENCE" / "learning_dataset_quality").resolve()
    evidence_coverage = (root / "EVIDENCE" / "learning_coverage").resolve()
    stage1_reports = (lab_data_root / "reports" / "stage1").resolve()
    stamp = started.strftime("%Y%m%dT%H%M%SZ")
    run_id = f"STAGE1_SHADOW_GONOGO_{stamp}"
    out_report = (
        Path(args.out_report).resolve()
        if str(args.out_report).strip()
        else (stage1_reports / f"stage1_shadow_gonogo_{stamp}.json").resolve()
    )
    out_report = ensure_write_parent(out_report, root=root, lab_data_root=lab_data_root)

    checks: List[Dict[str, Any]] = []
    operator_required: List[str] = []
    hashes: Dict[str, str] = {}

    # 1) Dataset quality
    q_path = _latest_by_pattern(evidence_quality, "stage1_dataset_quality_*.json")
    if q_path is None:
        _add_check(checks, "dataset_quality", CHECK_FAIL, "MISSING", "")
    else:
        q = load_json(q_path)
        verdict = _verdict_status(q)
        if verdict == "PASS":
            _add_check(checks, "dataset_quality", CHECK_PASS, "PASS", str(q_path))
        elif verdict == "HOLD":
            if str(args.dataset_quality_hold_mode).lower() == "warn":
                _add_check(checks, "dataset_quality", CHECK_WARN, "HOLD_DATASET_QUALITY", str(q_path))
            else:
                _add_check(checks, "dataset_quality", CHECK_FAIL, "VERDICT_HOLD", str(q_path))
        else:
            _add_check(checks, "dataset_quality", CHECK_FAIL, f"VERDICT_{verdict or 'UNKNOWN'}", str(q_path))
        try:
            hashes["dataset_quality"] = file_sha256(q_path)
        except Exception:
            hashes["dataset_quality"] = ""

    # 2) Coverage gate
    c_path = _latest_by_pattern(evidence_coverage, "rejected_coverage_gate_*.json")
    if c_path is None:
        _add_check(checks, "coverage_gate", CHECK_WARN, "MISSING", "")
    else:
        c = load_json(c_path)
        verdict = _verdict_status(c)
        if verdict == "PASS":
            _add_check(checks, "coverage_gate", CHECK_PASS, "PASS", str(c_path))
        elif verdict == "HOLD":
            _add_check(checks, "coverage_gate", CHECK_WARN, "HOLD_LOW_COVERAGE", str(c_path))
        else:
            _add_check(checks, "coverage_gate", CHECK_WARN, f"VERDICT_{verdict or 'UNKNOWN'}", str(c_path))
        try:
            hashes["coverage_gate"] = file_sha256(c_path)
        except Exception:
            hashes["coverage_gate"] = ""

    # 3) Profile eval
    pe_path = (stage1_reports / "stage1_profile_pack_eval_latest.json").resolve()
    if not pe_path.exists():
        _add_check(checks, "profile_eval", CHECK_FAIL, "MISSING", str(pe_path))
    else:
        pe = load_json(pe_path)
        status = str(pe.get("status") or "").upper()
        if status == "PASS":
            _add_check(checks, "profile_eval", CHECK_PASS, "PASS", str(pe_path))
        else:
            _add_check(checks, "profile_eval", CHECK_FAIL, f"STATUS_{status or 'UNKNOWN'}", str(pe_path))
        try:
            hashes["profile_eval"] = file_sha256(pe_path)
        except Exception:
            hashes["profile_eval"] = ""

    # 4) Shadow deployer
    sd_path = (stage1_reports / "stage1_shadow_deployer_latest.json").resolve()
    if not sd_path.exists():
        _add_check(checks, "shadow_deployer", CHECK_WARN, "MISSING", str(sd_path))
        operator_required.append("shadow_deployer_missing")
    else:
        sd = load_json(sd_path)
        status = str(sd.get("status") or "").upper()
        reason = str(sd.get("reason") or "").upper()
        if status == "PASS":
            _add_check(checks, "shadow_deployer", CHECK_PASS, "PASS", str(sd_path))
        elif status == "SKIP" and reason == "HUMAN_APPROVAL_REQUIRED":
            _add_check(checks, "shadow_deployer", CHECK_WARN, "HUMAN_APPROVAL_REQUIRED", str(sd_path))
            operator_required.append("manual_approval")
        else:
            _add_check(checks, "shadow_deployer", CHECK_FAIL, f"{status}:{reason}", str(sd_path))
        try:
            hashes["shadow_deployer"] = file_sha256(sd_path)
        except Exception:
            hashes["shadow_deployer"] = ""

    # 5) Shadow apply plan
    sa_path = (stage1_reports / "stage1_shadow_apply_plan_latest.json").resolve()
    if not sa_path.exists():
        _add_check(checks, "shadow_apply_plan", CHECK_WARN, "MISSING", str(sa_path))
    else:
        sa = load_json(sa_path)
        status = str(sa.get("status") or "").upper()
        reason = str(sa.get("reason") or "").upper()
        if status == "PASS":
            _add_check(checks, "shadow_apply_plan", CHECK_PASS, "PASS", str(sa_path))
        elif status == "SKIP" and reason in {"SKIP_ALREADY_APPLIED", "DEPLOYER_NOT_READY", "NO_ACTIONS_SELECTED"}:
            _add_check(checks, "shadow_apply_plan", CHECK_WARN, reason, str(sa_path))
        else:
            _add_check(checks, "shadow_apply_plan", CHECK_FAIL, f"{status}:{reason}", str(sa_path))
        try:
            hashes["shadow_apply_plan"] = file_sha256(sa_path)
        except Exception:
            hashes["shadow_apply_plan"] = ""

    has_fail = any(str(c.get("result")) == CHECK_FAIL for c in checks)
    has_warn = any(str(c.get("result")) == CHECK_WARN for c in checks)
    if has_fail:
        verdict = "NO-GO"
        status = "FAIL"
        reason = "CHECKS_FAILED"
    elif has_warn:
        verdict = "REVIEW_REQUIRED"
        status = "WARN"
        reason = "CHECKS_WITH_WARNINGS"
    else:
        verdict = "PASS"
        status = "PASS"
        reason = "ALL_CHECKS_PASS"

    report = {
        "schema": "oanda.mt5.stage1_shadow_gonogo.v1",
        "run_id": run_id,
        "started_at_utc": iso_utc(started),
        "finished_at_utc": iso_utc(dt.datetime.now(tz=UTC)),
        "status": status,
        "reason": reason,
        "verdict": verdict,
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "checks": checks,
        "operator_decisions_required": sorted(set(operator_required)),
        "source_hashes": hashes,
        "notes": [
            "Go/No-Go applies to SHADOW control plane, not live execution.",
            "Any FAIL check results in NO-GO.",
        ],
    }
    out_report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    out_report.with_suffix(".txt").write_text(_render_txt(report), encoding="utf-8")
    latest_json = ensure_write_parent((stage1_reports / "stage1_shadow_gonogo_latest.json").resolve(), root=root, lab_data_root=lab_data_root)
    latest_txt = ensure_write_parent((stage1_reports / "stage1_shadow_gonogo_latest.txt").resolve(), root=root, lab_data_root=lab_data_root)
    latest_json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    latest_txt.write_text(_render_txt(report), encoding="utf-8")

    try:
        registry_path = (lab_data_root / "registry" / "lab_registry.sqlite").resolve()
        conn_reg = connect_registry(registry_path)
        init_registry_schema(conn_reg)
        cfg_hash = canonical_json_hash({"tool": "stage1_shadow_gonogo.v1"})
        insert_job_run(
            conn_reg,
            {
                "run_id": run_id,
                "run_type": "STAGE1_SHADOW_GONOGO",
                "started_at_utc": report["started_at_utc"],
                "finished_at_utc": report["finished_at_utc"],
                "status": status,
                "source_type": "MT5_SNAPSHOT",
                "dataset_hash": canonical_json_hash(hashes),
                "config_hash": cfg_hash,
                "readiness": verdict,
                "reason": reason,
                "evidence_path": str(out_report),
                "details_json": json.dumps({"checks_n": len(checks), "operator_decisions_required": operator_required}, ensure_ascii=False),
            },
        )
        conn_reg.close()
    except Exception as exc:
        _ = exc
    print(f"STAGE1_SHADOW_GONOGO_DONE verdict={verdict} status={status} reason={reason} report={out_report}")
    return 0 if verdict in {"PASS", "REVIEW_REQUIRED"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
