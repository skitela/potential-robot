# -*- coding: utf-8 -*-
"""validate_audit_checklist_v1_2.py

Strict validator for the V1.2 audit report template defined in:
PROMPT_OANDA_MT5_SYSTEM_AUDYT.py

Rules enforced:
- Required stages E0..E6 must exist.
- Required checklist points C01..C50 must exist.
- Evidence field is mandatory for every stage/check item.
- Optional stages E4/E5 may be marked NIE_URUCHAMIANO.
- SYSTEM_STATUS must match computed status from checklist:
  * GOTOWY only when every C01..C50 == PASS.
  * otherwise NIEGOTOWY.
"""

from __future__ import annotations

import argparse
import json
import re
import time
from pathlib import Path
from typing import Any, Dict, List, Tuple

STAGE_IDS: List[str] = [
    "E0_PRECHECK_DISK",
    "E1_PREFLIGHT_SAFE",
    "E2_AUDIT_OFFLINE",
    "E3_AUDIT_TRAINING_OFFLINE",
    "E4_OPTIONAL_ONLINE_PREFLIGHT",
    "E5_OPTIONAL_ONLINE_SMOKE_MT5",
    "E6_PODSUMOWANIE",
]

OPTIONAL_STAGE_IDS = {
    "E4_OPTIONAL_ONLINE_PREFLIGHT",
    "E5_OPTIONAL_ONLINE_SMOKE_MT5",
}

CHECKLIST_IDS: List[str] = [
    "C01_ROOT_HARD",
    "C02_KANON_PLIKOW",
    "C03_OFFLINE_CONTRACT",
    "C04_NO_TRADING_DURING_AUDIT",
    "C05_STRATEGY_UNCHANGED",
    "C06_GUARDS_NOT_WEAKENED",
    "C07_OANDA_LIMITS_CONSISTENT",
    "C08_RETCODE_PROTECTION",
    "C09_SECRETS_POLICY",
    "C10_EVIDENCE_REQUIRED",
    "C11_PREFLIGHT_PASS",
    "C12_OFFLINE_AUDIT_PASS",
    "C13_TRAINING_AUDIT_PASS",
    "C14_API_CONTRACTS_PASS",
    "C15_TESTS_PASS",
    "C16_HOUSEKEEPING_SAFE",
    "C17_NO_EXTERNAL_CHANNELS",
    "C18_ONLINE_SMOKE_POLICY",
    "C19_PIPELINE_VERDICT_PASS",
    "C20_PIPELINE_RUNLOG_PRESENT",
    "C21_PIPELINE_STEP_LOGS_PRESENT",
    "C22_PREFLIGHT_ITER_LOGS_PRESENT",
    "C23_PREFLIGHT_AUDIT_OFFLINE_PASS",
    "C24_OFFLINE_MODE_DRY_RUN",
    "C25_OFFLINE_REASONS_EMPTY",
    "C26_OFFLINE_QUALITY_ALL_PASS",
    "C27_OFFLINE_MANIFEST_COMPLETE",
    "C28_OFFLINE_REDACTION_REPORT_PRESENT",
    "C29_OFFLINE_BUNDLE_INTEGRITY_FILES",
    "C30_OFFLINE_RUNLOG_PRESENT",
    "C31_TRAINING_VERDICT_PASS",
    "C32_TRAINING_CHECKPOINT_PRESENT",
    "C33_TRAINING_LINEAGE_PRESENT",
    "C34_TRAINING_REQUIRED_STEPS_OK",
    "C35_TRAINING_TESTS_EXIT0",
    "C36_TRAINING_TEST_SUITES_PRESENT",
    "C37_TRAINING_API_CONTRACTS_CLEAN",
    "C38_TRAINING_COMPILE_NO_FAILURES",
    "C39_TRAINING_DEPENDENCY_REPORT_PASS",
    "C40_TRAINING_HOUSEKEEPING_REPORT_PASS",
    "C41_SECRETS_SCAN_NO_FINDINGS",
    "C42_CHANNELS_DISABLED_IN_TRAINING_SCRIPT",
    "C43_RUNTIME_ROOT_TOOL_PRESENT",
    "C44_VALIDATOR_TOOL_PRESENT",
    "C45_GENERATOR_TOOL_PRESENT",
    "C46_HOUSEKEEPING_TOOL_PRESENT",
    "C47_GATE_TOOL_PRESENT",
    "C48_DIAG_BUNDLE_TOOL_PRESENT",
    "C49_SAFETYBOT_TIMEZONE_POLICY_DEFINED",
    "C50_SAFETYBOT_TIME_HELPERS_DEFINED",
]

_STAGE_RE = re.compile(
    r"^[\-\*]\s*(E[0-9]_[A-Z0-9_]+):\s*(PASS|FAIL|NIE_URUCHAMIANO)\s*\|\s*dow[oó]d:\s*(.*?)\s*$",
    re.IGNORECASE,
)
_CHECK_RE = re.compile(
    r"^[\-\*]\s*(C[0-9]{2}_[A-Z0-9_]+):\s*(PASS|FAIL)\s*\|\s*dow[oó]d:\s*(.*?)\s*\|\s*uwaga:\s*(.*?)\s*$",
    re.IGNORECASE,
)
_SYSTEM_RE = re.compile(
    r"^[\-\*]\s*SYSTEM_STATUS:\s*(GOTOWY|NIEGOTOWY)\s*$",
    re.IGNORECASE,
)


def _is_placeholder(value: str) -> bool:
    v = (value or "").strip()
    if not v:
        return True
    low = v.lower()
    if low in {"...", "<...>", "-", "brak", "none", "null", "n/a"}:
        return True
    if re.search(r"<[^>]+>", v):
        return True
    return False


def _add_finding(findings: List[Dict[str, Any]], fid: str, message: str, line: int = 0) -> None:
    item: Dict[str, Any] = {"id": fid, "severity": "ERROR", "message": message}
    if line > 0:
        item["line"] = int(line)
    findings.append(item)


def _parse_report(text: str) -> Tuple[Dict[str, Dict[str, Any]], Dict[str, Dict[str, Any]], Dict[str, Any]]:
    stages: Dict[str, Dict[str, Any]] = {}
    checks: Dict[str, Dict[str, Any]] = {}
    system_status: Dict[str, Any] = {"value": "", "line": 0}

    lines = text.splitlines()
    for idx, raw in enumerate(lines, start=1):
        line = raw.strip()
        if not line:
            continue

        m_stage = _STAGE_RE.match(line)
        if m_stage:
            sid = m_stage.group(1).upper()
            status = m_stage.group(2).upper()
            evidence = m_stage.group(3).strip()
            if sid not in stages:
                stages[sid] = {"status": status, "evidence": evidence, "line": idx}
            else:
                stages[sid]["_duplicate_line"] = idx
            continue

        m_check = _CHECK_RE.match(line)
        if m_check:
            cid = m_check.group(1).upper()
            status = m_check.group(2).upper()
            evidence = m_check.group(3).strip()
            note = m_check.group(4).strip()
            if cid not in checks:
                checks[cid] = {"status": status, "evidence": evidence, "note": note, "line": idx}
            else:
                checks[cid]["_duplicate_line"] = idx
            continue

        m_sys = _SYSTEM_RE.match(line)
        if m_sys:
            system_status = {"value": m_sys.group(1).upper(), "line": idx}

    return stages, checks, system_status


def evaluate_report(text: str, report_path: str = "") -> Dict[str, Any]:
    stages, checks, system_status = _parse_report(text)
    findings: List[Dict[str, Any]] = []

    for sid in STAGE_IDS:
        if sid not in stages:
            _add_finding(findings, "MISSING_STAGE", f"Missing required stage line: {sid}")
            continue

        stage = stages[sid]
        if sid in OPTIONAL_STAGE_IDS:
            allowed = {"PASS", "FAIL", "NIE_URUCHAMIANO"}
        else:
            allowed = {"PASS", "FAIL"}
        if stage["status"] not in allowed:
            _add_finding(
                findings,
                "INVALID_STAGE_STATUS",
                f"Invalid stage status for {sid}: {stage['status']}; allowed={sorted(allowed)}",
                line=int(stage.get("line", 0)),
            )

        if _is_placeholder(stage.get("evidence", "")):
            _add_finding(
                findings,
                "EVIDENCE_REQUIRED_STAGE",
                f"Stage {sid} has missing/placeholder evidence",
                line=int(stage.get("line", 0)),
            )

        if "_duplicate_line" in stage:
            _add_finding(
                findings,
                "DUPLICATE_STAGE",
                f"Duplicate stage entry for {sid}",
                line=int(stage.get("_duplicate_line", 0)),
            )

    for cid in CHECKLIST_IDS:
        if cid not in checks:
            _add_finding(findings, "MISSING_CHECK", f"Missing required checklist line: {cid}")
            continue
        check = checks[cid]
        if check["status"] not in {"PASS", "FAIL"}:
            _add_finding(
                findings,
                "INVALID_CHECK_STATUS",
                f"Invalid checklist status for {cid}: {check['status']}",
                line=int(check.get("line", 0)),
            )
        if _is_placeholder(check.get("evidence", "")):
            _add_finding(
                findings,
                "EVIDENCE_REQUIRED_CHECK",
                f"Checklist {cid} has missing/placeholder evidence",
                line=int(check.get("line", 0)),
            )
        if "_duplicate_line" in check:
            _add_finding(
                findings,
                "DUPLICATE_CHECK",
                f"Duplicate checklist entry for {cid}",
                line=int(check.get("_duplicate_line", 0)),
            )

    computed_status = "NIEGOTOWY"
    checklist_all_pass = True
    for cid in CHECKLIST_IDS:
        check = checks.get(cid)
        if not check:
            checklist_all_pass = False
            break
        if check.get("status") != "PASS":
            checklist_all_pass = False
            break
        if _is_placeholder(check.get("evidence", "")):
            checklist_all_pass = False
            break
    if checklist_all_pass:
        computed_status = "GOTOWY"

    reported_status = (system_status.get("value") or "").upper().strip()
    if not reported_status:
        _add_finding(findings, "MISSING_SYSTEM_STATUS", "Missing line: - SYSTEM_STATUS: GOTOWY/NIEGOTOWY")
    elif reported_status not in {"GOTOWY", "NIEGOTOWY"}:
        _add_finding(
            findings,
            "INVALID_SYSTEM_STATUS",
            f"Invalid SYSTEM_STATUS: {reported_status}",
            line=int(system_status.get("line", 0)),
        )
    elif reported_status != computed_status:
        _add_finding(
            findings,
            "SYSTEM_STATUS_MISMATCH",
            f"SYSTEM_STATUS={reported_status} but computed={computed_status} from C01..C50",
            line=int(system_status.get("line", 0)),
        )

    stage_counts = {"PASS": 0, "FAIL": 0, "NIE_URUCHAMIANO": 0}
    for sid in STAGE_IDS:
        st = stages.get(sid, {}).get("status", "")
        if st in stage_counts:
            stage_counts[st] += 1

    check_counts = {"PASS": 0, "FAIL": 0}
    for cid in CHECKLIST_IDS:
        st = checks.get(cid, {}).get("status", "")
        if st in check_counts:
            check_counts[st] += 1

    audit_pass = computed_status == "GOTOWY"
    contract_ok = len(findings) == 0
    gate_ok = bool(contract_ok and audit_pass)

    result: Dict[str, Any] = {
        "schema_version": 1,
        "tool": "validate_audit_checklist_v1_2",
        "ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "report_path": report_path,
        "expected": {
            "stages": STAGE_IDS,
            "optional_stages": sorted(OPTIONAL_STAGE_IDS),
            "checklist": CHECKLIST_IDS,
            "system_status_rule": "GOTOWY iff C01..C50 are all PASS with non-placeholder evidence",
        },
        "parsed": {
            "stages": stages,
            "checklist": checks,
            "system_status": system_status,
        },
        "summary": {
            "stage_counts": stage_counts,
            "check_counts": check_counts,
            "reported_system_status": reported_status,
            "computed_system_status": computed_status,
            "audit_pass": audit_pass,
            "contract_ok": contract_ok,
        },
        "findings": findings,
        "gate": {
            "ok": gate_ok,
            "exit_code": 0 if gate_ok else 1,
        },
    }
    return result


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Validate OANDA_MT5_SYSTEM V1.2 audit checklist report template.",
    )
    ap.add_argument("--report", required=True, help="Path to text/markdown audit report.")
    ap.add_argument("--out", default="", help="Optional output JSON report path.")
    ap.add_argument("--print-json", action="store_true", help="Print JSON result to stdout.")
    args = ap.parse_args()

    report_path = Path(args.report)
    if not report_path.exists() or not report_path.is_file():
        err = {
            "schema_version": 1,
            "tool": "validate_audit_checklist_v1_2",
            "ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "report_path": str(report_path),
            "findings": [
                {
                    "id": "REPORT_NOT_FOUND",
                    "severity": "ERROR",
                    "message": f"Report file not found: {report_path}",
                }
            ],
            "gate": {"ok": False, "exit_code": 2},
        }
        payload = json.dumps(err, indent=2, ensure_ascii=False)
        if args.out:
            out_path = Path(args.out)
            out_path.parent.mkdir(parents=True, exist_ok=True)
            out_path.write_text(payload + "\n", encoding="utf-8")
        if args.print_json or not args.out:
            print(payload)
        return 2

    text = report_path.read_text(encoding="utf-8", errors="replace")
    result = evaluate_report(text=text, report_path=str(report_path))
    payload = json.dumps(result, indent=2, ensure_ascii=False)

    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(payload + "\n", encoding="utf-8")
    if args.print_json or not args.out:
        print(payload)
    return int(result["gate"]["exit_code"])


if __name__ == "__main__":
    raise SystemExit(main())
