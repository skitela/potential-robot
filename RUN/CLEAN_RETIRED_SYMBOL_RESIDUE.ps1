param(
    [ValidateSet("dry-run", "archive-and-clean")]
    [string]$Mode = "dry-run",
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$CommonStateRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [string]$BackupRoot = "C:\MAKRO_I_MIKRO_BOT\BACKUP"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Add-Target {
    param(
        [System.Collections.Generic.List[object]]$Targets,
        [string]$Path,
        [string]$Kind,
        [string]$Reason,
        [string]$Action
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $Targets.Add([pscustomobject]@{
        path = $Path
        kind = $Kind
        reason = $Reason
        action = $Action
    }) | Out-Null
}

function Get-RelativeBackupPath {
    param(
        [string]$Path,
        [string]$ProjectPath,
        [string]$CommonPath,
        [string]$ResearchPath
    )
    $normalized = [IO.Path]::GetFullPath($Path)
    foreach ($root in @(
        @{ base = [IO.Path]::GetFullPath($ProjectPath); prefix = "project" },
        @{ base = [IO.Path]::GetFullPath($CommonPath); prefix = "common" },
        @{ base = [IO.Path]::GetFullPath($ResearchPath); prefix = "research" }
    )) {
        if ($normalized.StartsWith($root.base, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relative = $normalized.Substring($root.base.Length).TrimStart('\')
            return Join-Path $root.prefix $relative
        }
    }
    return Join-Path "external" ([IO.Path]::GetFileName($normalized))
}

function Copy-ToArchive {
    param(
        [string]$SourcePath,
        [string]$ArchiveRoot,
        [string]$ProjectPath,
        [string]$CommonPath,
        [string]$ResearchPath
    )
    $relative = Get-RelativeBackupPath -Path $SourcePath -ProjectPath $ProjectPath -CommonPath $CommonPath -ResearchPath $ResearchPath
    $targetPath = Join-Path $ArchiveRoot $relative
    $parent = Split-Path -Path $targetPath -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    if (Test-Path -LiteralPath $SourcePath -PathType Container) {
        Copy-Item -LiteralPath $SourcePath -Destination $targetPath -Recurse -Force
    }
    else {
        Copy-Item -LiteralPath $SourcePath -Destination $targetPath -Force
    }
    return $targetPath
}

function Remove-RetiredSymbolsFromObject {
    param(
        [object]$Node,
        [string[]]$RetiredSymbols
    )

    if ($null -eq $Node) { return $null }
    if ($Node -is [string] -or $Node -is [int] -or $Node -is [long] -or $Node -is [double] -or $Node -is [decimal] -or $Node -is [bool]) {
        return $Node
    }
    if ($Node -is [pscustomobject]) {
        $out = [ordered]@{}
        foreach ($prop in $Node.PSObject.Properties) {
            $value = Remove-RetiredSymbolsFromObject -Node $prop.Value -RetiredSymbols $RetiredSymbols
            if ($prop.Value -is [System.Collections.IEnumerable] -and -not ($prop.Value -is [string]) -and $prop.Name -match '^(expected_symbols|symbols_without_candidates|symbols_without_rows|symbols_without_labeled|symbols_present|symbols)$') {
                $value = @($value | Where-Object { $RetiredSymbols -notcontains [string]$_ })
            }
            $out[$prop.Name] = $value
        }
        if ($out.Contains("expected_symbols") -and $out.Contains("expected_symbols_count")) {
            $out["expected_symbols_count"] = @($out["expected_symbols"]).Count
        }
        if ($out.Contains("symbols_without_candidates") -and $out.Contains("missing_candidate_count")) {
            $out["missing_candidate_count"] = @($out["symbols_without_candidates"]).Count
        }
        return [pscustomobject]$out
    }
    if ($Node -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($key in $Node.Keys) {
            $value = Remove-RetiredSymbolsFromObject -Node $Node[$key] -RetiredSymbols $RetiredSymbols
            if ($Node[$key] -is [System.Collections.IEnumerable] -and -not ($Node[$key] -is [string]) -and [string]$key -match '^(expected_symbols|symbols_without_candidates|symbols_without_rows|symbols_without_labeled|symbols_present|symbols)$') {
                $value = @($value | Where-Object { $RetiredSymbols -notcontains [string]$_ })
            }
            $out[[string]$key] = $value
        }
        if ($out.Contains("expected_symbols") -and $out.Contains("expected_symbols_count")) {
            $out["expected_symbols_count"] = @($out["expected_symbols"]).Count
        }
        if ($out.Contains("symbols_without_candidates") -and $out.Contains("missing_candidate_count")) {
            $out["missing_candidate_count"] = @($out["symbols_without_candidates"]).Count
        }
        return $out
    }

    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        $items = @()
        foreach ($item in $Node) {
            $items += ,(Remove-RetiredSymbolsFromObject -Node $item -RetiredSymbols $RetiredSymbols)
        }
        return $items
    }

    return $Node
}

function Rewrite-FilteredJsonFile {
    param(
        [string]$Path,
        [string[]]$RetiredSymbols
    )
    $payload = Read-JsonFile -Path $Path
    if ($null -eq $payload) { return $false }
    $filtered = Remove-RetiredSymbolsFromObject -Node $payload -RetiredSymbols $RetiredSymbols
    $filtered | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $true
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$commonPath = (Resolve-Path -LiteralPath $CommonStateRoot).Path
$researchPath = (Resolve-Path -LiteralPath $ResearchRoot).Path
$planPath = Join-Path $projectPath "CONFIG\scalping_universe_plan.json"
$handoffRoot = Join-Path $projectPath "SERVER_PROFILE\HANDOFF"
$remoteSimRoot = Join-Path $projectPath "SERVER_PROFILE\REMOTE_SIM"
$stateRoot = Join-Path $commonPath "state"
$keyRoot = Join-Path $commonPath "key"
$metricsTargets = @(
    "C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor\paper_gate_acceptor_latest_metrics.json"
)

if (-not (Test-Path -LiteralPath $planPath)) {
    throw "Missing scalping universe plan: $planPath"
}

$plan = Read-JsonFile -Path $planPath
$retiredSymbols = @($plan.retired_symbols | ForEach-Object { [string]$_ })
$targetList = New-Object System.Collections.Generic.List[object]
$patterns = @($retiredSymbols | ForEach-Object { [regex]::Escape([string]$_) })
$allowedExt = @(".json", ".txt", ".md", ".ini", ".csv", ".set", ".mqh", ".mq5", ".ex5")

foreach ($symbol in $retiredSymbols) {
    Add-Target -Targets $targetList -Path (Join-Path $stateRoot $symbol) -Kind "directory" -Reason "retired_state_dir" -Action "archive_and_remove"
    Add-Target -Targets $targetList -Path (Join-Path $keyRoot $symbol) -Kind "directory" -Reason "retired_key_dir" -Action "archive_and_remove"
}

foreach ($rootSpec in @(
    @{ root = $handoffRoot; reason = "handoff_retired_leak" },
    @{ root = $remoteSimRoot; reason = "remote_sim_retired_leak" }
)) {
    if (-not (Test-Path -LiteralPath $rootSpec.root)) { continue }
    $files = Get-ChildItem -LiteralPath $rootSpec.root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $allowedExt -contains $_.Extension.ToLowerInvariant() }
    foreach ($file in $files) {
        $pathHit = $false
        foreach ($symbol in $retiredSymbols) {
            if ($file.FullName -match [regex]::Escape($symbol)) {
                $pathHit = $true
                break
            }
        }
        $contentHit = $false
        if (-not $pathHit) {
            try {
                $contentHit = (Select-String -LiteralPath $file.FullName -Pattern $patterns -SimpleMatch -Quiet -Encoding UTF8)
            }
            catch {
                $contentHit = $false
            }
        }
        if ($pathHit -or $contentHit) {
            Add-Target -Targets $targetList -Path $file.FullName -Kind "file" -Reason $rootSpec.reason -Action "archive_and_remove"
        }
    }
}

foreach ($metricsPath in $metricsTargets) {
    if (-not (Test-Path -LiteralPath $metricsPath)) { continue }
    try {
        $raw = Get-Content -LiteralPath $metricsPath -Raw -Encoding UTF8
        $hasLeak = $false
        foreach ($symbol in $retiredSymbols) {
            if ($raw -match [regex]::Escape($symbol)) {
                $hasLeak = $true
                break
            }
        }
        if ($hasLeak) {
            Add-Target -Targets $targetList -Path $metricsPath -Kind "json" -Reason "global_metrics_retired_expectation" -Action "archive_and_rewrite"
        }
    }
    catch {
    }
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$archiveRoot = Join-Path $BackupRoot ("retired_symbol_cleanup_" + $stamp)
$archived = New-Object System.Collections.Generic.List[object]
$cleaned = New-Object System.Collections.Generic.List[object]
$unchanged = New-Object System.Collections.Generic.List[object]
$failed = New-Object System.Collections.Generic.List[object]

if ($Mode -eq "archive-and-clean") {
    New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null
    foreach ($target in $targetList) {
        try {
            $archivePath = Copy-ToArchive -SourcePath $target.path -ArchiveRoot $archiveRoot -ProjectPath $projectPath -CommonPath $commonPath -ResearchPath $researchPath
            $archived.Add([pscustomobject]@{
                path = $target.path
                archive_path = $archivePath
                reason = $target.reason
            }) | Out-Null

            if ($target.action -eq "archive_and_remove") {
                Remove-Item -LiteralPath $target.path -Recurse -Force
                $cleaned.Add([pscustomobject]@{
                    path = $target.path
                    action = "removed"
                    reason = $target.reason
                }) | Out-Null
            }
            elseif ($target.action -eq "archive_and_rewrite") {
                $rewritten = Rewrite-FilteredJsonFile -Path $target.path -RetiredSymbols $retiredSymbols
                if ($rewritten) {
                    $cleaned.Add([pscustomobject]@{
                        path = $target.path
                        action = "rewritten_filtered_json"
                        reason = $target.reason
                    }) | Out-Null
                }
                else {
                    $failed.Add([pscustomobject]@{
                        path = $target.path
                        action = "rewrite_failed"
                        reason = $target.reason
                    }) | Out-Null
                }
            }
        }
        catch {
            $failed.Add([pscustomobject]@{
                path = $target.path
                action = "failed"
                reason = $target.reason
                error = $_.Exception.Message
            }) | Out-Null
        }
    }
}
else {
    foreach ($target in $targetList) {
        $unchanged.Add([pscustomobject]@{
            path = $target.path
            action = "dry_run_only"
            reason = $target.reason
        }) | Out-Null
    }
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$jsonPath = Join-Path $OutputRoot "retired_symbol_cleanup_latest.json"
$mdPath = Join-Path $OutputRoot "retired_symbol_cleanup_latest.md"
$archiveRootValue = if ($Mode -eq "archive-and-clean") { [string]$archiveRoot } else { "" }

$report = New-Object System.Collections.Specialized.OrderedDictionary
$report.Add("schema_version", "1.0")
$report.Add("generated_at_local", (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
$report.Add("mode", [string]$Mode)
$report.Add("universe_version", [string]$plan.universe_version)
$report.Add("retired_symbols", [object]([object[]]@($retiredSymbols)))
$report.Add("archive_root", [string]$archiveRootValue)
$report.Add("found_count", [int]$targetList.Count)
$report.Add("archived_count", [int]$archived.Count)
$report.Add("cleaned_count", [int]$cleaned.Count)
$report.Add("unchanged_count", [int]$unchanged.Count)
$report.Add("failed_count", [int]$failed.Count)
$report.Add("found_paths", [string[]]@($targetList.ToArray() | ForEach-Object { [string]$_.path }))
$report.Add("archived_paths", [string[]]@($archived.ToArray() | ForEach-Object { [string]$_.path }))
$report.Add("cleaned_paths", [string[]]@($cleaned.ToArray() | ForEach-Object { [string]$_.path }))
$report.Add("failed_paths", [string[]]@($failed.ToArray() | ForEach-Object { [string]$_.path }))

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Cleanup Retired Symbol Residue")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- mode: {0}" -f $report.mode))
$lines.Add(("- universe_version: {0}" -f $report.universe_version))
$lines.Add(("- found_count: {0}" -f $report.found_count))
$lines.Add(("- archived_count: {0}" -f $report.archived_count))
$lines.Add(("- cleaned_count: {0}" -f $report.cleaned_count))
$lines.Add(("- failed_count: {0}" -f $report.failed_count))
$lines.Add("")
$lines.Add("## Found")
$lines.Add("")
foreach ($item in $targetList.ToArray()) {
    $lines.Add(("- {0} [{1}] -> {2}" -f $item.path, $item.reason, $item.action))
}
$lines.Add("")
$lines.Add("## Cleaned")
$lines.Add("")
foreach ($item in $cleaned.ToArray()) {
    $lines.Add(("- {0} -> {1}" -f $item.path, $item.action))
}
$lines.Add("")
$lines.Add("## Failed")
$lines.Add("")
foreach ($item in $failed.ToArray()) {
    $lines.Add(("- {0} -> {1}" -f $item.path, $item.error))
}
$lines -join "`r`n" | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report
