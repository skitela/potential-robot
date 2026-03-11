from __future__ import annotations

from pathlib import Path


def test_connect_vps_rdp_uses_local_admin_normalization_and_prompt_mode() -> None:
    script = Path("TOOLS/CONNECT_VPS_RDP.ps1").read_text(encoding="utf-8", errors="ignore")
    required = (
        "function Normalize-RdpUser",
        "return \".\\$UserName\"",
        "[switch]$PromptForPassword",
        "prompt for credentials:i:{0}",
        "$rdpUser = Normalize-RdpUser -UserName $vpsUser",
        "if (-not $PromptForPassword)",
        "vps_quick_connect_prompt.rdp",
    )
    for token in required:
        assert token in script, f"Missing CONNECT_VPS_RDP token: {token}"


def test_vps_control_buttons_include_password_prompt_and_panel_fallback() -> None:
    script = Path("TOOLS/CREATE_VPS_CONTROL_BUTTONS.ps1").read_text(encoding="utf-8", errors="ignore")
    required = (
        "OPEN_VPS_PROVIDER_PORTAL.ps1",
        "-Name \"VPS OANDA POLACZ HASLO\"",
        "-PromptForPassword",
        "-Name \"VPS OANDA PANEL\"",
        "Panel Cyberfolks do wejscia przez VNC/noVNC",
    )
    for token in required:
        assert token in script, f"Missing VPS control shortcut token: {token}"
