param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_SYSTEM\LAB_DATA",
    [int]$KeepDays = 2
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Normalize-PathString {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    try {
        $p = $Path -replace "/", "\"
        return [System.IO.Path]::GetFullPath($p)
    } catch {
        return ($Path -replace "/", "\")
    }
}

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-GitTrackedPathSet {
    param([string]$RepoRoot)
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    try {
        Push-Location -LiteralPath $RepoRoot
        $tracked = @(git ls-files --full-name 2>$null)
        Pop-Location
        foreach ($rel in $tracked) {
            if ([string]::IsNullOrWhiteSpace($rel)) { continue }
            $abs = Normalize-PathString (Join-Path $RepoRoot $rel)
            [void]$set.Add($abs)
        }
    } catch {
        try { Pop-Location } catch {}
    }
    return $set
}

function Test-IsUnderProtectedRoot {
    param(
        [string]$FullPath,
        [string[]]$ProtectedRoots
    )
    if ([string]::IsNullOrWhiteSpace($FullPath)) { return $false }
    $fp = Normalize-PathString $FullPath
    foreach ($root in @($ProtectedRoots)) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $r = Normalize-PathString $root
        if (-not $r.EndsWith("\")) { $r += "\" }
        if ($fp.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Test-PidFileProcessAlive {
    param([string]$FilePath)
    try {
        $raw = Get-Content -LiteralPath $FilePath -Raw -ErrorAction Stop
        $pidVal = $null
        try {
            $obj = $raw | ConvertFrom-Json -ErrorAction Stop
            if ($obj -and $obj.PSObject.Properties.Name -contains "pid") {
                $pidVal = [int]$obj.pid
            }
        } catch {
            # plain-text fallback
            $rawTrim = ($raw.Trim())
            if ($rawTrim -match '^\d+$') {
                $pidVal = [int]$rawTrim
            }
        }
        if ($null -eq $pidVal) { return $false }
        $p = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
        return ($null -ne $p)
    } catch {
        return $false
    }
}

function Remove-OldFilesInTree {
    param(
        [string]$BasePath,
        [datetime]$Cutoff,
        [scriptblock]$SkipPredicate,
        [ref]$DeletedRows,
        [System.Collections.Generic.HashSet[string]]$TrackedPaths,
        [ref]$SkippedTrackedRows,
        [string[]]$ProtectedRoots,
        [ref]$SkippedProtectedRows
    )
    if (-not (Test-Path -LiteralPath $BasePath)) { return }
    Get-ChildItem -LiteralPath $BasePath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $Cutoff } |
        ForEach-Object {
            $f = $_
            $normalized = Normalize-PathString $f.FullName
            if (Test-IsUnderProtectedRoot -FullPath $normalized -ProtectedRoots $ProtectedRoots) {
                $SkippedProtectedRows.Value += [pscustomobject]@{
                    path = $f.FullName
                    reason = "protected_data"
                }
                return
            }
            if ($TrackedPaths -and $TrackedPaths.Contains($normalized)) {
                $SkippedTrackedRows.Value += [pscustomobject]@{
                    path = $f.FullName
                    reason = "git_tracked"
                }
                return
            }
            $skip = $false
            if ($SkipPredicate) {
                try { $skip = [bool](& $SkipPredicate $f) } catch { $skip = $false }
            }
            if ($skip) { return }
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                $DeletedRows.Value += [pscustomobject]@{
                    path       = $f.FullName
                    size_bytes = [int64]$f.Length
                    last_write = $f.LastWriteTime.ToString("s")
                }
            } catch {
                # best effort
            }
        }
}

$runtimeRoot = (Resolve-Path -LiteralPath $Root).Path
$cutoff = (Get-Date).Date.AddDays(-( [Math]::Max(1, [int]$KeepDays) - 1 ))
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")

$reportDir = Join-Path $runtimeRoot "EVIDENCE\cleanup"
Ensure-Dir -Path $reportDir
$reportJson = Join-Path $reportDir ("cleanup_report_" + $stamp + ".json")
$reportTxt = Join-Path $reportDir ("cleanup_report_" + $stamp + ".txt")
$deletedCsv = Join-Path $reportDir ("cleanup_deleted_" + $stamp + ".csv")
$skippedTrackedCsv = Join-Path $reportDir ("cleanup_skipped_tracked_" + $stamp + ".csv")
$skippedProtectedCsv = Join-Path $reportDir ("cleanup_skipped_protected_" + $stamp + ".csv")

$targets = @(
    (Join-Path $runtimeRoot "LOGS"),
    (Join-Path $runtimeRoot "EVIDENCE"),
    (Join-Path $runtimeRoot "RUN"),
    (Join-Path $runtimeRoot "META"),
    (Join-Path $runtimeRoot "DIAG"),
    (Join-Path $runtimeRoot "OBSERVERS_IMPLEMENTATION_CANDIDATE\outputs"),
    (Join-Path $runtimeRoot ".mypy_cache"),
    (Join-Path $runtimeRoot ".pytest_cache"),
    (Join-Path $runtimeRoot ".tmp"),
    (Join-Path $LabDataRoot "reports"),
    (Join-Path $LabDataRoot "run"),
    (Join-Path $LabDataRoot "tmp")
)

$runKeepNames = @(
    "system_control_last.json",
    "system_desired_state.json",
    "runtime_watchdog_state.json"
)

$protectedRoots = @(
    (Join-Path $runtimeRoot "EVIDENCE\learning_dataset"),
    (Join-Path $runtimeRoot "EVIDENCE\learning_dataset_quality"),
    (Join-Path $runtimeRoot "EVIDENCE\learning_coverage"),
    (Join-Path $runtimeRoot "LAB\EVIDENCE"),
    (Join-Path $LabDataRoot "snapshots")
)

$gitTracked = Get-GitTrackedPathSet -RepoRoot $runtimeRoot
$deleted = @()
$skippedTracked = @()
$skippedProtected = @()
foreach ($target in $targets) {
    $skipPredicate = $null
    if ($target -eq (Join-Path $runtimeRoot "RUN")) {
        $skipPredicate = {
            param($f)
            if ($runKeepNames -contains $f.Name) { return $true }
            if ($f.Name -like "*.lock") { return $true }
            if ($f.Name -like "*.pid") {
                if (Test-PidFileProcessAlive -FilePath $f.FullName) { return $true }
                return $false
            }
            return $false
        }
    } elseif ($target -eq (Join-Path $runtimeRoot "EVIDENCE")) {
        $skipPredicate = {
            param($f)
            if ($f.FullName -like "*\\EVIDENCE\\cleanup\\*") { return $true }
            return $false
        }
    }
    Remove-OldFilesInTree -BasePath $target -Cutoff $cutoff -SkipPredicate $skipPredicate -DeletedRows ([ref]$deleted) -TrackedPaths $gitTracked -SkippedTrackedRows ([ref]$skippedTracked) -ProtectedRoots $protectedRoots -SkippedProtectedRows ([ref]$skippedProtected)
}

# Clean empty directories
foreach ($target in $targets) {
    if (-not (Test-Path -LiteralPath $target)) { continue }
    Get-ChildItem -LiteralPath $target -Recurse -Directory -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        ForEach-Object {
            try {
                if ($_.FullName -eq $reportDir) { return }
                if ((Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                }
            } catch {
                # ignore
            }
        }
}

$byPath = @()
foreach ($target in $targets) {
    $rows = @($deleted | Where-Object { $_.path -like ($target + "*") })
    if ($rows.Count -le 0) { continue }
    $sumBytes = ($rows | Measure-Object size_bytes -Sum).Sum
    $byPath += [pscustomobject]@{
        path            = $target
        deleted_files   = [int]$rows.Count
        deleted_size_mb = [math]::Round(($sumBytes / 1MB), 2)
    }
}

$totalBytes = [int64]0
if (@($deleted).Count -gt 0) {
    $totalBytes = [int64](($deleted | Measure-Object -Property size_bytes -Sum).Sum)
}
$summary = [ordered]@{
    schema                = "oanda.mt5.cleanup.report.v1"
    ts_utc                = (Get-Date).ToUniversalTime().ToString("s") + "Z"
    keep_days             = [int]$KeepDays
    cutoff_local          = $cutoff.ToString("s")
    deleted_total_files   = [int]$deleted.Count
    deleted_total_size_mb = [math]::Round(($totalBytes / 1MB), 2)
    skipped_git_tracked   = [int]$skippedTracked.Count
    skipped_protected     = [int]$skippedProtected.Count
    protected_roots       = $protectedRoots
    by_path               = @($byPath | Sort-Object deleted_size_mb -Descending)
    report_json           = $reportJson
    report_txt            = $reportTxt
    deleted_csv           = $deletedCsv
    skipped_tracked_csv   = $skippedTrackedCsv
    skipped_protected_csv = $skippedProtectedCsv
}

Ensure-Dir -Path $reportDir
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportJson -Encoding UTF8
$deleted | Export-Csv -LiteralPath $deletedCsv -NoTypeInformation -Encoding UTF8
$skippedTracked | Export-Csv -LiteralPath $skippedTrackedCsv -NoTypeInformation -Encoding UTF8
$skippedProtected | Export-Csv -LiteralPath $skippedProtectedCsv -NoTypeInformation -Encoding UTF8

$lines = @()
$lines += ("CLEANUP_REPORT ts_utc={0} keep_days={1} cutoff_local={2}" -f $summary.ts_utc, $summary.keep_days, $summary.cutoff_local)
$lines += ("deleted_total_files={0} deleted_total_size_mb={1}" -f $summary.deleted_total_files, $summary.deleted_total_size_mb)
$lines += ("skipped_git_tracked={0}" -f $summary.skipped_git_tracked)
$lines += ("skipped_protected={0}" -f $summary.skipped_protected)
$lines += ""
$lines += "BY_PATH:"
foreach ($r in ($summary.by_path | Sort-Object deleted_size_mb -Descending)) {
    $lines += ("- {0} files={1} size_mb={2}" -f $r.path, $r.deleted_files, $r.deleted_size_mb)
}
$lines | Set-Content -LiteralPath $reportTxt -Encoding UTF8

Write-Host ("CLEANUP_DONE files={0} size_mb={1}" -f $summary.deleted_total_files, $summary.deleted_total_size_mb)
Write-Host ("SKIPPED_GIT_TRACKED {0}" -f $summary.skipped_git_tracked)
Write-Host ("SKIPPED_PROTECTED {0}" -f $summary.skipped_protected)
Write-Host ("REPORT_JSON {0}" -f $reportJson)
Write-Host ("REPORT_TXT  {0}" -f $reportTxt)
Write-Host ("DELETED_CSV {0}" -f $deletedCsv)
Write-Host ("SKIPPED_TRACKED_CSV {0}" -f $skippedTrackedCsv)
Write-Host ("SKIPPED_PROTECTED_CSV {0}" -f $skippedProtectedCsv)
