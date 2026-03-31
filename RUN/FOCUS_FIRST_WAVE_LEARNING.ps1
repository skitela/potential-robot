param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [int]$DurationMinutes = 180,
    [switch]$StopNonFirstWaveTesters = $true,
    [switch]$RefreshAudits = $true,
    [switch]$UseActivePresets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$diagnosticScript = Join-Path $projectPath "RUN\SET_FIRST_WAVE_TRUTH_DIAGNOSTIC_MODE.ps1"
$runtimeAuditScript = Join-Path $projectPath "RUN\BUILD_MT5_FIRST_WAVE_RUNTIME_ACTIVITY_AUDIT.ps1"
$closureAuditScript = Join-Path $projectPath "RUN\BUILD_FIRST_WAVE_LESSON_CLOSURE_AUDIT.ps1"
$profileScript = Join-Path $projectPath "TOOLS\setup_mt5_microbots_profile.py"
$generateActivePresetsScript = Join-Path $projectPath "TOOLS\GENERATE_ACTIVE_LIVE_PRESETS.ps1"
$allowedSymbols = @("US500","EURJPY","AUDUSD","USDCAD")
$stopped = New-Object System.Collections.Generic.List[object]

function Stop-ProcessRow {
    param(
        [Parameter(Mandatory = $true)]$Row,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    try {
        Stop-Process -Id ([int]$Row.ProcessId) -Force -ErrorAction Stop
        $stopped.Add([pscustomobject]@{
            pid = [int]$Row.ProcessId
            name = [string]$Row.Name
            reason = $Reason
        }) | Out-Null
    }
    catch {
        $stopped.Add([pscustomobject]@{
            pid = [int]$Row.ProcessId
            name = [string]$Row.Name
            reason = "$Reason|STOP_FAILED"
        }) | Out-Null
    }
}

if($StopNonFirstWaveTesters) {
    $procs = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -in @("terminal64.exe","metatester64.exe","powershell.exe","python.exe")
    }

    foreach($row in $procs) {
        $cmd = [string]$row.CommandLine
        $name = [string]$row.Name

        if($name -eq "terminal64.exe") {
            if($cmd -like "*OANDA TMS MT5 Terminal*") {
                continue
            }

            if($cmd -like "*strategy_tester*" -or $cmd -like "*MT5_NEAR_PROFIT_LAB*") {
                Stop-ProcessRow -Row $row -Reason "NON_FIRST_WAVE_TERMINAL"
                continue
            }
        }

        if($name -eq "metatester64.exe") {
            if($cmd -like "*MetaTrader 5\\metatester64.exe*" -or $cmd -like "*MT5_NEAR_PROFIT_LAB\\metatester64.exe*") {
                Stop-ProcessRow -Row $row -Reason "NON_FIRST_WAVE_METATESTER"
                continue
            }
        }

        if($name -eq "powershell.exe") {
            if($cmd -match "weakest_mt5_batch_wrapper|near_profit_optimization_after_idle_wrapper|mt5_tester_status_watcher_wrapper") {
                Stop-ProcessRow -Row $row -Reason "NON_FIRST_WAVE_WRAPPER"
                continue
            }
        }
    }

    $exporters = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "python.exe" -and [string]$_.CommandLine -like "*EXPORT_MT5_RESEARCH_DATA.py*"
    } | Sort-Object ProcessId -Descending)

    if($exporters.Count -gt 1) {
        $keep = $exporters | Select-Object -First 1
        foreach($row in ($exporters | Select-Object -Skip 1)) {
            Stop-ProcessRow -Row $row -Reason "DUPLICATE_RESEARCH_EXPORT"
        }
    }
}

$diagnosticResult = & $diagnosticScript -Mode Enable -ProjectRoot $projectPath -DurationMinutes $DurationMinutes | ConvertFrom-Json

$useActivePresetsResolved = $false
$activePresetRoot = Join-Path $projectPath "MQL5\Presets\ActiveLive"
$expectedActivePresets = @(
    "MicroBot_US500_Live_ACTIVE.set",
    "MicroBot_EURJPY_Live_ACTIVE.set",
    "MicroBot_AUDUSD_Live_ACTIVE.set",
    "MicroBot_USDCAD_Live_ACTIVE.set"
)

if($UseActivePresets) {
    try {
        if(Test-Path -LiteralPath $generateActivePresetsScript) {
            & $generateActivePresetsScript -ProjectRoot $projectPath -OutputRoot $activePresetRoot -AllowBlockedAuditGate | Out-Null
        }
    }
    catch {
    }

    if(Test-Path -LiteralPath $activePresetRoot) {
        $useActivePresetsResolved = $true
        foreach($presetName in $expectedActivePresets) {
            if(-not (Test-Path -LiteralPath (Join-Path $activePresetRoot $presetName))) {
                $useActivePresetsResolved = $false
                break
            }
        }
    }
}

$profileArgs = @($profileScript)
if($useActivePresetsResolved) {
    $profileArgs += "--use-active-presets"
}
$profileArgs += "--launch"

& python @profileArgs | Out-Null
Start-Sleep -Seconds 25

$runtimeAudit = $null
$closureAudit = $null

if($RefreshAudits) {
    & $runtimeAuditScript | Out-Null
    & $closureAuditScript | Out-Null
    $runtimeAudit = Get-Content (Join-Path $projectPath "EVIDENCE\OPS\mt5_first_wave_runtime_activity_latest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $closureAudit = Get-Content (Join-Path $projectPath "EVIDENCE\OPS\first_wave_lesson_closure_latest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
}

[pscustomobject]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    project_root = $projectPath
    duration_minutes = $DurationMinutes
    allowed_symbols = $allowedSymbols
    use_active_presets = $useActivePresetsResolved
    active_presets_requested = [bool]$UseActivePresets
    active_preset_root = $activePresetRoot
    stopped_processes = @($stopped.ToArray())
    diagnostic_mode = $diagnosticResult
    runtime_activity_verdict = if($runtimeAudit) { [string]$runtimeAudit.verdict } else { $null }
    lesson_closure_verdict = if($closureAudit) { [string]$closureAudit.verdict } else { $null }
    fresh_chain_ready_count = if($closureAudit) { [int]$closureAudit.summary.fresh_chain_ready_count } else { $null }
} | ConvertTo-Json -Depth 10
