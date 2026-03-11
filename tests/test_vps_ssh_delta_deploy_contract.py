from __future__ import annotations

from pathlib import Path


def test_vps_ssh_delta_deploy_retries_transient_ssh_and_scp_failures() -> None:
    script = Path("TOOLS/VPS_SSH_DELTA_DEPLOY.ps1").read_text(encoding="utf-8", errors="ignore")
    required_tokens = (
        "function Invoke-SshRemoteBestEffort",
        "function Invoke-ScpWithRetry",
        "Connection reset",
        "kex_exchange_identification",
        "Connection closed",
        "subsystem request failed",
        "Broken pipe",
        "timed out",
        "Start-Sleep -Seconds ([Math]::Min(10, (2 * $attempt)))",
        "throw \"scp nie powiodlo sie dla: $LocalPath`n$msg\"",
        "Invoke-ScpWithRetry -SshKeyPath $SshKeyPath -LocalPath $localPath -RemoteTarget",
        "Invoke-SshRemoteCapture -BaseArgs $sshBase -CommandText",
    )
    for token in required_tokens:
        assert token in script, f"Missing VPS SSH delta deploy retry token: {token}"
