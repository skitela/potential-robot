from __future__ import annotations

import ast
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


FORBIDDEN_RUNTIME_IMPORT_PREFIXES: tuple[str, ...] = (
    "MetaTrader5",
    "safetybot",
    "zeromq_bridge",
    "BIN.safetybot",
    "BIN.zeromq_bridge",
    "MQL5",
)

ALLOWED_WRITE_FILES = {
    "common/outputs.py",
    "common/paths.py",
    "tests/test_safe_read_artifacts.py",
    "tools/runtime_onboarding_preflight.py",
    "tools/operator_dry_run_cycle.py",
}

WRITE_CALL_NAMES = {"write_text", "write_bytes", "unlink", "mkdir", "rmdir", "rename", "touch"}


@dataclass(frozen=True)
class CheckResult:
    name: str
    passed: bool
    details: dict[str, Any]


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def check_required_files(root: Path) -> CheckResult:
    required = [
        root / "DRAFT_MANIFEST.json",
        root / "docs" / "DECISIONS.md",
        root / "docs" / "ARCHITEKTURA_4_AGENTOW_READ_ONLY.md",
        root / "docs" / "README_OBSERVERS_IMPLEMENTATION_CANDIDATE.md",
        root / "docs" / "WDROZENIE_ETAPOWE_PLAN.md",
        root / "tickets_schema" / "codex_ticket_schema_v1.json",
    ]
    missing = [str(p) for p in required if not p.exists()]
    return CheckResult(
        name="required_files",
        passed=len(missing) == 0,
        details={"missing": missing, "required_count": len(required)},
    )


def check_audit_statuses(root: Path) -> CheckResult:
    audit_paths = [
        root / "docs" / "audits" / "audit_1_self.json",
        root / "docs" / "audits" / "audit_2_cross_architecture.json",
        root / "docs" / "audits" / "audit_3_operational_auditability.json",
    ]
    missing = [str(p) for p in audit_paths if not p.exists()]
    statuses: dict[str, str] = {}
    if not missing:
        for p in audit_paths:
            obj = _load_json(p)
            statuses[str(p)] = str(obj.get("status", "UNKNOWN"))
    passed = (len(missing) == 0) and all(v == "PASS" for v in statuses.values())
    return CheckResult(
        name="audit_statuses",
        passed=passed,
        details={"missing": missing, "statuses": statuses},
    )


def check_import_boundaries(root: Path) -> CheckResult:
    violations: list[dict[str, Any]] = []
    py_files = [p for p in root.rglob("*.py") if "__pycache__" not in p.parts]
    for py in py_files:
        tree = ast.parse(py.read_text(encoding="utf-8"), filename=str(py))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    if alias.name.startswith(FORBIDDEN_RUNTIME_IMPORT_PREFIXES):
                        violations.append({"file": str(py), "line": node.lineno, "import": alias.name})
            elif isinstance(node, ast.ImportFrom):
                module = node.module or ""
                if module.startswith(FORBIDDEN_RUNTIME_IMPORT_PREFIXES):
                    violations.append({"file": str(py), "line": node.lineno, "import_from": module})
    return CheckResult(
        name="import_boundaries",
        passed=len(violations) == 0,
        details={"violations": violations, "forbidden_prefixes": FORBIDDEN_RUNTIME_IMPORT_PREFIXES},
    )


def check_write_boundaries(root: Path) -> CheckResult:
    violations: list[dict[str, Any]] = []
    py_files = [p for p in root.rglob("*.py") if "__pycache__" not in p.parts]
    for py in py_files:
        rel = py.relative_to(root).as_posix()
        tree = ast.parse(py.read_text(encoding="utf-8"), filename=str(py))
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            fn = node.func
            write_like = False
            call_name = ""
            if isinstance(fn, ast.Attribute) and fn.attr in WRITE_CALL_NAMES:
                write_like = True
                call_name = fn.attr
            elif isinstance(fn, ast.Name) and fn.id == "open":
                mode = "r"
                if len(node.args) >= 2 and isinstance(node.args[1], ast.Constant) and isinstance(node.args[1].value, str):
                    mode = node.args[1].value
                for kw in node.keywords:
                    if kw.arg == "mode" and isinstance(kw.value, ast.Constant) and isinstance(kw.value.value, str):
                        mode = kw.value.value
                if any(m in mode for m in ("w", "a", "x", "+")):
                    write_like = True
                    call_name = "open_write"
            if write_like and rel not in ALLOWED_WRITE_FILES:
                violations.append({"file": str(py), "line": node.lineno, "call": call_name})
    return CheckResult(
        name="write_boundaries",
        passed=len(violations) == 0,
        details={"violations": violations, "allowed_files": sorted(ALLOWED_WRITE_FILES)},
    )


def run(root: Path) -> dict[str, Any]:
    checks = [
        check_required_files(root),
        check_audit_statuses(root),
        check_import_boundaries(root),
        check_write_boundaries(root),
    ]
    verdict = "GO" if all(c.passed for c in checks) else "NO-GO"
    return {
        "schema_version": "oanda_mt5.observers.runtime_onboarding_preflight.v1",
        "generated_at_utc": _utc_now(),
        "root": str(root),
        "verdict": verdict,
        "checks": [
            {"name": c.name, "passed": c.passed, "details": c.details}
            for c in checks
        ],
    }


def main() -> int:
    root = Path(r"C:\OANDA_MT5_SYSTEM\OBSERVERS_IMPLEMENTATION_CANDIDATE")
    output_dir = root / "docs" / "onboarding"
    output_dir.mkdir(parents=True, exist_ok=True)

    result = run(root)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    json_path = output_dir / f"runtime_onboarding_preflight_{ts}.json"
    txt_path = output_dir / f"runtime_onboarding_preflight_{ts}.txt"

    json_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = [
        "RUNTIME ONBOARDING PREFLIGHT",
        f"generated_at_utc: {result['generated_at_utc']}",
        f"root: {result['root']}",
        f"verdict: {result['verdict']}",
        "",
    ]
    for check in result["checks"]:
        lines.append(f"[{check['name']}] passed={check['passed']}")
    txt_path.write_text("\n".join(lines), encoding="utf-8")

    print(f"WORKSPACE_ROOT_PATH: C:\\OANDA_MT5_SYSTEM")
    print(f"REPORT_JSON_PATH: {json_path}")
    print(f"REPORT_TXT_PATH: {txt_path}")
    print(f"VERDICT: {result['verdict']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
