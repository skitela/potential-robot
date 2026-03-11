from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _read(rel_path: str) -> str:
    return (ROOT / rel_path).read_text(encoding="utf-8", errors="ignore")


def test_audit_offline_resolves_python_explicitly() -> None:
    script = _read("RUN/AUDIT_OFFLINE.ps1")
    required = (
        "function Resolve-PythonExe",
        '$pythonExe = Resolve-PythonExe -RuntimeRoot $Root',
        '[AUDIT_OFFLINE] Python=$pythonExe',
        '& $pythonExe (Join-Path $Root "TOOLS\\runtime_housekeeping.py")',
        '& $pythonExe @args',
    )
    for token in required:
        assert token in script


def test_preflight_safe_resolves_python_explicitly() -> None:
    script = _read("RUN/PREFLIGHT_SAFE.ps1")
    required = (
        "function Resolve-PythonExe",
        '$pythonExe = Resolve-PythonExe -RuntimeRoot $Root',
        '$pythonExeCmd = \'"\' + $pythonExe + \'"\'',
        'PYTHON=$pythonExe',
        'Invoke-Step -Name "compile"',
        '$pythonExeCmd TOOLS\\\\smoke_compile_v6_2.py',
        '$pythonExeCmd test_dyrygent_external.py',
        '$pythonExeCmd -m unittest',
    )
    for token in required:
        assert token in script


def test_generate_and_validate_audit_entrypoints_resolve_python_explicitly() -> None:
    generate_script = _read("RUN/GENERATE_AUDIT_REPORT_V1_2.ps1")
    validate_script = _read("RUN/VALIDATE_AUDIT_CHECKLIST_V1_2.ps1")

    for token in (
        "function Resolve-PythonExe",
        '$pythonExe = Resolve-PythonExe -RuntimeRoot $Root',
        '[GENERATE_AUDIT_REPORT_V1_2] Python=$pythonExe',
        '& $pythonExe @argsList',
    ):
        assert token in generate_script

    for token in (
        "function Resolve-PythonExe",
        '$pythonExe = Resolve-PythonExe -RuntimeRoot $Root',
        '[VALIDATE_AUDIT_CHECKLIST_V1_2] Python=$pythonExe',
        '& $pythonExe $validator --report $Report --out $Out',
    ):
        assert token in validate_script
