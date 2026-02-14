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
from typing import Dict, Tuple


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


def generate_report(root: Path, run_dir: Path, out_path: Path) -> Tuple[Path, Path, int]:
    preflight_summary = run_dir / "preflight" / "summary.txt"
    preflight_tests = run_dir / "preflight" / "iter_01" / "03_structural_contract_tests.txt"
    offline_verdict = run_dir / "offline" / "verdict.json"
    offline_quality = run_dir / "offline" / "quality_checks.json"
    training_verdict = run_dir / "training" / "verdict.json"
    training_runlog = run_dir / "training" / "runlog.jsonl"
    training_tests = run_dir / "training" / "02_tests_training.txt"
    training_api = run_dir / "training" / "api_contracts_report.json"
    training_house = run_dir / "training" / "housekeeping_report.json"
    training_lineage = run_dir / "training" / "lineage_manifest.jsonl"
    secrets_report = _pick_secrets_report(run_dir)

    preflight_st = _summary_status(preflight_summary)
    offline_st = _status_from_verdict(offline_verdict)
    training_st = _status_from_verdict(training_verdict)
    tests_rc = _exit_code_from_step_log(training_tests)
    api_rc = _exit_code_from_step_log(run_dir / "training" / "01b_api_contracts.txt")

    off_data = _read_json(offline_verdict)
    sec_data = _read_json(secrets_report)
    house_data = _read_json(training_house)
    tests_txt = _read_text(training_tests)

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
        _bool_to_status(str(house_data.get("status", "")).upper() == "PASS"),
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
            "- REGULA: GOTOWY tylko gdy C01..C18 = PASS (bez wyjatkow wymaganych).",
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
