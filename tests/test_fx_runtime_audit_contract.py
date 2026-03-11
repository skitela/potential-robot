from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_fx_runtime_audit_resolves_python_explicitly() -> None:
    script = (ROOT / "TOOLS" / "fx_runtime_audit_next_window.ps1").read_text(
        encoding="utf-8", errors="ignore"
    )
    required_tokens = (
        "function Find-AuditPythonExe",
        'Join-Path $RuntimeRoot ".venv\\\\Scripts\\\\python.exe"',
        '"C:\\OANDA_VENV\\.venv\\Scripts\\python.exe"',
        'Get-Command python -ErrorAction SilentlyContinue',
        '$pythonExe = Find-AuditPythonExe -RuntimeRoot $runtimeRoot',
        '[FX_AUDIT] using python={0}',
        '& $pythonExe (Join-Path $runtimeRoot "TOOLS\\post_unlock_entry_test.py") --root $runtimeRoot',
    )
    for token in required_tokens:
        assert token in script, f"Missing FX audit python token: {token}"
