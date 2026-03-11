from __future__ import annotations

from pathlib import Path


def test_enable_vps_remote_admin_configures_winrm_and_ssh() -> None:
    script = Path("TOOLS/ENABLE_VPS_REMOTE_ADMIN.ps1").read_text(encoding="utf-8", errors="ignore")
    required = (
        "Enable-PSRemoting -SkipNetworkProfileCheck -Force",
        "Set-Service -Name WinRM -StartupType Automatic",
        "Set-Item -Path WSMan:\\localhost\\Service\\Auth\\Negotiate -Value $true",
        "LocalAccountTokenFilterPolicy",
        "OpenSSH.Server",
        "Start-Service sshd",
        "OpenSSH-Server-In-TCP",
    )
    for token in required:
        assert token in script, f"Missing remote admin token: {token}"


def test_test_vps_remote_channels_checks_rdp_winrm_and_ssh() -> None:
    script = Path("TOOLS/TEST_VPS_REMOTE_CHANNELS.ps1").read_text(encoding="utf-8", errors="ignore")
    required = (
        "Test-NetConnection -ComputerName $hostName -Port $port",
        "3389, 5985, 22",
        "Test-WSMan $hostName",
        "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new oanda-vps hostname",
        "test_vps_remote_channels_",
    )
    for token in required:
        assert token in script, f"Missing channel test token: {token}"
