from __future__ import annotations

from pathlib import Path


def test_system_control_status_has_strict_safetybot_heartbeat_fallback() -> None:
    script = Path("TOOLS/SYSTEM_CONTROL.ps1").read_text(encoding="utf-8", errors="ignore")
    required_tokens = (
        "function Get-ProcessExecutablePath",
        "function Select-PreferredComponentKeepPid",
        "function Get-SafetyBotHeartbeatOkAgeSec",
        "function Get-SafetyBotBridgeIssueHint",
        "function Get-Mt5ProfileLoadIssueHint",
        "Get-Content -Path $latestLog.FullName -Tail",
        "PreferredPythonPath",
        "heartbeat_ok_age_sec",
        "heartbeat_ok_recent",
        "bridge_peer_ready",
        "bridge_issue_hint",
        "mt5_profile_issue",
        "duplicate_pids",
        "start_failed_no_lock",
        "stderr_tail",
        "function Test-PidMatchesScript",
        "function Test-AcceptablePidTree",
        "already_running_lock_pid",
        "already_running_multi_pid_accepted",
        "multi_pid_tree_ok",
        "[switch]$SkipBackgroundGuards",
        "guards_skipped",
        "([bool]$lockExists -and [bool]$logFresh -and [bool]$heartbeatOkRecent -and (-not [bool]$runningByPid))",
    )
    for token in required_tokens:
        assert token in script, f"Missing SYSTEM_CONTROL contract token: {token}"
