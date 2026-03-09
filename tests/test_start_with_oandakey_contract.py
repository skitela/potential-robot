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
        "Get-BridgeHeartbeatOkAgeSec",
        "FAIL_RUNTIME_NOT_READY",
        "PASS_READY",
        "Wait-RuntimeReady -RuntimeRoot $runtimeRoot -Profile $Profile -TimeoutSec 120 -PollSec 3",
    )
    for token in required_tokens:
        assert token in script, f"Missing runtime-ready token: {token}"
