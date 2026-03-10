from __future__ import annotations

from pathlib import Path


def test_start_with_oandakey_runs_kernel_config_preseed() -> None:
    script = Path("RUN/START_WITH_OANDAKEY.ps1").read_text(encoding="utf-8", errors="ignore")
    assert "preseed_kernel_config.py" in script
    assert "kernel_config_preseed" in script


def test_start_with_oandakey_waits_for_runtime_ready_contract() -> None:
    script = Path("RUN/START_WITH_OANDAKEY.ps1").read_text(encoding="utf-8", errors="ignore")
    required_tokens = (
        "function Wait-RuntimeReady",
        "function Invoke-SystemControlStatusSafe",
        "Get-BridgeHeartbeatOkAgeSec",
        "reconcile_attempted",
        "Invoke-PowerShellWithTimeout",
        "FAIL_RUNTIME_NOT_READY",
        "PASS_READY",
        "Wait-RuntimeReady -RuntimeRoot $runtimeRoot -Profile $Profile -TimeoutSec 120 -PollSec 3",
    )
    for token in required_tokens:
        assert token in script, f"Missing runtime-ready token: {token}"


def test_start_with_oandakey_has_python_runtime_dependency_preflight() -> None:
    script = Path("RUN/START_WITH_OANDAKEY.ps1").read_text(encoding="utf-8", errors="ignore")
    required_tokens = (
        "function Ensure-RuntimePythonDeps",
        "function Get-MissingRuntimeModules",
        "requirements.live.lock",
        "FAIL_PYTHON_DEPS",
        "python_runtime_deps",
    )
    for token in required_tokens:
        assert token in script, f"Missing python deps preflight token: {token}"


def test_start_with_oandakey_has_single_instance_lock_contract() -> None:
    script = Path("RUN/START_WITH_OANDAKEY.ps1").read_text(encoding="utf-8", errors="ignore")
    required_tokens = (
        "function Acquire-StartPidLock",
        "RUN\\start_with_key.lock",
        "FAIL_LOCK",
        "start_lock_not_acquired",
    )
    for token in required_tokens:
        assert token in script, f"Missing start-lock token: {token}"


def test_start_with_oandakey_profile_setup_has_retry_and_nonfatal_stderr_contract() -> None:
    script = Path("RUN/START_WITH_OANDAKEY.ps1").read_text(encoding="utf-8", errors="ignore")
    required_tokens = (
        "$profileMaxAttempts = 2",
        '$ErrorActionPreference = "Continue"',
        "attempts = [int]$profileAttempt",
        "last_error = [string]$profileLastError",
    )
    for token in required_tokens:
        assert token in script, f"Missing profile-setup resilience token: {token}"
