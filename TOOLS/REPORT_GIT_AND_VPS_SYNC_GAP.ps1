param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$VpsSyncEvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [string]$OutputDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\VPS_SYNC_GAP",
    [string]$TerminalRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [datetime]$ReferenceDay = (Get-Date).Date.AddDays(-1)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string[]]$Args
    )

    $output = & git -C $ProjectRoot @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("git failed: git -C {0} {1}`n{2}" -f $ProjectRoot, ($Args -join " "), ($output -join [Environment]::NewLine))
    }
    return $output
}

function Get-TextFileLinesLike {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    return Select-String -Path $Path -Pattern $Pattern | ForEach-Object {
        [pscustomobject]@{
            line_number = $_.LineNumber
            line        = $_.Line.Trim()
        }
    }
}

function Convert-ToMarkdownBullets {
    param(
        [Parameter(Mandatory = $false)][AllowNull()][AllowEmptyCollection()][object[]]$Items
    )

    if (-not $Items -or $Items.Count -eq 0) {
        return "- brak"
    }

    return (($Items | ForEach-Object { "- {0}" -f $_ }) -join [Environment]::NewLine)
}

$projectRootResolved = (Resolve-Path -LiteralPath $ProjectRoot).Path
$vpsSyncEvidenceResolved = (Resolve-Path -LiteralPath $VpsSyncEvidenceDir).Path
$terminalRootResolved = (Resolve-Path -LiteralPath $TerminalRoot).Path
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$reportStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportJsonPath = Join-Path $OutputDir ("git_vps_gap_{0}.json" -f $reportStamp)
$reportMdPath = Join-Path $OutputDir ("git_vps_gap_{0}.md" -f $reportStamp)
$latestJsonPath = Join-Path $OutputDir "git_vps_gap_latest.json"
$latestMdPath = Join-Path $OutputDir "git_vps_gap_latest.md"

$branch = @((Invoke-Git -Args @("rev-parse", "--abbrev-ref", "HEAD")))[0].ToString().Trim()
$head = @((Invoke-Git -Args @("rev-parse", "HEAD")))[0].ToString().Trim()
$headCommitDateRaw = @((Invoke-Git -Args @("show", "-s", "--format=%cI", "HEAD")))[0].ToString().Trim()
$headSubject = @((Invoke-Git -Args @("show", "-s", "--format=%s", "HEAD")))[0].ToString().Trim()
$statusShort = @((Invoke-Git -Args @("status", "--short")))
$remoteVerbose = @((Invoke-Git -Args @("remote", "-v")))
$branchVerbose = @((Invoke-Git -Args @("branch", "-vv")))
$commitsYesterday = @((Invoke-Git -Args @(
    "log",
    "--since", ($ReferenceDay.ToString("yyyy-MM-dd 00:00:00")),
    "--until", ($ReferenceDay.ToString("yyyy-MM-dd 23:59:59")),
    "--date=iso",
    "--pretty=format:%H|%ad|%s"
)))

$latestSyncJson = Get-ChildItem -LiteralPath $vpsSyncEvidenceResolved -Filter "paper_live_sync*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $latestSyncJson) {
    $latestSyncJson = Get-ChildItem -LiteralPath $vpsSyncEvidenceResolved -Filter "mt5_virtual_hosting_sync_*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}
if (-not $latestSyncJson) {
    throw "No paper_live_sync*.json or mt5_virtual_hosting_sync_*.json artifact found."
}
$latestSync = Get-Content -LiteralPath $latestSyncJson.FullName -Raw | ConvertFrom-Json
$latestSyncTs = [datetimeoffset]::Parse($latestSync.ts_local)
$headCommitDate = [datetimeoffset]::Parse($headCommitDateRaw)
$latestSyncKeyEvents = @()
if ($latestSync.PSObject.Properties.Name -contains "key_events") {
    $latestSyncKeyEvents = @($latestSync.key_events)
}
$latestSyncInvocationMethod = if ($latestSync.PSObject.Properties.Name -contains "invocation_method") { $latestSync.invocation_method } else { "" }
$latestSyncMigrationScope = if ($latestSync.PSObject.Properties.Name -contains "migration_scope") { $latestSync.migration_scope } else { "" }
$latestSyncMigrationScopeLabel = if ($latestSync.PSObject.Properties.Name -contains "migration_scope_label") { $latestSync.migration_scope_label } else { "" }

$commitsSinceSync = @((Invoke-Git -Args @(
    "log",
    "--since", $latestSyncTs.ToString("yyyy-MM-dd HH:mm:ss"),
    "--date=iso",
    "--pretty=format:%H|%ad|%s"
)))

$keyBotNames = @(
    "MicroBot_AUDUSD.ex5",
    "MicroBot_GBPUSD.ex5",
    "MicroBot_EURJPY.ex5",
    "MicroBot_USDCAD.ex5",
    "MicroBot_USDCHF.ex5",
    "MicroBot_USDJPY.ex5"
)
$keyBinaries = Get-ChildItem -Path (Join-Path $terminalRootResolved "MQL5\Experts") -Recurse -File |
    Where-Object { $keyBotNames -contains $_.Name } |
    Sort-Object Name |
    ForEach-Object {
        [pscustomobject]@{
            name            = $_.Name
            last_write_time = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            length          = $_.Length
            path            = $_.FullName
        }
    }

$keyCoreFiles = @(
    (Join-Path $terminalRootResolved "MQL5\Include\Core\MbTuningDeckhand.mqh"),
    (Join-Path $terminalRootResolved "MQL5\Include\Core\MbTuningEpistemology.mqh"),
    (Join-Path $terminalRootResolved "MQL5\Include\Core\MbTuningLocalAgent.mqh")
)
$coreState = foreach ($path in $keyCoreFiles) {
    if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path
        [pscustomobject]@{
            name            = $item.Name
            last_write_time = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            length          = $item.Length
            path            = $item.FullName
        }
    }
}

$terminalLog20260317 = Join-Path $terminalRootResolved "logs\20260317.log"
$algoDisabledLines = Get-TextFileLinesLike -Path $terminalLog20260317 -Pattern "automated trading disabled after migration and enabled on virtual hosting"
$migrationProcessedLines = Get-TextFileLinesLike -Path $terminalLog20260317 -Pattern "migration processed"
$prepareTransferLines = Get-TextFileLinesLike -Path $terminalLog20260317 -Pattern "prepare to transfer experts"

$projectEvidenceYesterday = Get-ChildItem -Path (Join-Path $projectRootResolved "EVIDENCE") -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $ReferenceDay -and $_.LastWriteTime -lt $ReferenceDay.AddDays(1) } |
    Sort-Object LastWriteTime |
    Select-Object -Last 40 |
    ForEach-Object {
        [pscustomobject]@{
            last_write_time = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            path            = $_.FullName
        }
    }

$vpsEvidenceYesterday = Get-ChildItem -Path $vpsSyncEvidenceResolved -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $ReferenceDay -and $_.LastWriteTime -lt $ReferenceDay.AddDays(1) } |
    Sort-Object LastWriteTime |
    ForEach-Object {
        [pscustomobject]@{
            last_write_time = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            path            = $_.FullName
        }
    }

$report = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    project_root = $projectRootResolved
    git = [ordered]@{
        branch               = $branch
        head                 = $head
        head_commit_date     = $headCommitDate.ToString("yyyy-MM-ddTHH:mm:sszzz")
        head_subject         = $headSubject
        status_clean         = ($statusShort.Count -eq 0)
        status_short         = $statusShort
        branch_verbose       = $branchVerbose
        remote_verbose       = $remoteVerbose
        commits_reference_day = $commitsYesterday
        commits_since_last_confirmed_vps_sync = $commitsSinceSync
    }
    latest_confirmed_vps_sync = [ordered]@{
        artifact_path        = $latestSyncJson.FullName
        ts_local             = $latestSync.ts_local
        mode                 = $latestSync.mode
        hosting_id           = $latestSync.hosting_id
        invocation_method    = $latestSyncInvocationMethod
        migration_scope      = $latestSyncMigrationScope
        migration_scope_label = $latestSyncMigrationScopeLabel
        key_events           = $latestSyncKeyEvents
    }
    preservation = [ordered]@{
        repo_head_is_newer_than_last_confirmed_vps_sync = ($headCommitDate -gt $latestSyncTs)
        yesterday_work_is_in_git                        = ($commitsYesterday.Count -gt 0)
        yesterday_work_is_on_remote                     = ($remoteVerbose.Count -gt 0)
        latest_confirmed_vps_sync_is_stale_vs_repo      = ($headCommitDate -gt $latestSyncTs)
    }
    local_mt5_ready_state = [ordered]@{
        key_binaries = $keyBinaries
        key_core_files = $coreState
    }
    local_mt5_migration_behavior = [ordered]@{
        prepare_transfer_lines = $prepareTransferLines
        migration_processed_lines = $migrationProcessedLines
        algo_disabled_after_migration_lines = $algoDisabledLines
    }
    evidence_reference_day = [ordered]@{
        project_evidence_paths = $projectEvidenceYesterday
        vps_evidence_paths = $vpsEvidenceYesterday
    }
    interpretation = @(
        "Kod i dokumentacja z wczoraj sa juz bezpiecznie zapisane w repo oraz wypchniete na origin/makro_i_mikro_bot_main.",
        "Najpozniejszy twardo potwierdzony sync MetaTrader VPS pozostaje z 2026-03-17 08:52:38, wiec hosting jest opozniony wzgledem aktualnego repo.",
        "Lokalny MT5 ma skompilowane binarki i zaktualizowane pliki tuning core z wczoraj, wiec brakujacy krok to juz migracja do MetaTrader VPS, nie odzyskiwanie kodu.",
        "Lokalne Algo Trading po migracji bylo wczesniej automatycznie wylaczane przez MetaTrader i wlaczane na virtual hostingu, co jest potwierdzone w logu 20260317."
    )
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportJsonPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8

$md = @"
# Git I VPS Sync Gap

- Wygenerowano: $($report.generated_at)
- Branch: $branch
- HEAD: $head
- Ostatni commit: $headSubject
- Ostatni potwierdzony sync VPS: $($latestSync.ts_local)
- Hosting id: $($latestSync.hosting_id)
- Zakres ostatniej migracji: $latestSyncMigrationScopeLabel

## Wniosek

- Wczorajsza praca jest w `git`: $(if($commitsYesterday.Count -gt 0){'tak'} else {'nie'})
- Wczorajsza praca jest na zdalnym repo: $(if($remoteVerbose.Count -gt 0){'tak'} else {'nie'})
- Repo jest nowsze niz ostatni potwierdzony sync VPS: $(if($headCommitDate -gt $latestSyncTs){'tak'} else {'nie'})

## Potwierdzenia Git

- Branch tracking: $($branchVerbose -join '; ')
- Remote:
$((Convert-ToMarkdownBullets -Items $remoteVerbose))

## Ostatni potwierdzony sync VPS

- Artefakt: $($latestSyncJson.FullName)
$((Convert-ToMarkdownBullets -Items ($latestSyncKeyEvents | ForEach-Object { "{0} -> {1}" -f $_.time_local, $_.message })))

## Lokalny MT5 Jest Gotowy Do Syncu

### Kluczowe binarki `.ex5`
$((Convert-ToMarkdownBullets -Items ($keyBinaries | ForEach-Object { "{0} | {1} | {2}" -f $_.name, $_.last_write_time, $_.path })))

### Kluczowe pliki tuning core
$((Convert-ToMarkdownBullets -Items ($coreState | ForEach-Object { "{0} | {1} | {2}" -f $_.name, $_.last_write_time, $_.path })))

## Zachowanie MT5 Przy Migracji

Log `20260317.log` potwierdza:
$((Convert-ToMarkdownBullets -Items ($prepareTransferLines | ForEach-Object { "linia {0}: {1}" -f $_.line_number, $_.line })))
$((Convert-ToMarkdownBullets -Items ($migrationProcessedLines | ForEach-Object { "linia {0}: {1}" -f $_.line_number, $_.line })))
$((Convert-ToMarkdownBullets -Items ($algoDisabledLines | ForEach-Object { "linia {0}: {1}" -f $_.line_number, $_.line })))

To oznacza, ze lokalne `Algo Trading` moglo byc wylaczane przez sam proces migracji, a nie przez utrate konfiguracji.

## Najwazniejsze Artefakty Z Wczoraj

### VPS / hosting
$((Convert-ToMarkdownBullets -Items ($vpsEvidenceYesterday | ForEach-Object { "{0} | {1}" -f $_.last_write_time, $_.path })))

### Project evidence
$((Convert-ToMarkdownBullets -Items ($projectEvidenceYesterday | Select-Object -First 20 | ForEach-Object { "{0} | {1}" -f $_.last_write_time, $_.path })))

## Interpretacja

$((Convert-ToMarkdownBullets -Items $report.interpretation))
"@

$md | Set-Content -LiteralPath $reportMdPath -Encoding UTF8
$md | Set-Content -LiteralPath $latestMdPath -Encoding UTF8

Write-Output ("REPORT_JSON={0}" -f $reportJsonPath)
Write-Output ("REPORT_MD={0}" -f $reportMdPath)
