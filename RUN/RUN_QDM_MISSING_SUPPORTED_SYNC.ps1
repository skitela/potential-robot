param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ProfileBuilderPath = "C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_QDM_MISSING_ONLY_PROFILE.ps1",
    [string]$SyncScriptPath = "C:\MAKRO_I_MIKRO_BOT\RUN\SYNC_QDM_FOCUS_PACK.ps1",
    [string]$ProfilePath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\qdm_missing_only_pack.csv",
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
        missing_symbols = @($profileStatus.missing | ForEach-Object { [string]$_.symbol_alias })
        unsupported_symbols = @($profileStatus.unsupported | ForEach-Object { [string]$_.symbol_alias })
    }
}

function Write-LatestStatus {
    param(
        [string]$State,
        [bool]$SyncStarted,
        [int]$MissingCount,
        [string[]]$MissingSymbols,
        [string[]]$UnsupportedSymbols,
        [string]$ProfilePath,
        [string]$LatestStatusPath,
        [string]$ErrorMessage = $null
    )

    $payload = [ordered]@{
        schema_version = "1.0"
        generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        state = $State
        qdm_missing_count = $MissingCount
        missing_symbols = $MissingSymbols
        unsupported_symbols = $UnsupportedSymbols
        profile_path = $ProfilePath
        sync_started = $SyncStarted
        runner_pid = $PID
    }

    if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
        $payload.error = $ErrorMessage
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LatestStatusPath) | Out-Null
    $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $LatestStatusPath -Encoding UTF8
}

foreach ($path in @($ProfileBuilderPath, $SyncScriptPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

$profileStatusPath = Join-Path $ProjectRoot "EVIDENCE\OPS\qdm_missing_only_profile_latest.json"
$profileSnapshot = Get-ProfileSnapshot -ProjectRoot $ProjectRoot -ProfileStatusPath $profileStatusPath
$missingCount = $profileSnapshot.missing_count
$missingSymbols = @($profileSnapshot.missing_symbols)
$unsupportedSymbols = @($profileSnapshot.unsupported_symbols)

$state = "noop"
$syncStarted = $false

try {
    if ($missingCount -gt 0) {
        $state = "running"
        $syncStarted = $true
        Write-LatestStatus -State $state -SyncStarted $syncStarted -MissingCount $missingCount -MissingSymbols $missingSymbols -UnsupportedSymbols $unsupportedSymbols -ProfilePath $ProfilePath -LatestStatusPath $LatestStatusPath

        & $SyncScriptPath -ProfilePath $ProfilePath

        $profileSnapshot = Get-ProfileSnapshot -ProjectRoot $ProjectRoot -ProfileStatusPath $profileStatusPath
        $missingCount = $profileSnapshot.missing_count
        $missingSymbols = @($profileSnapshot.missing_symbols)
        $unsupportedSymbols = @($profileSnapshot.unsupported_symbols)

        if ($missingCount -gt 0) {
            $state = "completed_with_remaining_missing"
        }
        else {
            $state = "completed"
        }
    }

    Write-LatestStatus -State $state -SyncStarted $syncStarted -MissingCount $missingCount -MissingSymbols $missingSymbols -UnsupportedSymbols $unsupportedSymbols -ProfilePath $ProfilePath -LatestStatusPath $LatestStatusPath
    Get-Content -LiteralPath $LatestStatusPath -Raw -Encoding UTF8
}
catch {
    Write-LatestStatus -State "failed" -SyncStarted $syncStarted -MissingCount $missingCount -MissingSymbols $missingSymbols -UnsupportedSymbols $unsupportedSymbols -ProfilePath $ProfilePath -LatestStatusPath $LatestStatusPath -ErrorMessage $_.Exception.Message
    throw
}
