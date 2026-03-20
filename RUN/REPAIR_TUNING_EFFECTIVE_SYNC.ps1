param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$stateRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\state"
$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
New-Item -ItemType Directory -Force -Path $opsRoot | Out-Null

function Read-TabMap {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $map = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $parts = $line -split "`t", 2
        if ($parts.Count -lt 2) {
            continue
        }

        $map[$parts[0]] = $parts[1]
    }

    return $map
}

function Write-TabMap {
    param(
        [string]$Path,
        [System.Collections.Specialized.OrderedDictionary]$Map
    )

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in $Map.Keys) {
        $lines.Add(("{0}`t{1}" -f $key, $Map[$key]))
    }
    ($lines -join "`r`n") | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function ConvertTo-BoolLoose {
    param($Value)

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $false
    }

    return @("1","true","yes","on") -contains $text.ToLowerInvariant()
}

function ConvertTo-DoubleLoose {
    param($Value)

    $number = 0.0
    [void][double]::TryParse(
        ([string]$Value),
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$number
    )
    return $number
}

$repaired = New-Object System.Collections.Generic.List[object]

if (Test-Path -LiteralPath $stateRoot) {
    $symbolDirs = @(
        Get-ChildItem -LiteralPath $stateRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike "_*" }
    )

    foreach ($dir in $symbolDirs) {
        $localPath = Join-Path $dir.FullName "tuning_policy.csv"
        $effectivePath = Join-Path $dir.FullName "tuning_policy_effective.csv"
        $executionSummaryPath = Join-Path $dir.FullName "execution_summary.json"

        $localPolicy = Read-TabMap -Path $localPath
        $effectivePolicy = Read-TabMap -Path $effectivePath
        $executionSummary = Read-JsonFile -Path $executionSummaryPath

        if ($null -eq $localPolicy -or $null -eq $effectivePolicy -or $null -eq $executionSummary) {
            continue
        }

        $paperRuntime = [bool]$executionSummary.paper_runtime_override_active
        $acceptedRiskMasked = (
            $paperRuntime -and
            [string]$localPolicy["experiment_status"] -eq "ACCEPTED" -and
            (
                [string]$localPolicy["trust_reason_domain"] -eq "RISK" -or
                [string]$localPolicy["trust_reason_class"] -eq "CONTRACT"
            )
        )

        if (-not $acceptedRiskMasked) {
            continue
        }

        $localConfidenceCap = ConvertTo-DoubleLoose -Value $localPolicy["confidence_cap"]
        $localRiskCap = ConvertTo-DoubleLoose -Value $localPolicy["risk_cap"]

        if ($localConfidenceCap -le 0.0 -or $localRiskCap -le 0.0) {
            continue
        }

        $effectiveTrusted = ConvertTo-BoolLoose -Value $effectivePolicy["trusted_data"]
        $effectiveConfidenceCap = ConvertTo-DoubleLoose -Value $effectivePolicy["confidence_cap"]
        $effectiveRiskCap = ConvertTo-DoubleLoose -Value $effectivePolicy["risk_cap"]

        $changed = $false
        if (-not $effectiveTrusted) {
            $effectivePolicy["trusted_data"] = "1"
            $changed = $true
        }
        if ($effectiveConfidenceCap -le 0.0 -or [math]::Abs($effectiveConfidenceCap - $localConfidenceCap) -gt 0.000001) {
            $effectivePolicy["confidence_cap"] = $localPolicy["confidence_cap"]
            $changed = $true
        }
        if ($effectiveRiskCap -le 0.0 -or [math]::Abs($effectiveRiskCap - $localRiskCap) -gt 0.000001) {
            $effectivePolicy["risk_cap"] = $localPolicy["risk_cap"]
            $changed = $true
        }

        if ($changed) {
            Write-TabMap -Path $effectivePath -Map $effectivePolicy
            $repaired.Add([pscustomobject]@{
                symbol = $dir.Name
                trusted_data = $effectivePolicy["trusted_data"]
                confidence_cap = $effectivePolicy["confidence_cap"]
                risk_cap = $effectivePolicy["risk_cap"]
                source = "local_policy"
            }) | Out-Null
        }
    }
}

$report = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    repaired_count = $repaired.Count
    repaired = @($repaired | ForEach-Object { $_ })
}

$jsonPath = Join-Path $opsRoot "tuning_effective_sync_repair_latest.json"
$mdPath = Join-Path $opsRoot "tuning_effective_sync_repair_latest.md"

([pscustomobject]$report) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Tuning Effective Sync Repair")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- repaired_count: {0}" -f $report.repaired_count))
$lines.Add("")
$lines.Add("## Repaired")
$lines.Add("")
if ($repaired.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in $repaired) {
        $lines.Add(("- {0}: trusted_data={1}, confidence_cap={2}, risk_cap={3}" -f $item.symbol, $item.trusted_data, $item.confidence_cap, $item.risk_cap))
    }
}
($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

([pscustomobject]$report)
