param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$UsbLabel = "OANDAKEY",
    [string]$TokenEnvPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )

    try {
        $output = & $Body 2>&1 | Out-String
        return [ordered]@{
            ok = $true
            output = $output.Trim()
        }
    } catch {
        return [ordered]@{
            ok = $false
            error = $_.Exception.Message
        }
    }
}

function Invoke-WinRmAuthStep {
    param([string]$RuntimeRoot, [string]$TokenEnvPathValue)

    $scriptPath = Join-Path $RuntimeRoot "TOOLS\TEST_VPS_WINRM_AUTH.ps1"
    $evidencePath = Join-Path $RuntimeRoot "EVIDENCE\test_vps_winrm_auth_report.json"

    try {
        if ([string]::IsNullOrWhiteSpace($TokenEnvPathValue)) {
            $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath 2>&1 | Out-String
        } else {
            $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -TokenEnvPath $TokenEnvPathValue 2>&1 | Out-String
        }

        $parsed = $null
        if (Test-Path -LiteralPath $evidencePath) {
            $parsed = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        }

        $winRmOk = ($null -ne $parsed) -and ([bool]$parsed.winrm_auth_ok)
        $tcpOk = ($null -ne $parsed) -and ([bool]$parsed.tcp_5985)

        return [ordered]@{
            ok = $winRmOk
            output = $output.Trim()
            report_path = $evidencePath
            tcp_5985 = $tcpOk
            winrm_auth_ok = $winRmOk
            host = if ($null -ne $parsed) { [string]$parsed.host } else { "" }
            error = if ($null -ne $parsed) { [string]$parsed.error } else { "" }
        }
    } catch {
        return [ordered]@{
            ok = $false
            error = $_.Exception.Message
            report_path = $evidencePath
        }
    }
}

$runtimeRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
$evidenceDir = Join-Path $runtimeRoot "EVIDENCE"
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null

$report = [ordered]@{
    schema = "oanda.mt5.hybrid_agent.vps.recovery.v1"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    root = $runtimeRoot
    steps = [ordered]@{}
    guidance = [ordered]@{
        connect_rdp = "C:\OANDA_MT5_SYSTEM\RUN\CONNECT_VPS_RDP.ps1"
        detach_on_vps = "C:\OANDA_MT5_SYSTEM\TOOLS\DETACH_HYBRID_AGENT_ON_VPS.ps1"
        detach_runbook = "C:\OANDA_MT5_SYSTEM\DOCS\HYBRID_AGENT_DETACH_RUNBOOK_PL.md"
        winrm_blocker_runbook = "C:\OANDA_MT5_SYSTEM\DOCS\VPS_WINRM_ACCESS_BLOCKER_PL.md"
    }
}

$report.steps.local_detach_validation = Invoke-Step -Name "local_detach_validation" -Body {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $runtimeRoot "TOOLS\VALIDATE_HYBRID_AGENT_DETACHED_LOCAL.ps1")
}

$report.steps.winrm_auth = Invoke-WinRmAuthStep -RuntimeRoot $runtimeRoot -TokenEnvPathValue $TokenEnvPath

$report.steps.remote_channels = Invoke-Step -Name "remote_channels" -Body {
    if ([string]::IsNullOrWhiteSpace($TokenEnvPath)) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $runtimeRoot "TOOLS\TEST_VPS_REMOTE_CHANNELS.ps1") -Root $runtimeRoot -UsbLabel $UsbLabel
    } else {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $runtimeRoot "TOOLS\TEST_VPS_REMOTE_CHANNELS.ps1") -Root $runtimeRoot -UsbLabel $UsbLabel -TokenEnvPath $TokenEnvPath
    }
}

$report.steps.rdp_hint = [ordered]@{
    ok = $true
    command = "powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\RUN\CONNECT_VPS_RDP.ps1"
}

$report.steps.remote_detach_hint = [ordered]@{
    ok = $true
    command = "powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\DETACH_HYBRID_AGENT_ON_VPS.ps1"
}

$report.overall_ok =
    [bool]$report.steps.local_detach_validation.ok -and
    [bool]$report.steps.winrm_auth.ok -and
    [bool]$report.steps.remote_channels.ok

$reportPath = Join-Path $evidenceDir "prepare_vps_hybrid_agent_recovery_report.json"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Output ("PREPARE_VPS_HYBRID_AGENT_RECOVERY_DONE report={0}" -f $reportPath)
Write-Output ("LOCAL_DETACH_OK={0}" -f [string]$report.steps.local_detach_validation.ok)
Write-Output ("WINRM_AUTH_OK={0}" -f [string]$report.steps.winrm_auth.ok)
Write-Output ("REMOTE_CHANNELS_OK={0}" -f [string]$report.steps.remote_channels.ok)
if (-not [bool]$report.steps.winrm_auth.ok) {
    Write-Output "NEXT_STEP=RDP_OR_VNC_AND_RUN_DETACH_HYBRID_AGENT_ON_VPS"
}
exit 0
