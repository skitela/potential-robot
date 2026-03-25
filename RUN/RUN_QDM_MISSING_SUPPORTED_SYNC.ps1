param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ProfileBuilderPath = "C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_QDM_MISSING_ONLY_PROFILE.ps1",
    [string]$SyncScriptPath = "C:\MAKRO_I_MIKRO_BOT\RUN\SYNC_QDM_FOCUS_PACK.ps1",
    [string]$ExportScriptPath = "C:\MAKRO_I_MIKRO_BOT\RUN\EXPORT_QDM_FOCUS_PACK_TO_MT5.ps1",
    [string]$ProfilePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_missing_only_pack_latest.csv",
    [string]$LatestStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_missing_supported_sync_latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-ActiveQdmExport {
    $process = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq "qdmcli.exe" -and
            -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
            $_.CommandLine -like "*action=exportToMT5*"
        } |
        Select-Object -First 1

    if ($null -eq $process) {
        return $null
    }

    $symbol = $null
    if ($process.CommandLine -match 'symbol=([^\s"]+)') {
        $symbol = $Matches[1]
    }

    return [pscustomobject]@{
        pid = [int]$process.ProcessId
        command_line = [string]$process.CommandLine
        symbol = $symbol
    }
}

function Get-ProfileSnapshot {
    param(
        [string]$ProjectRoot,
        [string]$ProfileStatusPath
    )

    & $ProfileBuilderPath | Out-Null

    $profileStatus = Read-JsonFile -Path $ProfileStatusPath
    if ($null -eq $profileStatus) {
        throw "Missing profile status not found: $ProfileStatusPath"
    }

    return [pscustomobject]@{
        missing_count = [int]$profileStatus.qdm_missing_count
        blocked_count = [int]$profileStatus.qdm_blocked_count
        unsupported_count = [int]$profileStatus.qdm_unsupported_count
        missing_symbols = @($profileStatus.missing | ForEach-Object { [string]$_.symbol_alias })
        unsupported_symbols = @($profileStatus.unsupported | ForEach-Object { [string]$_.symbol_alias })
        current_focus = if (@($profileStatus.missing).Count -gt 0) { [string]$profileStatus.missing[0].symbol_alias } else { $null }
    }
}

function Write-LatestStatus {
    param(
        [string]$State,
        [bool]$SyncStarted,
        [int]$MissingCount,
        [int]$BlockedCount,
        [int]$UnsupportedCount,
        [string[]]$MissingSymbols,
        [string[]]$UnsupportedSymbols,
        [string]$ProfilePath,
        [string]$LatestStatusPath,
        [string]$CurrentFocus = $null,
        [string]$Note = $null,
        [string]$ErrorMessage = $null
    )

    $payload = [ordered]@{
        schema_version = "1.0"
        generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        state = $State
        qdm_missing_count = $MissingCount
        qdm_blocked_count = $BlockedCount
        qdm_unsupported_count = $UnsupportedCount
        missing_symbols = $MissingSymbols
        unsupported_symbols = $UnsupportedSymbols
        profile_path = $ProfilePath
        sync_started = $SyncStarted
        runner_pid = $PID
        current_focus = $CurrentFocus
        note = $Note
    }

    if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
        $payload.error = $ErrorMessage
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LatestStatusPath) | Out-Null
    $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $LatestStatusPath -Encoding UTF8
}

foreach ($path in @($ProfileBuilderPath, $SyncScriptPath, $ExportScriptPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

$profileStatusPath = Join-Path $ProjectRoot "EVIDENCE\OPS\qdm_missing_only_profile_latest.json"
$profileSnapshot = Get-ProfileSnapshot -ProjectRoot $ProjectRoot -ProfileStatusPath $profileStatusPath
$missingCount = $profileSnapshot.missing_count
$blockedCount = $profileSnapshot.blocked_count
$unsupportedCount = $profileSnapshot.unsupported_count
$missingSymbols = @($profileSnapshot.missing_symbols)
$unsupportedSymbols = @($profileSnapshot.unsupported_symbols)
$currentFocus = $profileSnapshot.current_focus

$state = "noop"
$syncStarted = $false
$note = "no_missing_exports"
$activeExport = Get-ActiveQdmExport

if ($null -ne $activeExport) {
    $currentFocus = if (-not [string]::IsNullOrWhiteSpace($activeExport.symbol)) { $activeExport.symbol } else { $currentFocus }
    $note = "qdm_export_already_running"
    Write-LatestStatus -State "export_in_progress" -SyncStarted $false -MissingCount $missingCount -BlockedCount $blockedCount -UnsupportedCount $unsupportedCount -MissingSymbols $missingSymbols -UnsupportedSymbols $unsupportedSymbols -ProfilePath $ProfilePath -LatestStatusPath $LatestStatusPath -CurrentFocus $currentFocus -Note $note
    Get-Content -LiteralPath $LatestStatusPath -Raw -Encoding UTF8
    return
}

try {
    if ($missingCount -gt 0) {
        $state = "running"
        $syncStarted = $true
        $note = "sync_and_export_missing_qdm"
        Write-LatestStatus -State $state -SyncStarted $syncStarted -MissingCount $missingCount -BlockedCount $blockedCount -UnsupportedCount $unsupportedCount -MissingSymbols $missingSymbols -UnsupportedSymbols $unsupportedSymbols -ProfilePath $ProfilePath -LatestStatusPath $LatestStatusPath -CurrentFocus $currentFocus -Note $note

        & $SyncScriptPath -ProfilePath $ProfilePath
        & $ExportScriptPath -ProfilePath $ProfilePath

        $profileSnapshot = Get-ProfileSnapshot -ProjectRoot $ProjectRoot -ProfileStatusPath $profileStatusPath
        $missingCount = $profileSnapshot.missing_count
        $blockedCount = $profileSnapshot.blocked_count
        $unsupportedCount = $profileSnapshot.unsupported_count
        $missingSymbols = @($profileSnapshot.missing_symbols)
        $unsupportedSymbols = @($profileSnapshot.unsupported_symbols)
        $currentFocus = $profileSnapshot.current_focus

        if ($missingCount -gt 0) {
            $state = "completed_with_remaining_missing"
            $note = "some_exports_still_missing_after_repair"
        }
        else {
            $state = "completed"
            $note = "all_missing_exports_repaired"
        }
    }

    Write-LatestStatus -State $state -SyncStarted $syncStarted -MissingCount $missingCount -BlockedCount $blockedCount -UnsupportedCount $unsupportedCount -MissingSymbols $missingSymbols -UnsupportedSymbols $unsupportedSymbols -ProfilePath $ProfilePath -LatestStatusPath $LatestStatusPath -CurrentFocus $currentFocus -Note $note
    Get-Content -LiteralPath $LatestStatusPath -Raw -Encoding UTF8
}
catch {
    Write-LatestStatus -State "failed" -SyncStarted $syncStarted -MissingCount $missingCount -BlockedCount $blockedCount -UnsupportedCount $unsupportedCount -MissingSymbols $missingSymbols -UnsupportedSymbols $unsupportedSymbols -ProfilePath $ProfilePath -LatestStatusPath $LatestStatusPath -CurrentFocus $currentFocus -Note $note -ErrorMessage $_.Exception.Message
    throw
}
