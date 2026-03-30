param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [string]$ContractPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\supervisor_scope_contract_v1.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Git {
    param([string[]]$Arguments)

    $quotedArgs = foreach ($argument in @($Arguments)) {
        if ([string]::IsNullOrWhiteSpace($argument)) {
            continue
        }

        if ($argument -match '\s') {
            '"' + ($argument -replace '"', '\"') + '"'
        }
        else {
            $argument
        }
    }

    $command = 'git -c core.safecrlf=false -C "' + $ProjectRoot + '" ' + ($quotedArgs -join ' ') + ' 2>nul'
    $output = & cmd.exe /d /c $command
    return @(
        $output | Where-Object {
            $_ -and ($_ -notmatch 'could not open directory .+\.pytest_cache')
        }
    )
}

function Test-TimestampOnlyDiff {
    param([string]$RelativePath)

    $diffLines = Invoke-Git -Arguments @("diff", "--unified=0", "--", $RelativePath)
    if ($diffLines.Count -eq 0) {
        return $false
    }

    $changedLines = @(
        $diffLines | Where-Object {
            ($_ -match '^[+-]') -and
            ($_ -notmatch '^\+\+\+') -and
            ($_ -notmatch '^---')
        }
    )

    if ($changedLines.Count -eq 0) {
        return $false
    }

    foreach ($line in $changedLines) {
        if (
            $line -notmatch '"generated_at_utc"\s*:' -and
            $line -notmatch '"generated_at_local"\s*:' -and
            $line -notmatch '"ts_utc"\s*:'
        ) {
            return $false
        }
    }

    return $true
}

function Read-JsonSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Test-MatchesAnyPattern {
    param(
        [string]$Value,
        [object[]]$Patterns
    )

    foreach ($pattern in @($Patterns)) {
        if ([string]::IsNullOrWhiteSpace([string]$pattern)) {
            continue
        }

        if ($Value -like [string]$pattern) {
            return $true
        }
    }

    return $false
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$statusLines = Invoke-Git -Arguments @("status", "--porcelain")
$contract = Read-JsonSafe -Path $ContractPath
$knownGeneratedPaths = if ($null -ne $contract) { @($contract.timestamp_only_candidates) } else { @(
    "CONFIG/family_policy_registry.json",
    "CONFIG/family_reference_registry.json",
    "SERVER_PROFILE/HANDOFF/handoff_manifest.json"
) }
$generatedPatterns = if ($null -ne $contract) { @($contract.generated_path_patterns) } else { @(
    "EVIDENCE/*",
    "SERVER_PROFILE/HANDOFF/DOCS/*",
    "DOCS/06_MT5_CHART_ATTACHMENT_PLAN*"
) }
$auxiliaryBridgePatterns = if ($null -ne $contract) { @($contract.auxiliary_bridge_path_patterns) } else { @() }

$classified = New-Object System.Collections.Generic.List[object]
foreach ($line in $statusLines) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) {
        continue
    }

    $status = $line.Substring(0,2)
    $path = $line.Substring(3).Trim()
    $bucket = "system_core"
    $timestampOnly = $false

    if ($knownGeneratedPaths -contains $path) {
        $timestampOnly = Test-TimestampOnlyDiff -RelativePath $path
        $bucket = if ($timestampOnly) { "generated_timestamp_only" } else { "generated_meaningful" }
    }
    elseif (Test-MatchesAnyPattern -Value $path -Patterns $generatedPatterns) {
        $bucket = "generated_or_report"
    }
    elseif (Test-MatchesAnyPattern -Value $path -Patterns $auxiliaryBridgePatterns) {
        $bucket = "auxiliary_bridge"
    }

    $classified.Add([pscustomobject]@{
        status = $status
        path = $path
        bucket = $bucket
        timestamp_only = $timestampOnly
    }) | Out-Null
}

$items = @($classified.ToArray())
$systemCoreItems = @($items | Where-Object { $_.bucket -eq "system_core" })
$auxiliaryBridgeItems = @($items | Where-Object { $_.bucket -eq "auxiliary_bridge" })
$timestampItems = @($items | Where-Object { $_.bucket -eq "generated_timestamp_only" })
$generatedItems = @($items | Where-Object { $_.bucket -eq "generated_or_report" -or $_.bucket -eq "generated_meaningful" })

$verdict = "CZYSTO"
if ($systemCoreItems.Count -gt 0) {
    $verdict = "BRUD_SYSTEMU"
}
elseif ($auxiliaryBridgeItems.Count -gt 0) {
    $verdict = "BRUD_POMOCNICZY"
}
elseif ($generatedItems.Count -gt 0 -or $timestampItems.Count -gt 0) {
    $verdict = "TYLKO_ARTEFAKTY_LUB_ZNACZNIKI"
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    verdict = $verdict
    counts = [ordered]@{
        dirty_total = $items.Count
        system_core = $systemCoreItems.Count
        auxiliary_bridge = $auxiliaryBridgeItems.Count
        code_or_logic = ($systemCoreItems.Count + $auxiliaryBridgeItems.Count)
        generated_timestamp_only = $timestampItems.Count
        generated_other = $generatedItems.Count
    }
    scope_contract = if ($null -ne $contract) {
        [ordered]@{
            contract_path = $ContractPath
            auxiliary_bridge_path_patterns = @($auxiliaryBridgePatterns)
            generated_path_patterns = @($generatedPatterns)
        }
    } else { $null }
    items = @($items)
}

$jsonPath = Join-Path $OutputRoot "repo_hygiene_latest.json"
$mdPath = Join-Path $OutputRoot "repo_hygiene_latest.md"

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Repo Hygiene")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- dirty_total: {0}" -f $report.counts.dirty_total))
$lines.Add(("- system_core: {0}" -f $report.counts.system_core))
$lines.Add(("- auxiliary_bridge: {0}" -f $report.counts.auxiliary_bridge))
$lines.Add(("- code_or_logic: {0}" -f $report.counts.code_or_logic))
$lines.Add(("- generated_timestamp_only: {0}" -f $report.counts.generated_timestamp_only))
$lines.Add(("- generated_other: {0}" -f $report.counts.generated_other))
$lines.Add("")

foreach ($item in $items) {
    $lines.Add(("- [{0}] {1} | bucket={2}" -f $item.status, $item.path, $item.bucket))
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8
