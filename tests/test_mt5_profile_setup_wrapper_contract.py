from __future__ import annotations

from pathlib import Path


def test_wrapper_calls_python_profile_setup_script() -> None:
    script = Path("TOOLS/setup_mt5_hybrid_profile.ps1").read_text(
        encoding="utf-8", errors="ignore"
    )
    required_tokens = (
        "setup_mt5_hybrid_profile.py",
        "Get-PythonExe",
        "--profile",
        "--focus-group",
        "--no-launch",
        "exit $rc",
    )
    for token in required_tokens:
        assert token in script, f"Missing wrapper token: {token}"
