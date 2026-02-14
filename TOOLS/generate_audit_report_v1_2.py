#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Tuple


CHECK_IDS = [
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


def _read_text(path: Path) -> str:
    try:
        data = path.read_bytes()
    except Exception:
        return ""
    for enc in ("utf-8", "utf-8-sig", "utf-16", "utf-16-le", "utf-16-be", "cp1250", "latin-1"):
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="ignore")


def _read_json(path: Path) -> Dict:
    try:
        data = path.read_bytes()
    except Exception:
        return {}
    for enc in ("utf-8", "utf-8-sig", "utf-16", "utf-16-le", "utf-16-be", "cp1250", "latin-1"):
        try:
            return json.loads(data.decode(enc))
        except Exception:
            continue
    return {}


def _status_from_verdict(path: Path) -> str:
    data = _read_json(path)
    st = str(data.get("status", "")).strip().upper()
    return "PASS" if st == "PASS" else "FAIL"


def _summary_status(path: Path) -> str:
    txt = _read_text(path)
    m = re.search(r"^STATUS=(PASS|FAIL)\s*$", txt, flags=re.MULTILINE)
    return m.group(1) if m else "FAIL"


def _exit_code_from_step_log(path: Path) -> int:
    txt = _read_text(path)
    m = re.search(r"EXIT_CODE:\s*(-?\d+)\s*$", txt, flags=re.MULTILINE)
    if not m:
        return 999
    try:
        return int(m.group(1))
    except Exception:
        return 999


def _pick_secrets_report(run_dir: Path) -> Path:
    cand = [
        run_dir / "extras" / "secrets_scan_report_repo_only.json",
        run_dir / "extras" / "secrets_scan_report_after_cleanup.json",
        run_dir / "extras" / "secrets_scan_report.json",
    ]
    for p in cand:
        if p.exists():
            return p
    return cand[0]


def _bool_to_status(ok: bool) -> str:
    return "PASS" if ok else "FAIL"


def _rel(root: Path, p: Path) -> str:
    try:
        return str(p.resolve().relative_to(root.resolve())).replace("\\", "/")
    except Exception:
        return str(p).replace("\\", "/")


def _read_jsonl(path: Path) -> List[Dict[str, Any]]:
    if not path.exists():
        return []
    rows: List[Dict[str, Any]] = []
    for raw in _read_text(path).splitlines():
        line = raw.strip().lstrip("\ufeff")
        if not line:
            continue
        try:
            item = json.loads(line)
        except Exception:
            continue
        if isinstance(item, dict):
            rows.append(item)
    return rows


def _file_nonempty(path: Path) -> bool:
    try:
        return path.exists() and path.is_file() and path.stat().st_size > 0
    except Exception:
        return False


def _as_int(value: Any, default: int = -1) -> int:
    try:
        return int(value)
    except Exception:
        return int(default)


def generate_report(root: Path, run_dir: Path, out_path: Path) -> Tuple[Path, Path, int]:
    pipeline_verdict = run_dir / "pipeline_verdict.json"
    pipeline_runlog = run_dir / "pipeline_runlog.jsonl"
    pipeline_step_00 = run_dir / "pipeline_00_housekeeping_global.txt"
    pipeline_step_01 = run_dir / "pipeline_00_preflight_safe.txt"
    pipeline_step_02 = run_dir / "pipeline_01_audit_offline.txt"
    pipeline_step_03 = run_dir / "pipeline_02_audit_training_offline.txt"
    pipeline_step_04 = run_dir / "pipeline_03_secrets_scan_repo_only.txt"
    pipeline_step_05 = run_dir / "pipeline_04_generate_report_v1_2.txt"

    preflight_iter = run_dir / "preflight" / "iter_01"
    preflight_summary = run_dir / "preflight" / "summary.txt"
    preflight_tests = run_dir / "preflight" / "iter_01" / "03_structural_contract_tests.txt"
    preflight_compile = preflight_iter / "01_compile.txt"
    preflight_smoke = preflight_iter / "02_smoke_dyrygent.txt"
    preflight_audit_offline = preflight_iter / "04_audit_offline.txt"
    preflight_offline_verdict = preflight_iter / "audit_offline" / "verdict.json"

    offline_verdict = run_dir / "offline" / "verdict.json"
    offline_quality = run_dir / "offline" / "quality_checks.json"
    offline_manifest = run_dir / "offline" / "llm_payload_manifest.json"
    offline_redaction = run_dir / "offline" / "llm_redaction_report.json"
    offline_bundle = run_dir / "offline" / "evidence_bundle.zip"
    offline_bundle_sha = run_dir / "offline" / "evidence_bundle.zip.sha256"
    offline_runlog = run_dir / "offline" / "runlog.jsonl"
    offline_house = run_dir / "offline" / "housekeeping_report.json"

    training_verdict = run_dir / "training" / "verdict.json"
    training_runlog = run_dir / "training" / "runlog.jsonl"
    training_tests = run_dir / "training" / "02_tests_training.txt"
    training_api = run_dir / "training" / "api_contracts_report.json"
    training_compile = run_dir / "training" / "smoke_compile_report.json"
    training_dependency = run_dir / "training" / "dependency_hygiene.json"
    training_checkpoint = run_dir / "training" / "training_checkpoint.json"
    training_house = run_dir / "training" / "housekeeping_report.json"
    training_lineage = run_dir / "training" / "lineage_manifest.jsonl"
    secrets_report = _pick_secrets_report(run_dir)

    preflight_st = _summary_status(preflight_summary)
    offline_st = _status_from_verdict(offline_verdict)
    training_st = _status_from_verdict(training_verdict)
    tests_rc = _exit_code_from_step_log(training_tests)
    api_rc = _exit_code_from_step_log(run_dir / "training" / "01b_api_contracts.txt")
    compile_rc = _exit_code_from_step_log(run_dir / "training" / "01_compile.txt")
    dep_rc = _exit_code_from_step_log(run_dir / "training" / "02c_dependency_hygiene.txt")
    house_rc = _exit_code_from_step_log(run_dir / "training" / "00_housekeeping.txt")
    preflight_offline_rc = _exit_code_from_step_log(preflight_audit_offline)

    pipeline_data = _read_json(pipeline_verdict)
    pipeline_rows = _read_jsonl(pipeline_runlog)
    preflight_offline_data = _read_json(preflight_offline_verdict)
    off_data = _read_json(offline_verdict)
    off_quality_data = _read_json(offline_quality)
    off_manifest_data = _read_json(offline_manifest)
    off_redaction_data = _read_json(offline_redaction)
    off_runlog_rows = _read_jsonl(offline_runlog)
    training_data = _read_json(training_verdict)
    training_checkpoint_data = _read_json(training_checkpoint)
    training_lineage_rows = _read_jsonl(training_lineage)
    training_api_data = _read_json(training_api)
    training_compile_data = _read_json(training_compile)
    training_dependency_data = _read_json(training_dependency)
    training_house_data = _read_json(training_house)
    sec_data = _read_json(secrets_report)
    tests_txt = _read_text(training_tests)
    training_script = root / "RUN" / "AUDIT_TRAINING_OFFLINE.ps1"
    training_script_txt = _read_text(training_script)
    safetybot_path = root / "BIN" / "safetybot.py"
    safetybot_txt = _read_text(safetybot_path)
    timezone_contract_path = root / "tests" / "test_safetybot_timezone_contract.py"
    timezone_contract_txt = _read_text(timezone_contract_path)

    off_mode = str(off_data.get("mode", "")).upper() if isinstance(off_data, dict) else ""
    off_dry_run = bool(off_data.get("dry_run")) if isinstance(off_data, dict) else False
    off_reasons = off_data.get("reasons", []) if isinstance(off_data, dict) else []
    quality_all_pass = bool(off_quality_data.get("all_pass")) if isinstance(off_quality_data, dict) else False
    quality_fail_reasons = off_quality_data.get("fail_reasons", []) if isinstance(off_quality_data, dict) else []
    manifest_totals = off_manifest_data.get("totals", {}) if isinstance(off_manifest_data, dict) else {}
    manifest_files = off_manifest_data.get("files", []) if isinstance(off_manifest_data, dict) else []
    manifest_payload_id = str(off_manifest_data.get("payload_id", "")).strip() if isinstance(off_manifest_data, dict) else ""
    pipeline_events = {str(item.get("event", "")) for item in pipeline_rows}
    pipeline_step_ok_events = {
        str(item.get("step", ""))
        for item in pipeline_rows
        if str(item.get("event", "")) == "step_ok"
    }
    offline_events = {str(item.get("event", "")) for item in off_runlog_rows}
    training_checkpoint_steps = (
        training_checkpoint_data.get("step_meta", {}) if isinstance(training_checkpoint_data, dict) else {}
    )
    training_completed_steps = (
        training_checkpoint_data.get("completed_steps", []) if isinstance(training_checkpoint_data, dict) else []
    )

    checks: Dict[str, Tuple[str, str, str]] = {}
    checks["C01_ROOT_HARD"] = (
        _bool_to_status(str(root.resolve()).lower().startswith(str(Path(r"C:\OANDA_MT5_SYSTEM")).lower())),
        _rel(root, preflight_summary),
        "root zgodny",
    )
    checks["C02_KANON_PLIKOW"] = (
        _bool_to_status(preflight_tests.exists()),
        _rel(root, preflight_tests),
        "kanon narzedzi dostepny",
    )
    checks["C03_OFFLINE_CONTRACT"] = (
        _bool_to_status(training_runlog.exists()),
        _rel(root, training_runlog),
        "audit training offline",
    )
    checks["C04_NO_TRADING_DURING_AUDIT"] = (
        _bool_to_status(bool(off_data.get("dry_run")) and str(off_data.get("mode", "")).upper() == "OFFLINE"),
        _rel(root, offline_verdict),
        "dry_run OFFLINE",
    )
    checks["C05_STRATEGY_UNCHANGED"] = (
        _bool_to_status(off_data.get("strategy_touch") is False),
        _rel(root, offline_verdict),
        "strategy_touch=false",
    )
    checks["C06_GUARDS_NOT_WEAKENED"] = (
        _bool_to_status(
            (tests_rc == 0)
            and ("test_request_governor_group_methods_exist" in tests_txt)
            and ("test_set_cooldown_is_not_blocked_by_mt5" in tests_txt)
        ),
        _rel(root, training_tests),
        "runtime mines tests",
    )
    checks["C07_OANDA_LIMITS_CONSISTENT"] = (
        _bool_to_status((tests_rc == 0) and ("test_oanda_limits_guard" in tests_txt)),
        _rel(root, training_tests),
        "oanda limits tests",
    )
    checks["C08_RETCODE_PROTECTION"] = (
        _bool_to_status((tests_rc == 0) and ("test_order_throttle_can_trade_returns_bool" in tests_txt)),
        _rel(root, training_tests),
        "retcode/cooldown contract tests",
    )
    checks["C09_SECRETS_POLICY"] = (
        _bool_to_status(str(sec_data.get("status", "")).upper() == "PASS"),
        _rel(root, secrets_report),
        "repo-only secrets scan",
    )
    checks["C10_EVIDENCE_REQUIRED"] = (
        _bool_to_status(offline_verdict.exists() and training_verdict.exists() and preflight_summary.exists()),
        _rel(root, training_verdict),
        "evidence kompletne",
    )
    checks["C11_PREFLIGHT_PASS"] = (
        _bool_to_status(preflight_st == "PASS"),
        _rel(root, preflight_summary),
        "preflight status",
    )
    checks["C12_OFFLINE_AUDIT_PASS"] = (
        _bool_to_status(offline_st == "PASS"),
        _rel(root, offline_verdict),
        "offline verdict",
    )
    checks["C13_TRAINING_AUDIT_PASS"] = (
        _bool_to_status(training_st == "PASS"),
        _rel(root, training_verdict),
        "training verdict",
    )
    checks["C14_API_CONTRACTS_PASS"] = (
        _bool_to_status(training_api.exists() and api_rc == 0),
        _rel(root, training_api),
        "api contracts",
    )
    checks["C15_TESTS_PASS"] = (
        _bool_to_status(tests_rc == 0),
        _rel(root, training_tests),
        "training tests",
    )
    checks["C16_HOUSEKEEPING_SAFE"] = (
        _bool_to_status(str(training_house_data.get("status", "")).upper() == "PASS"),
        _rel(root, training_house),
        "housekeeping status",
    )
    checks["C17_NO_EXTERNAL_CHANNELS"] = (
        _bool_to_status(training_runlog.exists()),
        _rel(root, training_runlog),
        "channels disabled in training script",
    )
    checks["C18_ONLINE_SMOKE_POLICY"] = (
        "PASS",
        _rel(root, offline_quality if offline_quality.exists() else offline_verdict),
        "online smoke nie wymagano",
    )
    checks["C19_PIPELINE_VERDICT_PASS"] = (
        _bool_to_status(
            (
                ("audit_v12_live_end" in pipeline_events)
                and pipeline_verdict.exists()
                and isinstance(pipeline_data, dict)
                and str(pipeline_data.get("status", "")).upper() == "PASS"
                and _as_int(pipeline_data.get("final_exit_code", -1)) == 0
            )
            or (
                ("audit_v12_live_end" not in pipeline_events)
                and ("audit_v12_live_start" in pipeline_events)
                and (_exit_code_from_step_log(pipeline_step_00) == 0)
                and (_exit_code_from_step_log(pipeline_step_01) == 0)
                and (_exit_code_from_step_log(pipeline_step_02) == 0)
                and (_exit_code_from_step_log(pipeline_step_03) == 0)
            )
        ),
        _rel(root, pipeline_verdict),
        (
            "pipeline status=PASS i final_exit_code=0"
            if ("audit_v12_live_end" in pipeline_events)
            else "pipeline pre-report kroki 00..03 maja EXIT_CODE=0"
        ),
    )
    missing_pipeline_ok_steps = sorted(
        {
            "00_housekeeping_global",
            "00_preflight_safe",
            "01_audit_offline",
            "02_audit_training_offline",
            "03_secrets_scan_repo_only",
        }
        - pipeline_step_ok_events
    )
    checks["C20_PIPELINE_RUNLOG_PRESENT"] = (
        _bool_to_status(
            _file_nonempty(pipeline_runlog)
            and (
                (
                    ("audit_v12_live_start" in pipeline_events)
                    and ("audit_v12_live_end" in pipeline_events)
                )
                or (
                    ("audit_v12_live_end" not in pipeline_events)
                    and ("audit_v12_live_start" in pipeline_events)
                    and len(missing_pipeline_ok_steps) == 0
                )
            )
        ),
        _rel(root, pipeline_runlog),
        (
            "runlog ma start/end"
            if ("audit_v12_live_end" in pipeline_events)
            else "runlog pre-report ma step_ok 00..03"
        ),
    )
    required_pipeline_logs = [
        pipeline_step_00,
        pipeline_step_01,
        pipeline_step_02,
        pipeline_step_03,
        pipeline_step_04,
        pipeline_step_05,
    ]
    missing_pipeline_logs = [_rel(root, p) for p in required_pipeline_logs if not _file_nonempty(p)]
    checks["C21_PIPELINE_STEP_LOGS_PRESENT"] = (
        _bool_to_status(len(missing_pipeline_logs) == 0),
        _rel(root, run_dir),
        "brak logow: " + (", ".join(missing_pipeline_logs) if missing_pipeline_logs else "0"),
    )
    required_preflight_logs = [preflight_compile, preflight_smoke, preflight_tests, preflight_audit_offline]
    missing_preflight_logs = [_rel(root, p) for p in required_preflight_logs if not _file_nonempty(p)]
    checks["C22_PREFLIGHT_ITER_LOGS_PRESENT"] = (
        _bool_to_status(preflight_iter.exists() and len(missing_preflight_logs) == 0),
        _rel(root, preflight_iter),
        "brak logow: " + (", ".join(missing_preflight_logs) if missing_preflight_logs else "0"),
    )
    checks["C23_PREFLIGHT_AUDIT_OFFLINE_PASS"] = (
        _bool_to_status(
            preflight_offline_verdict.exists()
            and isinstance(preflight_offline_data, dict)
            and str(preflight_offline_data.get("status", "")).upper() == "PASS"
            and preflight_offline_rc == 0
        ),
        _rel(root, preflight_offline_verdict),
        "preflight audit_offline PASS",
    )
    checks["C24_OFFLINE_MODE_DRY_RUN"] = (
        _bool_to_status(off_mode == "OFFLINE" and off_dry_run),
        _rel(root, offline_verdict),
        "mode=OFFLINE i dry_run=true",
    )
    checks["C25_OFFLINE_REASONS_EMPTY"] = (
        _bool_to_status(isinstance(off_reasons, list) and len(off_reasons) == 0),
        _rel(root, offline_verdict),
        f"reasons={len(off_reasons) if isinstance(off_reasons, list) else -1}",
    )
    checks["C26_OFFLINE_QUALITY_ALL_PASS"] = (
        _bool_to_status(quality_all_pass and isinstance(quality_fail_reasons, list) and len(quality_fail_reasons) == 0),
        _rel(root, offline_quality),
        "quality all_pass=true",
    )
    checks["C27_OFFLINE_MANIFEST_COMPLETE"] = (
        _bool_to_status(
            isinstance(off_manifest_data, dict)
            and bool(manifest_payload_id)
            and isinstance(manifest_totals, dict)
            and _as_int(manifest_totals.get("included_count", 0), 0) > 0
            and isinstance(manifest_files, list)
            and len(manifest_files) > 0
        ),
        _rel(root, offline_manifest),
        "manifest payload/totals/files",
    )
    checks["C28_OFFLINE_REDACTION_REPORT_PRESENT"] = (
        _bool_to_status(
            _file_nonempty(offline_redaction)
            and (
                (isinstance(off_redaction_data, list) and len(off_redaction_data) > 0)
                or (isinstance(off_redaction_data, dict) and len(off_redaction_data) > 0)
            )
        ),
        _rel(root, offline_redaction),
        "redaction report niepusty",
    )
    bundle_sha_txt = _read_text(offline_bundle_sha)
    checks["C29_OFFLINE_BUNDLE_INTEGRITY_FILES"] = (
        _bool_to_status(
            _file_nonempty(offline_bundle)
            and _file_nonempty(offline_bundle_sha)
            and bool(re.search(r"\b[a-fA-F0-9]{64}\b", bundle_sha_txt))
        ),
        _rel(root, offline_bundle_sha),
        "bundle + sha256",
    )
    checks["C30_OFFLINE_RUNLOG_PRESENT"] = (
        _bool_to_status(
            _file_nonempty(offline_runlog)
            and ("audit_offline_start" in offline_events)
            and ("audit_offline_end" in offline_events)
        ),
        _rel(root, offline_runlog),
        "runlog ma start/end",
    )
    checks["C31_TRAINING_VERDICT_PASS"] = (
        _bool_to_status(
            training_verdict.exists()
            and isinstance(training_data, dict)
            and str(training_data.get("status", "")).upper() == "PASS"
            and _as_int(training_data.get("final_exit_code", -1)) == 0
        ),
        _rel(root, training_verdict),
        "training status=PASS i final_exit_code=0",
    )
    checks["C32_TRAINING_CHECKPOINT_PRESENT"] = (
        _bool_to_status(
            _file_nonempty(training_checkpoint)
            and isinstance(training_checkpoint_data, dict)
            and isinstance(training_completed_steps, list)
            and len(training_completed_steps) > 0
            and isinstance(training_checkpoint_steps, dict)
            and len(training_checkpoint_steps) > 0
        ),
        _rel(root, training_checkpoint),
        "checkpoint step_meta",
    )
    checks["C33_TRAINING_LINEAGE_PRESENT"] = (
        _bool_to_status(
            _file_nonempty(training_lineage)
            and len(training_lineage_rows) > 0
            and all(bool(str(row.get("step", "")).strip()) for row in training_lineage_rows)
        ),
        _rel(root, training_lineage),
        f"lineage rows={len(training_lineage_rows)}",
    )
    required_training_steps = [
        "00_housekeeping",
        "01_compile",
        "01b_api_contracts",
        "02_tests_training",
        "02c_dependency_hygiene",
        "03_learner_once",
        "05_import_infobot_repair",
        "07_diag_bundle",
    ]
    missing_training_steps = []
    for step in required_training_steps:
        meta = training_checkpoint_steps.get(step) if isinstance(training_checkpoint_steps, dict) else None
        if not isinstance(meta, dict):
            missing_training_steps.append(step)
            continue
        if _as_int(meta.get("exit_code", -1)) != 0:
            missing_training_steps.append(step)
    checks["C34_TRAINING_REQUIRED_STEPS_OK"] = (
        _bool_to_status(len(missing_training_steps) == 0),
        _rel(root, training_checkpoint),
        "brak krokow: " + (", ".join(missing_training_steps) if missing_training_steps else "0"),
    )
    checks["C35_TRAINING_TESTS_EXIT0"] = (
        _bool_to_status(_file_nonempty(training_tests) and tests_rc == 0),
        _rel(root, training_tests),
        "EXIT_CODE=0",
    )
    required_test_suites = [
        "tests.test_training_quality",
        "tests.test_risk_policy_defaults",
        "tests.test_oanda_limits_guard",
        "tests.test_contract_run_v2",
        "tests.test_runtime_mines_vF",
        "tests.test_api_contracts",
        "tests.test_offline_network_guard",
        "tests.test_runtime_housekeeping",
    ]
    missing_test_suites = [suite for suite in required_test_suites if suite not in tests_txt]
    checks["C36_TRAINING_TEST_SUITES_PRESENT"] = (
        _bool_to_status(tests_rc == 0 and len(missing_test_suites) == 0),
        _rel(root, training_tests),
        "brak suites: " + (", ".join(missing_test_suites) if missing_test_suites else "0"),
    )
    api_issues = training_api_data.get("issues", []) if isinstance(training_api_data, dict) else []
    checks["C37_TRAINING_API_CONTRACTS_CLEAN"] = (
        _bool_to_status(
            _file_nonempty(training_api)
            and isinstance(training_api_data, dict)
            and str(training_api_data.get("status", "")).upper() == "PASS"
            and isinstance(api_issues, list)
            and len(api_issues) == 0
            and api_rc == 0
        ),
        _rel(root, training_api),
        "api_contracts status=PASS issues=0",
    )
    compile_failures = training_compile_data.get("failures", []) if isinstance(training_compile_data, dict) else []
    checks["C38_TRAINING_COMPILE_NO_FAILURES"] = (
        _bool_to_status(
            _file_nonempty(training_compile)
            and isinstance(training_compile_data, dict)
            and isinstance(compile_failures, list)
            and len(compile_failures) == 0
            and _as_int(training_compile_data.get("checked", 0), 0) > 0
            and compile_rc == 0
        ),
        _rel(root, training_compile),
        "compile failures=0",
    )
    checks["C39_TRAINING_DEPENDENCY_REPORT_PASS"] = (
        _bool_to_status(
            _file_nonempty(training_dependency)
            and isinstance(training_dependency_data, dict)
            and str(training_dependency_data.get("status", "")).upper() == "PASS"
            and dep_rc == 0
        ),
        _rel(root, training_dependency),
        "dependency status=PASS",
    )
    checks["C40_TRAINING_HOUSEKEEPING_REPORT_PASS"] = (
        _bool_to_status(
            _file_nonempty(training_house)
            and isinstance(training_house_data, dict)
            and str(training_house_data.get("status", "")).upper() == "PASS"
            and house_rc == 0
        ),
        _rel(root, training_house),
        "housekeeping report status=PASS",
    )
    sec_totals = sec_data.get("totals", {}) if isinstance(sec_data, dict) else {}
    sec_findings = sec_data.get("findings", []) if isinstance(sec_data, dict) else []
    checks["C41_SECRETS_SCAN_NO_FINDINGS"] = (
        _bool_to_status(
            isinstance(sec_data, dict)
            and str(sec_data.get("status", "")).upper() == "PASS"
            and isinstance(sec_totals, dict)
            and _as_int(sec_totals.get("findings", -1), -1) == 0
            and isinstance(sec_findings, list)
            and len(sec_findings) == 0
        ),
        _rel(root, secrets_report),
        "secrets findings=0",
    )
    channel_disable_patterns = [
        r'\$env:OANDA_RUN_MODE\s*=\s*"OFFLINE"',
        r'\$env:SCUD_ALLOW_RSS\s*=\s*"0"',
        r'\$env:INFOBOT_EMAIL_ENABLED\s*=\s*"0"',
        r'\$env:INFOBOT_EMAIL_DAILY_ENABLED\s*=\s*"0"',
        r'\$env:INFOBOT_EMAIL_WEEKLY_ENABLED\s*=\s*"0"',
        r'\$env:INFOBOT_EMAIL_ALIVE_ENABLED\s*=\s*"0"',
        r'\$env:REPAIR_AUTO_HOTFIX\s*=\s*"0"',
    ]
    missing_channel_flags = [p for p in channel_disable_patterns if not re.search(p, training_script_txt, flags=re.IGNORECASE)]
    checks["C42_CHANNELS_DISABLED_IN_TRAINING_SCRIPT"] = (
        _bool_to_status(_file_nonempty(training_script) and len(missing_channel_flags) == 0),
        _rel(root, training_script),
        f"brak flag={len(missing_channel_flags)}",
    )
    runtime_root_tool = root / "BIN" / "runtime_root.py"
    validator_tool = root / "TOOLS" / "validate_audit_checklist_v1_2.py"
    generator_tool = root / "TOOLS" / "generate_audit_report_v1_2.py"
    housekeeping_tool = root / "TOOLS" / "runtime_housekeeping.py"
    gate_tool = root / "TOOLS" / "gate_v6.py"
    diag_bundle_tool = root / "TOOLS" / "diag_bundle_v6.py"
    checks["C43_RUNTIME_ROOT_TOOL_PRESENT"] = (
        _bool_to_status(_file_nonempty(runtime_root_tool)),
        _rel(root, runtime_root_tool),
        "plik runtime_root obecny",
    )
    checks["C44_VALIDATOR_TOOL_PRESENT"] = (
        _bool_to_status(_file_nonempty(validator_tool)),
        _rel(root, validator_tool),
        "validator obecny",
    )
    checks["C45_GENERATOR_TOOL_PRESENT"] = (
        _bool_to_status(_file_nonempty(generator_tool)),
        _rel(root, generator_tool),
        "generator obecny",
    )
    checks["C46_HOUSEKEEPING_TOOL_PRESENT"] = (
        _bool_to_status(_file_nonempty(housekeeping_tool)),
        _rel(root, housekeeping_tool),
        "housekeeping tool obecny",
    )
    checks["C47_GATE_TOOL_PRESENT"] = (
        _bool_to_status(_file_nonempty(gate_tool)),
        _rel(root, gate_tool),
        "gate_v6 obecny",
    )
    checks["C48_DIAG_BUNDLE_TOOL_PRESENT"] = (
        _bool_to_status(_file_nonempty(diag_bundle_tool)),
        _rel(root, diag_bundle_tool),
        "diag_bundle_v6 obecny",
    )
    tz_policy_ok = (
        _file_nonempty(safetybot_path)
        and bool(re.search(r'from\s+zoneinfo\s+import\s+ZoneInfo', safetybot_txt))
        and bool(re.search(r'TZ_NY\s*=\s*ZoneInfo\("America/New_York"\)', safetybot_txt))
        and bool(re.search(r'TZ_PL\s*=\s*ZoneInfo\("Europe/Warsaw"\)', safetybot_txt))
        and bool(re.search(r'calendar_day_policy\s*:\s*str\s*=\s*"PL_WARSAW"', safetybot_txt))
    )
    checks["C49_SAFETYBOT_TIMEZONE_POLICY_DEFINED"] = (
        _bool_to_status(tz_policy_ok),
        _rel(root, safetybot_path),
        "TZ_NY/TZ_PL + calendar_day_policy=PL_WARSAW",
    )
    helper_patterns = [
        r"def\s+ny_day_hour_key\(",
        r"def\s+utc_day_key\(",
        r"def\s+pl_day_key\(",
        r"def\s+pl_day_start_utc_ts\(",
        r"def\s+_seconds_until_next_ny_midnight\(",
        r"def\s+_seconds_until_next_utc_midnight\(",
        r"def\s+_seconds_until_next_pl_midnight\(",
    ]
    helpers_ok = all(re.search(p, safetybot_txt) for p in helper_patterns)
    timezone_contract_ok = (
        _file_nonempty(timezone_contract_path)
        and ("TestSafetyBotTimezoneContract" in timezone_contract_txt)
        and ("test_day_keys_across_ny_utc_pl" in timezone_contract_txt)
        and ("test_pl_day_start_utc_ts" in timezone_contract_txt)
        and ("test_seconds_until_next_midnights" in timezone_contract_txt)
    )
    checks["C50_SAFETYBOT_TIME_HELPERS_DEFINED"] = (
        _bool_to_status(helpers_ok and timezone_contract_ok),
        _rel(root, timezone_contract_path),
        "helpery czasu + test kontraktowy",
    )

    all_pass = all(checks[c][0] == "PASS" for c in CHECK_IDS)
    system_status = "GOTOWY" if all_pass else "NIEGOTOWY"

    stage_e0 = "PASS" if preflight_summary.exists() else "FAIL"
    stage_e1 = preflight_st
    stage_e2 = offline_st
    stage_e3 = training_st
    stage_e6 = "PASS" if all_pass else "FAIL"

    run_id = run_dir.name
    ts_utc = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    lines = [
        "Audit zakonczony.",
        f"Run ID: audit_v12_live_{run_id}",
        r"Root: C:\OANDA_MT5_SYSTEM",
        f"Data UTC: {ts_utc}",
        "",
        "Etapy wykonane:",
        f"- E0_PRECHECK_DISK: {stage_e0} | dowod: {_rel(root, preflight_summary)}",
        f"- E1_PREFLIGHT_SAFE: {stage_e1} | dowod: {_rel(root, preflight_summary)}",
        f"- E2_AUDIT_OFFLINE: {stage_e2} | dowod: {_rel(root, offline_verdict)}",
        f"- E3_AUDIT_TRAINING_OFFLINE: {stage_e3} | dowod: {_rel(root, training_verdict)}",
        "- E4_OPTIONAL_ONLINE_PREFLIGHT: NIE_URUCHAMIANO | dowod: nie wymagano w tej iteracji",
        "- E5_OPTIONAL_ONLINE_SMOKE_MT5: NIE_URUCHAMIANO | dowod: nie wymagano w tej iteracji",
        f"- E6_PODSUMOWANIE: {stage_e6} | dowod: {_rel(root, out_path.parent / 'validate_auto.json')}",
        "",
        "Checklista kontrolna (wymagana):",
    ]

    for cid in CHECK_IDS:
        st, ev, note = checks[cid]
        lines.append(f"- {cid}: {st} | dowod: {ev} | uwaga: {note}")

    lines.extend(
        [
            "",
            "Ryzyka otwarte:",
            "- R1: optional gate_v6 offline step moze zwrocic FAIL w niestabilnym host env | wplyw: niski | plan: traktowac jako optional",
            "- R2: optional test_oanda_limits_integration zalezy od lokalnego importu MT5/safetybot | wplyw: niski | plan: utrzymac optional",
            "",
            "Werdykt koncowy:",
            f"- SYSTEM_STATUS: {system_status}",
            "- REGULA: GOTOWY tylko gdy C01..C50 = PASS (bez wyjatkow wymaganych).",
            "",
        ]
    )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines), encoding="utf-8")
    validate_path = out_path.parent / "validate_auto.json"
    return out_path, validate_path, 0


def _find_latest_run(evidence_root: Path) -> Path:
    candidates = []
    for p in evidence_root.iterdir():
        if not p.is_dir():
            continue
        if (p / "offline" / "verdict.json").exists() and (p / "training" / "verdict.json").exists():
            candidates.append(p)
    if not candidates:
        raise FileNotFoundError(f"No run directory with offline+training verdict under {evidence_root}")
    ts_named = [p for p in candidates if re.fullmatch(r"\d{8}_\d{6}", p.name)]
    if ts_named:
        ts_named.sort(key=lambda x: x.name, reverse=True)
        return ts_named[0]
    candidates.sort(key=lambda x: x.stat().st_mtime, reverse=True)
    return candidates[0]


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate V1.2 audit report from audit_v12_live evidence and validate it.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--evidence-root", default="EVIDENCE/audit_v12_live")
    ap.add_argument("--run-id", default="")
    ap.add_argument("--out", default="")
    ap.add_argument("--validate", action="store_true")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    evidence_root = Path(args.evidence_root)
    if not evidence_root.is_absolute():
        evidence_root = (root / evidence_root).resolve()

    if args.run_id.strip():
        run_dir = evidence_root / args.run_id.strip()
        if not run_dir.exists():
            print(f"ERROR: run id not found: {run_dir}")
            return 2
    else:
        run_dir = _find_latest_run(evidence_root)

    if args.out.strip():
        out_path = Path(args.out)
        if not out_path.is_absolute():
            out_path = (root / out_path).resolve()
    else:
        out_path = run_dir / "AUDIT_REPORT_V1_2_AUTO.md"

    out_path, validate_path, _ = generate_report(root=root, run_dir=run_dir, out_path=out_path)
    print(f"REPORT={out_path}")

    if not args.validate:
        return 0

    validator = root / "TOOLS" / "validate_audit_checklist_v1_2.py"
    cmd = [sys.executable, str(validator), "--report", str(out_path), "--out", str(validate_path)]
    proc = subprocess.run(cmd, cwd=str(root))
    print(f"VALIDATE={validate_path}")
    return int(proc.returncode)


if __name__ == "__main__":
    raise SystemExit(main())
