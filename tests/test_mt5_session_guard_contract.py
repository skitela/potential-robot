from __future__ import annotations

from pathlib import Path


def test_mt5_session_guard_uses_conservative_no_active_peer_thresholds() -> None:
    script = Path("TOOLS/mt5_session_guard.ps1").read_text(encoding="utf-8", errors="ignore")
    required_tokens = (
        "[int]$NoActivePeerWindowSec = 300",
        "[int]$NoActivePeerThreshold = 12",
        "[int]$NoActivePeerGraceSec = 180",
    )
    for token in required_tokens:
        assert token in script, f"Missing threshold token: {token}"


def test_mt5_session_guard_requires_missing_heartbeat_ok_for_no_peer_repair() -> None:
    script = Path("TOOLS/mt5_session_guard.ps1").read_text(encoding="utf-8", errors="ignore")
    required_tokens = (
        "$bridgeOkRx",
        "last_bridge_ok_utc",
        "no_active_peer_bridge_ok_recent",
        "(-not $bridgeOkRecently)",
    )
    for token in required_tokens:
        assert token in script, f"Missing bridge-ok gating token: {token}"


def test_mt5_session_guard_handles_large_log_offsets_without_int32_overflow() -> None:
    script = Path("TOOLS/mt5_session_guard.ps1").read_text(encoding="utf-8", errors="ignore")
    required_tokens = (
        "if (($len - $start) -gt [int64]$MaxReadBytes)",
        "$remaining = [int64]($len - $start)",
        "if ($remaining -gt [int64]2147483647)",
    )
    for token in required_tokens:
        assert token in script, f"Missing large-log safety token: {token}"


def test_mt5_session_guard_does_not_stop_itself_during_repair_cycle() -> None:
    script = Path("TOOLS/mt5_session_guard.ps1").read_text(encoding="utf-8", errors="ignore")
    required_tokens = (
        "Invoke-SystemRepair",
        "-SkipBackgroundGuards",
    )
    for token in required_tokens:
        assert token in script, f"Missing self-preserving repair token: {token}"
