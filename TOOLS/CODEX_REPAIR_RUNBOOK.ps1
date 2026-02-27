param(
    [string]$Root = "",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-Root {
    param([string]$InputRoot = "")
    if ([string]::IsNullOrWhiteSpace($InputRoot)) {
        return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    }
    return (Resolve-Path $InputRoot).Path
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = ""
    )
    if (-not (Test-Path $FilePath)) {
        return [ordered]@{
            name = $Name
            status = "MISSING"
            file = $FilePath
            exit_code = 404
        }
    }
    if ($DryRun) {
        return [ordered]@{
            name = $Name
            status = "DRY_RUN"
            file = $FilePath
            args = @($Arguments)
            exit_code = 0
        }
    }
    $wd = if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) { Split-Path -Parent $FilePath } else { $WorkingDirectory }
    $proc = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $wd -PassThru -Wait -WindowStyle Hidden
    return [ordered]@{
        name = $Name
        status = if ($proc.ExitCode -eq 0) { "PASS" } else { "FAIL" }
        file = $FilePath
        args = @($Arguments)
        exit_code = [int]$proc.ExitCode
    }
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Object
    )
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $tmp = "$Path.tmp"
    $Object | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $tmp
    Move-Item -Force $tmp $Path
}

$runtimeRoot = Resolve-Root -InputRoot $Root
$statusPath = Join-Path $runtimeRoot "RUN\\codex_repair_last.json"

$steps = @()
$steps += Invoke-Step -Name "system_stop" -FilePath (Join-Path $runtimeRoot "stop.bat") -WorkingDirectory $runtimeRoot
$steps += Invoke-Step -Name "mt5_fix_autotrade" -FilePath (Join-Path $runtimeRoot "FIX_MT5_AUTOTRADE.bat") -WorkingDirectory $runtimeRoot
$steps += Invoke-Step -Name "mt5_full_diagnostic" -FilePath (Join-Path $runtimeRoot "RUN_MT5_FULL_DIAGNOSTIC.bat") -WorkingDirectory $runtimeRoot
$steps += Invoke-Step -Name "system_start" -FilePath (Join-Path $runtimeRoot "start.bat") -WorkingDirectory $runtimeRoot

$status = [ordered]@{
    schema_version = "oanda_mt5.codex_repair_runbook.v1"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    root = $runtimeRoot
    dry_run = [bool]$DryRun
    steps = @($steps)
    status = if ($steps | Where-Object { $_.status -in @("FAIL", "MISSING") }) { "FAIL" } else { "PASS" }
}

Write-JsonAtomic -Path $statusPath -Object $status

Write-Output ("CODEX_REPAIR_RUNBOOK status={0} report={1}" -f [string]$status.status, $statusPath)
if ($status.status -ne "PASS") {
    exit 1
}
exit 0

