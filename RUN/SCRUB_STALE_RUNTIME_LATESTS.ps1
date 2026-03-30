param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$PolicyPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\runtime_latest_scrub_policy_v1.json",
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Object
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $json = $Object | ConvertTo-Json -Depth 8
    $tmp = Join-Path $parent ((Split-Path $Path -Leaf) + ".tmp." + [guid]::NewGuid().ToString("N"))
    try {
        $json | Set-Content -LiteralPath $tmp -Encoding UTF8
        if (Test-Path -LiteralPath $Path) {
            try {
                [System.IO.File]::Replace($tmp, $Path, $null, $true)
            }
            catch {
                [System.IO.File]::Copy($tmp, $Path, $true)
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            [System.IO.File]::Move($tmp, $Path)
        }
    }
    finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-TextAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Lines
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $tmp = Join-Path $parent ((Split-Path $Path -Leaf) + ".tmp." + [guid]::NewGuid().ToString("N"))
    $normalizedLines = @($Lines | ForEach-Object { [string]$_ })
    try {
        $normalizedLines | Set-Content -LiteralPath $tmp -Encoding UTF8
        if (Test-Path -LiteralPath $Path) {
            try {
                [System.IO.File]::Replace($tmp, $Path, $null, $true)
            }
            catch {
                [System.IO.File]::Copy($tmp, $Path, $true)
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            [System.IO.File]::Move($tmp, $Path)
        }
    }
    finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Resolve-EntryPath {
    param(
        [string]$RootKind,
        [string]$RelativePath
    )

    switch ($RootKind) {
        "project" { return Join-Path $ProjectRoot $RelativePath }
        "research" { return Join-Path $ResearchRoot $RelativePath }
        "common" { return Join-Path $CommonRoot $RelativePath }
        default { throw "Nieznany root w polityce scrub: $RootKind" }
    }
}

$projectRootResolved = (Resolve-Path -LiteralPath $ProjectRoot).Path
$opsRoot = Join-Path $projectRootResolved "EVIDENCE\OPS"
$jsonPath = Join-Path $opsRoot "runtime_latest_scrub_latest.json"
$mdPath = Join-Path $opsRoot "runtime_latest_scrub_latest.md"
New-Item -ItemType Directory -Force -Path $opsRoot | Out-Null

$policy = Read-JsonSafe -Path $PolicyPath
if ($null -eq $policy) {
    throw "Nie mozna odczytac polityki scrub stale latest: $PolicyPath"
}

$archiveRootRelative = [string]$policy.archive_root_relative
if ([string]::IsNullOrWhiteSpace($archiveRootRelative)) {
    $archiveRootRelative = "EVIDENCE\OPS\archive\stale_latest"
}
$archiveRoot = Join-Path $projectRootResolved $archiveRootRelative
New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null

$now = Get-Date
$items = New-Object System.Collections.Generic.List[object]
$archivedCount = 0
$staleCount = 0
$missingCount = 0

foreach ($entry in @($policy.entries)) {
    $name = [string]$entry.name
    $rootKind = [string]$entry.root
    $relativePath = [string]$entry.relative_path
    $thresholdSeconds = [int]$entry.threshold_seconds
    $targetPath = Resolve-EntryPath -RootKind $rootKind -RelativePath $relativePath

    $row = [ordered]@{
        name = $name
        root = $rootKind
        path = $targetPath
        threshold_seconds = $thresholdSeconds
        exists = $false
        stale = $false
        age_seconds = $null
        last_write_local = $null
        action = "none"
        archive_path = $null
    }

    if (-not (Test-Path -LiteralPath $targetPath)) {
        $missingCount++
        $items.Add([pscustomobject]$row) | Out-Null
        continue
    }

    $item = Get-Item -LiteralPath $targetPath
    $ageSeconds = [int][Math]::Round(($now - $item.LastWriteTime).TotalSeconds)
    $row.exists = $true
    $row.age_seconds = $ageSeconds
    $row.last_write_local = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    $row.stale = ($ageSeconds -gt $thresholdSeconds)

    if ($row.stale) {
        $staleCount++
        if ($Apply) {
            $stamp = $now.ToString("yyyyMMdd_HHmmss")
            $archiveDir = Join-Path $archiveRoot $stamp
            New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null
            $archivePath = Join-Path $archiveDir ("{0}__{1}" -f $name, (Split-Path $targetPath -Leaf))
            if (Test-Path -LiteralPath $targetPath) {
                Move-Item -LiteralPath $targetPath -Destination $archivePath -Force
                $row.action = "archived"
                $row.archive_path = $archivePath
                $archivedCount++
            }
            else {
                $row.action = "missing_during_scrub"
            }
        }
        else {
            $row.action = "stale_detected"
        }
    }

    $items.Add([pscustomobject]$row) | Out-Null
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = $now.ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = $now.ToUniversalTime().ToString("o")
    project_root = $projectRootResolved
    policy_path = $PolicyPath
    apply_mode = [bool]$Apply
    summary = [ordered]@{
        total_entries = $items.Count
        stale_count = $staleCount
        archived_count = $archivedCount
        missing_count = $missingCount
    }
    items = @($items.ToArray())
}

Write-JsonAtomic -Path $jsonPath -Object $report

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Runtime Latest Scrub")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- tryb_zastosowania: {0}" -f ([string]$report.apply_mode).ToLowerInvariant()))
$lines.Add(("- stale_count: {0}" -f $report.summary.stale_count))
$lines.Add(("- archived_count: {0}" -f $report.summary.archived_count))
$lines.Add(("- missing_count: {0}" -f $report.summary.missing_count))
$lines.Add("")
$lines.Add("## Pozycje")
$lines.Add("")
foreach ($item in @($report.items)) {
    $lines.Add(("- {0}: exists={1}, stale={2}, action={3}, age_seconds={4}" -f $item.name, ([string]$item.exists).ToLowerInvariant(), ([string]$item.stale).ToLowerInvariant(), $item.action, $item.age_seconds))
}

Write-TextAtomic -Path $mdPath -Lines @($lines.ToArray())
$report | ConvertTo-Json -Depth 8
