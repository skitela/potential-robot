from __future__ import annotations

from pathlib import Path


def test_system_control_status_has_strict_safetybot_heartbeat_fallback() -> None:
    script = Path("TOOLS/SYSTEM_CONTROL.ps1").read_text(encoding="utf-8", errors="ignore")
    required_tokens = (
        "function Get-SafetyBotHeartbeatOkAgeSec",
        "heartbeat_ok_age_sec",
        "heartbeat_ok_recent",
        "bridge_peer_ready",
        "duplicate_pids",
        "start_failed_no_lock",
        "([bool]$lockExists -and [bool]$logFresh -and [bool]$heartbeatOkRecent -and (-not [bool]$runningByPid))",
    )
    for token in required_tokens:
        assert token in script, f"Missing SYSTEM_CONTROL contract token: {token}"
