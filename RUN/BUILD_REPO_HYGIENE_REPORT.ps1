param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Git {
    param([string[]]$Arguments)

    $output = & git -C $ProjectRoot @Arguments 2>$null
    return @($output)
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

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$statusLines = Invoke-Git -Arguments @("status", "--porcelain")
$knownGeneratedPaths = @(
    "CONFIG/family_policy_registry.json",
    "CONFIG/family_reference_registry.json",
    "SERVER_PROFILE/HANDOFF/handoff_manifest.json"
)

$classified = New-Object System.Collections.Generic.List[object]
foreach ($line in $statusLines) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) {
        continue
    }

    $status = $line.Substring(0,2)
    $path = $line.Substring(3).Trim()
    $bucket = "code_or_logic"
    $timestampOnly = $false

    if ($knownGeneratedPaths -contains $path) {
        $timestampOnly = Test-TimestampOnlyDiff -RelativePath $path
        $bucket = if ($timestampOnly) { "generated_timestamp_only" } else { "generated_meaningful" }
    }
    elseif ($path -match '^(EVIDENCE/|DOCS/06_MT5_CHART_ATTACHMENT_PLAN|SERVER_PROFILE/HANDOFF/DOCS/)') {
        $bucket = "generated_or_report"
    }

    $classified.Add([pscustomobject]@{
        status = $status
        path = $path
        bucket = $bucket
        timestamp_only = $timestampOnly
    }) | Out-Null
}

$items = @($classified.ToArray())
$codeItems = @($items | Where-Object { $_.bucket -eq "code_or_logic" })
$timestampItems = @($items | Where-Object { $_.bucket -eq "generated_timestamp_only" })
$generatedItems = @($items | Where-Object { $_.bucket -eq "generated_or_report" -or $_.bucket -eq "generated_meaningful" })

$verdict = "CZYSTO"
if ($codeItems.Count -gt 0) {
    $verdict = "BRUD_KODU"
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
        code_or_logic = $codeItems.Count
        generated_timestamp_only = $timestampItems.Count
        generated_other = $generatedItems.Count
    }
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
$lines.Add(("- code_or_logic: {0}" -f $report.counts.code_or_logic))
$lines.Add(("- generated_timestamp_only: {0}" -f $report.counts.generated_timestamp_only))
$lines.Add(("- generated_other: {0}" -f $report.counts.generated_other))
$lines.Add("")

foreach ($item in $items) {
    $lines.Add(("- [{0}] {1} | bucket={2}" -f $item.status, $item.path, $item.bucket))
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8
