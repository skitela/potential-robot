param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runtimeRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
$handoffRoot = Join-Path $runtimeRoot "EVIDENCE\VPS_HYBRID_AGENT_RECOVERY_HANDOFF"
New-Item -ItemType Directory -Force -Path $handoffRoot | Out-Null

$items = @(
    "DOCS\HYBRID_AGENT_DETACH_RUNBOOK_PL.md",
    "DOCS\VPS_WINRM_ACCESS_BLOCKER_PL.md",
    "DOCS\VPS_HYBRID_AGENT_RECOVERY_PACK_PL.md",
    "TOOLS\PREPARE_VPS_HYBRID_AGENT_RECOVERY.ps1",
    "TOOLS\DETACH_HYBRID_AGENT_ON_VPS.ps1",
    "TOOLS\VALIDATE_HYBRID_AGENT_DETACHED_ON_VPS.ps1",
    "TOOLS\TEST_VPS_WINRM_AUTH.ps1",
    "TOOLS\TEST_VPS_REMOTE_CHANNELS.ps1",
    "RUN\CONNECT_VPS_RDP.ps1",
    "RUN\vps_quick_connect.rdp",
    "EVIDENCE\detach_hybrid_agent_local_and_vps_report.json",
    "EVIDENCE\validate_hybrid_agent_detached_local_report.json",
    "EVIDENCE\test_vps_winrm_auth_report.json",
    "EVIDENCE\prepare_vps_hybrid_agent_recovery_report.json"
)

$copied = @()
foreach ($relative in $items) {
    $source = Join-Path $runtimeRoot $relative
    if (-not (Test-Path -LiteralPath $source)) {
        continue
    }
    $target = Join-Path $handoffRoot $relative
    $targetDir = Split-Path -Parent $target
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
    $copied += $relative
}

$latestRemote = Get-ChildItem -Path (Join-Path $runtimeRoot "EVIDENCE\vps_remote_admin") -Filter "*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -ne $latestRemote) {
    $target = Join-Path $handoffRoot "EVIDENCE\vps_remote_admin\$($latestRemote.Name)"
    $targetDir = Split-Path -Parent $target
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    Copy-Item -LiteralPath $latestRemote.FullName -Destination $target -Force
    $copied += "EVIDENCE\vps_remote_admin\$($latestRemote.Name)"
}

$summary = @(
    "VPS HybridAgent Recovery Handoff",
    "",
    "Host: 185.243.55.55",
    "Target server name: VPS Warsaw 01",
    "Target server id: #260303_1940",
    "",
    "Current state:",
    "- local HybridAgent detached: yes",
    "- local MT5 terminals clean: yes",
    "- tcp 5985 reachable: yes",
    "- WinRM auth: blocked (Access denied)",
    "- next step: RDP or VNC login and run DETACH_HYBRID_AGENT_ON_VPS.ps1 on the server",
    "",
    "Primary commands:",
    "- powershell -ExecutionPolicy Bypass -File C:\\OANDA_MT5_SYSTEM\\RUN\\CONNECT_VPS_RDP.ps1",
    "- powershell -ExecutionPolicy Bypass -File C:\\OANDA_MT5_SYSTEM\\TOOLS\\DETACH_HYBRID_AGENT_ON_VPS.ps1",
    "- powershell -ExecutionPolicy Bypass -File C:\\OANDA_MT5_SYSTEM\\TOOLS\\PREPARE_VPS_HYBRID_AGENT_RECOVERY.ps1"
)
$summaryPath = Join-Path $handoffRoot "HANDOFF_SUMMARY.txt"
Set-Content -LiteralPath $summaryPath -Value $summary -Encoding ASCII

$manifest = [ordered]@{
    schema = "oanda.mt5.hybrid_agent.vps.recovery.handoff.v1"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    root = $runtimeRoot
    handoff_root = $handoffRoot
    copied = $copied
    summary = "HANDOFF_SUMMARY.txt"
}
$manifestPath = Join-Path $handoffRoot "handoff_manifest.json"
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Output ("EXPORT_VPS_HYBRID_AGENT_RECOVERY_HANDOFF_DONE root={0}" -f $handoffRoot)
Write-Output ("FILES={0}" -f $copied.Count)
exit 0
