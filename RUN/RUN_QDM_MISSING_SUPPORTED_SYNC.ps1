param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ProfileBuilderPath = "C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_QDM_MISSING_ONLY_PROFILE.ps1",
    [string]$RefreshProfileBuilderPath = "C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_QDM_VISIBILITY_REFRESH_PROFILE.ps1",
    [string]$SyncScriptPath = "C:\MAKRO_I_MIKRO_BOT\RUN\SYNC_QDM_FOCUS_PACK.ps1",
    [string]$ExportScriptPath = "C:\MAKRO_I_MIKRO_BOT\RUN\EXPORT_QDM_FOCUS_PACK_TO_MT5.ps1",
    [string]$ProfilePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_missing_only_pack_latest.csv",
    [string]$RefreshProfilePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_visibility_refresh_pack_latest.csv",
    [string]$BatchProfilePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_missing_supported_batch_latest.csv",
    [string]$RefreshResearchScriptPath = "C:\MAKRO_I_MIKRO_BOT\RUN\REFRESH_MICROBOT_RESEARCH_DATA.ps1",
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$ResearchPerfProfile = "Light",
    [int]$BatchSize = 1,
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

function Remove-StaleQdmCacheForExports {
    param(
        [string]$ProjectRoot,
        [string[]]$ExportNames
    )

    $manifestPath = Join-Path $ProjectRoot "EVIDENCE\OPS\qdm_visibility_refresh_profile_latest.json"
    $cacheManifestPath = "C:\TRADING_DATA\RESEARCH\reports\qdm_cache_manifest_latest.json"
    $removedPaths = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $cacheManifestPath)) {
        return @()
    }

    $cacheManifest = Read-JsonFile -Path $cacheManifestPath
    if ($null -eq $cacheManifest -or $null -eq $cacheManifest.PSObject.Properties["files"]) {
        return @()
    }

    $refreshManifest = Read-JsonFile -Path $manifestPath
    $refreshSet = @{}
    if ($null -ne $refreshManifest -and $null -ne $refreshManifest.PSObject.Properties["refresh_required"]) {
        foreach ($item in @($refreshManifest.refresh_required)) {
            if ($null -eq $item) { continue }
            $name = [string]$item.mt5_export_name
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                $refreshSet[$name.Trim().ToUpperInvariant()] = $true
            }
        }
    }

    foreach ($exportName in @($ExportNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $key = $exportName.Trim().ToUpperInvariant()
        if (-not $refreshSet.ContainsKey($key)) {
            continue
        }
        $entry = $cacheManifest.files.PSObject.Properties[$exportName]
        if ($null -eq $entry) {
            continue
        }

        $cachePath = [string]$entry.Value.minute_parquet_path
        if ([string]::IsNullOrWhiteSpace($cachePath) -or -not (Test-Path -LiteralPath $cachePath)) {
            continue
        }

        Remove-Item -LiteralPath $cachePath -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $cachePath)) {
            $removedPaths.Add($cachePath) | Out-Null
        }
    }

    return @($removedPaths.ToArray())
}

function Get-ActiveQdmCliProcess {
    return Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq "qdmcli.exe" -and
            -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
            $_.CommandLine -like "*action=exportToMT5*"
        } |
        Select-Object -First 1
}

function Get-ActiveQdmExport {
    $lockPath = "C:\TRADING_DATA\QDM_EXPORT\MT5\_staging\active_export.lock.json"
    $activeProcess = Get-ActiveQdmCliProcess

    if (Test-Path -LiteralPath $lockPath) {
        try {
            $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $tempFile = [string]$lock.temp_file
            $finalFile = [string]$lock.final_file

            if ($null -ne $activeProcess) {
                return [pscustomobject]@{
                    pid = [int]$activeProcess.ProcessId
                    command_line = "staging_lock"
                    symbol = [string]$lock.symbol
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($tempFile) -and (Test-Path -LiteralPath $tempFile)) {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $finalFile) | Out-Null
                Move-Item -LiteralPath $tempFile -Destination $finalFile -Force
            }
            Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
        }
        catch {
            Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
        }
    }

    $process = $activeProcess

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
        [string]$ProfileStatusPath,
        [string]$RefreshStatusPath
    )

    & $ProfileBuilderPath | Out-Null
    & $RefreshProfileBuilderPath | Out-Null

    $profileStatus = Read-JsonFile -Path $ProfileStatusPath
    if ($null -eq $profileStatus) {
        throw "Missing profile status not found: $ProfileStatusPath"
    }
    $refreshStatus = Read-JsonFile -Path $RefreshStatusPath

    $pendingItems = New-Object System.Collections.Generic.List[object]
    if ($null -ne $profileStatus.PSObject.Properties["history_ready_export_pending"]) {
        foreach ($item in @($profileStatus.history_ready_export_pending)) {
            if ($null -ne $item) {
                $pendingItems.Add($item) | Out-Null
            }
        }
    }
    elseif ($null -ne $profileStatus.PSObject.Properties["missing"]) {
        foreach ($item in @($profileStatus.missing)) {
            if ($null -ne $item) {
                $pendingItems.Add($item) | Out-Null
            }
        }
    }

    $refreshRequiredSymbols = @()
    $refreshRequiredCount = 0
    if ($null -ne $refreshStatus) {
        if ($null -ne $refreshStatus.PSObject.Properties["summary"]) {
            $refreshRequiredCount = [int]$refreshStatus.summary.refresh_required_count
        }
        if ($null -ne $refreshStatus.PSObject.Properties["refresh_required"]) {
            $refreshItems = @($refreshStatus.refresh_required)
            $refreshRequiredSymbols = @($refreshItems | ForEach-Object { [string]$_.symbol_alias } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            foreach ($item in $refreshItems) {
                if ($null -eq $item) { continue }
                $alreadyTracked = @($pendingItems | Where-Object { [string]$_.mt5_export_name -eq [string]$item.mt5_export_name }).Count -gt 0
                if (-not $alreadyTracked) {
                    $pendingItems.Add([pscustomobject]@{
                        symbol_alias = [string]$item.symbol_alias
                        mt5_export_name = [string]$item.mt5_export_name
                        reason = [string]$item.main_root_cause
                        refresh_required = $true
                    }) | Out-Null
                }
            }
        }
    }

    return [pscustomobject]@{
        missing_count = [int]$profileStatus.qdm_missing_count
        refresh_required_count = $refreshRequiredCount
        blocked_count = [int]$profileStatus.qdm_blocked_count
        unsupported_count = [int]$profileStatus.qdm_unsupported_count
        missing_symbols = @($pendingItems | ForEach-Object { [string]$_.symbol_alias } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        refresh_symbols = @($refreshRequiredSymbols | Select-Object -Unique)
        unsupported_symbols = @($profileStatus.unsupported | ForEach-Object { [string]$_.symbol_alias })
        current_focus = if ($pendingItems.Count -gt 0) { [string]$pendingItems[0].symbol_alias } else { $null }
        pending_items = @($pendingItems.ToArray())
    }
}

function Get-QdmRecoveryPriorityMap {
    $priorityOrder = @(
        "EURUSD",
        "GBPUSD",
        "USDJPY",
        "AUDUSD",
        "NZDUSD",
        "EURJPY",
        "EURAUD",
        "GBPJPY",
        "USDCAD",
        "USDCHF",
        "GOLD",
        "SILVER",
        "US500",
        "DE30",
        "COPPER-US"
    )

    $map = @{}
    for ($i = 0; $i -lt $priorityOrder.Count; $i++) {
        $map[$priorityOrder[$i].ToUpperInvariant()] = $i
    }

    return $map
}

function Get-BatchRows {
    param(
        [string[]]$ProfilePaths,
        [object[]]$PendingItems,
        [int]$BatchSize
    )

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($candidatePath in @($ProfilePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if (-not (Test-Path -LiteralPath $candidatePath)) {
            continue
        }
        foreach ($row in @(Import-Csv -LiteralPath $candidatePath -Encoding UTF8)) {
            if ($null -ne $row) {
                $rows.Add($row) | Out-Null
            }
        }
    }
    $rows = @($rows.ToArray())
    if ($rows.Count -eq 0 -or $PendingItems.Count -eq 0) {
        return @()
    }

    $rowByExportName = @{}
    foreach ($row in $rows) {
        $exportName = [string]$row.mt5_export_name
        if (-not [string]::IsNullOrWhiteSpace($exportName)) {
            $rowByExportName[$exportName.ToUpperInvariant()] = $row
        }
    }

    $priorityMap = Get-QdmRecoveryPriorityMap
    $orderedPending = @(
        $PendingItems |
            Where-Object { $null -ne $_ } |
            Select-Object @{ Name = "symbol_alias"; Expression = { [string]$_.symbol_alias } },
                          @{ Name = "mt5_export_name"; Expression = { [string]$_.mt5_export_name } },
                          @{ Name = "priority"; Expression = {
                              $alias = [string]$_.symbol_alias
                              $aliasKey = if ([string]::IsNullOrWhiteSpace($alias)) { "" } else { $alias.Trim().ToUpperInvariant() }
                              if ($priorityMap.ContainsKey($aliasKey)) { [int]$priorityMap[$aliasKey] } else { 1000 }
                          } } |
            Sort-Object priority, symbol_alias
    )

    $batchRows = New-Object System.Collections.Generic.List[object]
    foreach ($item in $orderedPending) {
        if ($batchRows.Count -ge [Math]::Max(1, $BatchSize)) {
            break
        }

        $exportName = [string]$item.mt5_export_name
        $row = $null
        if (-not [string]::IsNullOrWhiteSpace($exportName)) {
            $row = $rowByExportName[$exportName.Trim().ToUpperInvariant()]
        }
        if ($null -eq $row) {
            continue
        }

        $batchRows.Add([pscustomobject]@{
            symbol_alias = [string]$item.symbol_alias
            mt5_export_name = [string]$row.mt5_export_name
            row = $row
        }) | Out-Null
    }

    return @($batchRows.ToArray())
}

function Write-BatchProfile {
    param(
        [object[]]$BatchRows,
        [string]$BatchProfilePath
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $BatchProfilePath) | Out-Null
    $exportRows = @($BatchRows | ForEach-Object { $_.row })
    $exportRows | Export-Csv -LiteralPath $BatchProfilePath -NoTypeInformation -Encoding UTF8
}

function Write-LatestStatus {
    param(
        [string]$State,
        [bool]$SyncStarted,
        [int]$MissingCount,
        [int]$RefreshRequiredCount,
        [int]$BlockedCount,
        [int]$UnsupportedCount,
        [string[]]$MissingSymbols,
        [string[]]$RefreshSymbols,
        [string[]]$UnsupportedSymbols,
        [string]$ProfilePath,
        [string]$LatestStatusPath,
        [string]$CurrentFocus = $null,
        [string[]]$BatchSymbols = @(),
        [string[]]$RecoveredSymbols = @(),
        [string]$Note = $null,
        [string]$ErrorMessage = $null,
        [bool]$ResearchRefreshed = $false
    )

    $payload = [ordered]@{
        schema_version = "1.0"
        generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        state = $State
        qdm_missing_count = $MissingCount
        qdm_refresh_required_count = $RefreshRequiredCount
        qdm_blocked_count = $BlockedCount
        qdm_unsupported_count = $UnsupportedCount
        missing_symbols = $MissingSymbols
        refresh_symbols = $RefreshSymbols
        unsupported_symbols = $UnsupportedSymbols
        profile_path = $ProfilePath
        sync_started = $SyncStarted
        runner_pid = $PID
        current_focus = $CurrentFocus
        batch_symbols = $BatchSymbols
        recovered_symbols = $RecoveredSymbols
        research_refreshed = $ResearchRefreshed
        note = $Note
    }

    if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
        $payload.error = $ErrorMessage
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LatestStatusPath) | Out-Null
    $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $LatestStatusPath -Encoding UTF8
}

foreach ($path in @($ProfileBuilderPath, $RefreshProfileBuilderPath, $SyncScriptPath, $ExportScriptPath, $RefreshResearchScriptPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

$profileStatusPath = Join-Path $ProjectRoot "EVIDENCE\OPS\qdm_missing_only_profile_latest.json"
$refreshStatusPath = Join-Path $ProjectRoot "EVIDENCE\OPS\qdm_visibility_refresh_profile_latest.json"
$profileSnapshot = Get-ProfileSnapshot -ProjectRoot $ProjectRoot -ProfileStatusPath $profileStatusPath -RefreshStatusPath $refreshStatusPath
$missingCount = $profileSnapshot.missing_count
$refreshRequiredCount = $profileSnapshot.refresh_required_count
$blockedCount = $profileSnapshot.blocked_count
$unsupportedCount = $profileSnapshot.unsupported_count
$missingSymbols = @($profileSnapshot.missing_symbols)
$refreshSymbols = @($profileSnapshot.refresh_symbols)
$unsupportedSymbols = @($profileSnapshot.unsupported_symbols)
$currentFocus = $profileSnapshot.current_focus
$pendingItems = @($profileSnapshot.pending_items)
$batchRows = @(Get-BatchRows -ProfilePaths @($ProfilePath, $RefreshProfilePath) -PendingItems $pendingItems -BatchSize $BatchSize)
$batchSymbols = @($batchRows | ForEach-Object { [string]$_.symbol_alias } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$recoveredSymbols = @()
$researchRefreshed = $false

$state = "noop"
$syncStarted = $false
$note = "no_qdm_repairs_required"
$activeExport = Get-ActiveQdmExport

if ($null -ne $activeExport) {
    $currentFocus = if (-not [string]::IsNullOrWhiteSpace($activeExport.symbol)) { $activeExport.symbol } else { $currentFocus }
    $note = "qdm_export_already_running"
    Write-LatestStatus -State "export_in_progress" -SyncStarted $false -MissingCount $missingCount -RefreshRequiredCount $refreshRequiredCount -BlockedCount $blockedCount -UnsupportedCount $unsupportedCount -MissingSymbols $missingSymbols -RefreshSymbols $refreshSymbols -UnsupportedSymbols $unsupportedSymbols -ProfilePath $ProfilePath -LatestStatusPath $LatestStatusPath -CurrentFocus $currentFocus -BatchSymbols $batchSymbols -RecoveredSymbols $recoveredSymbols -Note $note -ResearchRefreshed $researchRefreshed
    Get-Content -LiteralPath $LatestStatusPath -Raw -Encoding UTF8
    return
}

try {
    if (($missingCount + $refreshRequiredCount) -gt 0) {
        $state = "running"
        $syncStarted = $true
        $note = if ($refreshRequiredCount -gt 0) { "sync_and_export_missing_or_stale_qdm_batch" } else { "sync_and_export_missing_qdm_batch" }

        if ($batchRows.Count -eq 0) {
            $state = "blocked_no_batch"
            $note = "qdm_repair_detected_but_no_batch_rows_selected"
            Write-LatestStatus -State $state -SyncStarted $false -MissingCount $missingCount -RefreshRequiredCount $refreshRequiredCount -BlockedCount $blockedCount -UnsupportedCount $unsupportedCount -MissingSymbols $missingSymbols -RefreshSymbols $refreshSymbols -UnsupportedSymbols $unsupportedSymbols -ProfilePath $ProfilePath -LatestStatusPath $LatestStatusPath -CurrentFocus $currentFocus -BatchSymbols $batchSymbols -RecoveredSymbols $recoveredSymbols -Note $note -ResearchRefreshed $researchRefreshed
            Get-Content -LiteralPath $LatestStatusPath -Raw -Encoding UTF8
            return
        }

        Write-BatchProfile -BatchRows $batchRows -BatchProfilePath $BatchProfilePath
        $currentFocus = $batchSymbols[0]
        Write-LatestStatus -State $state -SyncStarted $syncStarted -MissingCount $missingCount -BlockedCount $blockedCount -UnsupportedCount $unsupportedCount -MissingSymbols $missingSymbols -UnsupportedSymbols $unsupportedSymbols -ProfilePath $BatchProfilePath -LatestStatusPath $LatestStatusPath -CurrentFocus $currentFocus -BatchSymbols $batchSymbols -RecoveredSymbols $recoveredSymbols -Note $note -ResearchRefreshed $researchRefreshed

        & $SyncScriptPath -ProfilePath $BatchProfilePath
        & $ExportScriptPath -ProfilePath $BatchProfilePath
        $batchExportNames = @($batchRows | ForEach-Object { [string]$_.mt5_export_name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $null = Remove-StaleQdmCacheForExports -ProjectRoot $ProjectRoot -ExportNames $batchExportNames
        & $RefreshResearchScriptPath -ProjectRoot $ProjectRoot -PerfProfile $ResearchPerfProfile | Out-Null
        $researchRefreshed = $true

        $profileSnapshot = Get-ProfileSnapshot -ProjectRoot $ProjectRoot -ProfileStatusPath $profileStatusPath -RefreshStatusPath $refreshStatusPath
        $missingCount = $profileSnapshot.missing_count
        $refreshRequiredCount = $profileSnapshot.refresh_required_count
        $blockedCount = $profileSnapshot.blocked_count
        $unsupportedCount = $profileSnapshot.unsupported_count
        $missingSymbols = @($profileSnapshot.missing_symbols)
        $refreshSymbols = @($profileSnapshot.refresh_symbols)
        $unsupportedSymbols = @($profileSnapshot.unsupported_symbols)
        $currentFocus = $profileSnapshot.current_focus
        $recoveredSymbols = @($batchSymbols | Where-Object { $missingSymbols -notcontains $_ -and $refreshSymbols -notcontains $_ })

        if (($missingCount + $refreshRequiredCount) -gt 0) {
            $state = "completed_with_remaining_missing"
            $note = "batch_completed_some_qdm_repairs_still_pending"
        }
        else {
            $state = "completed"
            $note = "all_qdm_repairs_completed"
        }
    }

    Write-LatestStatus -State $state -SyncStarted $syncStarted -MissingCount $missingCount -RefreshRequiredCount $refreshRequiredCount -BlockedCount $blockedCount -UnsupportedCount $unsupportedCount -MissingSymbols $missingSymbols -RefreshSymbols $refreshSymbols -UnsupportedSymbols $unsupportedSymbols -ProfilePath $(if ($batchRows.Count -gt 0) { $BatchProfilePath } else { $ProfilePath }) -LatestStatusPath $LatestStatusPath -CurrentFocus $currentFocus -BatchSymbols $batchSymbols -RecoveredSymbols $recoveredSymbols -Note $note -ResearchRefreshed $researchRefreshed
    Get-Content -LiteralPath $LatestStatusPath -Raw -Encoding UTF8
}
catch {
    Write-LatestStatus -State "failed" -SyncStarted $syncStarted -MissingCount $missingCount -RefreshRequiredCount $refreshRequiredCount -BlockedCount $blockedCount -UnsupportedCount $unsupportedCount -MissingSymbols $missingSymbols -RefreshSymbols $refreshSymbols -UnsupportedSymbols $unsupportedSymbols -ProfilePath $(if ($batchRows.Count -gt 0) { $BatchProfilePath } else { $ProfilePath }) -LatestStatusPath $LatestStatusPath -CurrentFocus $currentFocus -BatchSymbols $batchSymbols -RecoveredSymbols $recoveredSymbols -Note $note -ErrorMessage $_.Exception.Message -ResearchRefreshed $researchRefreshed
    throw
}
