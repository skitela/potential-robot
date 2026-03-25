param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Mt5Exe = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [string]$CommonFilesDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files",
    [int]$VpsSyncTimeoutSec = 240
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-OandaTerminalProcess {
    param([string]$ExpectedProfile)

    $cimProcesses = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
        Where-Object {
            $_.ExecutablePath -eq $Mt5Exe -and
            $_.CommandLine -match [regex]::Escape("/profile:$ExpectedProfile")
        } |
        Sort-Object ProcessId -Descending
    if ($cimProcesses) {
        return $cimProcesses | Select-Object -First 1
    }

    $windowed = Get-Process terminal64 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Path -eq $Mt5Exe -and
            $_.MainWindowTitle -like "*OANDA TMS Brokers S.A.*"
        } |
        Sort-Object StartTime -Descending

    return $windowed | Select-Object -First 1
}

$projectRootResolved = (Resolve-Path -LiteralPath $ProjectRoot).Path
$evidenceOpsDir = Join-Path $projectRootResolved "EVIDENCE\OPS"
New-Item -ItemType Directory -Force -Path $evidenceOpsDir | Out-Null

$report = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    ok = $false
    project_root = $projectRootResolved
    stage = "init"
    local_install = $null
    local_validate = $null
    clear_sync = $null
    main_sync = $null
    error = $null
}

try {
    $report.stage = "refresh_audit_gate"
    & (Join-Path $projectRootResolved "RUN\RUN_AUDIT_SUPERVISOR.ps1") `
        -ProjectRoot $projectRootResolved `
        -Mode Once `
        -ApplySafeAutoHeal | Out-Null

    $report.stage = "local_install"
    $installRaw = & (Join-Path $projectRootResolved "TOOLS\INSTALL_MT5_SERVER_PACKAGE.ps1") `
        -ProjectRoot $projectRootResolved `
        -TargetTerminalDataDir $TerminalDataDir `
        -TargetCommonFilesDir $CommonFilesDir `
        -CreateRuntimeFolders
    $report.local_install = (($installRaw -join [Environment]::NewLine).Trim() | ConvertFrom-Json)

    $report.stage = "local_validate"
    $validateRaw = & (Join-Path $projectRootResolved "TOOLS\VALIDATE_MT5_SERVER_INSTALL.ps1") `
        -ProjectRoot $projectRootResolved `
        -TargetTerminalDataDir $TerminalDataDir `
        -TargetCommonFilesDir $CommonFilesDir
    $report.local_validate = (($validateRaw -join [Environment]::NewLine).Trim() | ConvertFrom-Json)

    $report.stage = "clear_profile"
    & (Join-Path $projectRootResolved "RUN\OPEN_OANDA_MT5_WITH_VPS_CLEAR_PROFILE.ps1") `
        -Mt5Exe $Mt5Exe `
        -TerminalDataDir $TerminalDataDir | Out-Null
    Start-Sleep -Seconds 10

    $clearProcess = Get-OandaTerminalProcess -ExpectedProfile "MAKRO_I_MIKRO_BOT_VPS_CLEAR"
    if ($null -eq $clearProcess) {
        throw "Nie znaleziono procesu OANDA po uruchomieniu profilu VPS_CLEAR."
    }

    $clearStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $clearJson = Join-Path $evidenceOpsDir ("paper_live_sync_clear_{0}.json" -f $clearStamp)
    $report.stage = "clear_sync"
    & python (Join-Path $projectRootResolved "TOOLS\sync_mt5_virtual_hosting.py") `
        --process-id $clearProcess.ProcessId `
        --scope experts `
        --timeout-sec $VpsSyncTimeoutSec `
        --output-json $clearJson `
        --latest-json (Join-Path $evidenceOpsDir "paper_live_sync_clear_latest.json") `
        --latest-md (Join-Path $evidenceOpsDir "paper_live_sync_clear_latest.md") | Out-Null
    $report.clear_sync = Get-Content -Raw -LiteralPath $clearJson | ConvertFrom-Json

    $report.stage = "main_profile"
    & (Join-Path $projectRootResolved "RUN\RUN_AUDIT_SUPERVISOR.ps1") `
        -ProjectRoot $projectRootResolved `
        -Mode Once `
        -ApplySafeAutoHeal | Out-Null
    & (Join-Path $projectRootResolved "RUN\OPEN_OANDA_MT5_WITH_MICROBOTS.ps1") `
        -AllowBlockedAuditGate `
        -Mt5Exe $Mt5Exe `
        -TerminalDataDir $TerminalDataDir | Out-Null
    Start-Sleep -Seconds 10

    $mainProcess = Get-OandaTerminalProcess -ExpectedProfile "MAKRO_I_MIKRO_BOT_AUTO"
    if ($null -eq $mainProcess) {
        throw "Nie znaleziono procesu OANDA po uruchomieniu profilu MAKRO_I_MIKRO_BOT_AUTO."
    }

    $mainStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $mainJson = Join-Path $evidenceOpsDir ("paper_live_sync_{0}.json" -f $mainStamp)
    $report.stage = "main_sync"
    & python (Join-Path $projectRootResolved "TOOLS\sync_mt5_virtual_hosting.py") `
        --process-id $mainProcess.ProcessId `
        --scope experts `
        --timeout-sec $VpsSyncTimeoutSec `
        --output-json $mainJson `
        --latest-json (Join-Path $evidenceOpsDir "paper_live_sync_latest.json") `
        --latest-md (Join-Path $evidenceOpsDir "paper_live_sync_latest.md") | Out-Null
    $report.main_sync = Get-Content -Raw -LiteralPath $mainJson | ConvertFrom-Json

    $report.stage = "refresh_reports"
    & (Join-Path $projectRootResolved "RUN\BUILD_MT5_HOSTING_DAILY_REPORT.ps1") -ProjectRoot $projectRootResolved | Out-Null
    & (Join-Path $projectRootResolved "RUN\BUILD_CANONICAL_PAPER_LIVE_FEEDBACK.ps1") -ProjectRoot $projectRootResolved | Out-Null
    & (Join-Path $projectRootResolved "TOOLS\RUN_RUNTIME_WATCHDOG_PL.ps1") -ProjectRoot $projectRootResolved -NoRepair | Out-Null
    & (Join-Path $projectRootResolved "RUN\SYNC_VPS_SPOOL_BACKLOG.ps1") -ProjectRoot $projectRootResolved | Out-Null
    & (Join-Path $projectRootResolved "RUN\BUILD_RESEARCH_DATA_CONTRACT.ps1") -ProjectRoot $projectRootResolved | Out-Null

    $report.ok = $true
    $report.stage = "done"
}
catch {
    $report.ok = $false
    $report.error = $_.Exception.Message
    $report.stage = "failed"
}

$reportPath = Join-Path $projectRootResolved "EVIDENCE\migrate_oanda_mt5_vps_clean_latest.json"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8

if (-not $report.ok) {
    exit 1
}
