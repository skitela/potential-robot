param(
    [string]$ProjectRoot = "C:\\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$familyPath = Join-Path $ProjectRoot "CONFIG\\family_policy_registry.json"
$referencePath = Join-Path $ProjectRoot "CONFIG\\family_reference_registry.json"
$jsonReport = Join-Path $ProjectRoot "EVIDENCE\\family_reference_validation_report.json"
$txtReport = Join-Path $ProjectRoot "EVIDENCE\\family_reference_validation_report.txt"

$familyRegistry = Get-Content -Raw -LiteralPath $familyPath | ConvertFrom-Json
$referenceRegistry = Get-Content -Raw -LiteralPath $referencePath | ConvertFrom-Json

$familyMap = @{}
foreach ($family in $familyRegistry.families) {
    $familyMap[$family.family] = $family
}

$checks = @()
$issues = @()

foreach ($reference in $referenceRegistry.references) {
    $familyName = [string]$reference.family
    if (-not $familyMap.ContainsKey($familyName)) {
        $issues += [ordered]@{
            family = $familyName
            field = "family"
            actual = "<missing>"
            expected = "present in family_policy_registry"
        }
        continue
    }

    $family = $familyMap[$familyName]
    $sourceOk = ($family.symbols -contains $reference.source_symbol)
    $targetsOk = ((@($reference.target_symbols) | Sort-Object) -join ",") -eq ((@($family.symbols) | Sort-Object) -join ",")

    $row = [ordered]@{
        family = $familyName
        source_symbol = $reference.source_symbol
        source_in_family = $sourceOk
        target_symbols_match = $targetsOk
        target_count = @($reference.target_symbols).Count
        ok = ($sourceOk -and $targetsOk)
    }

    if (-not $sourceOk) {
        $issues += [ordered]@{
            family = $familyName
            field = "source_symbol"
            actual = $reference.source_symbol
            expected = (@($family.symbols) -join ",")
        }
    }
    if (-not $targetsOk) {
        $issues += [ordered]@{
            family = $familyName
            field = "target_symbols"
            actual = (@($reference.target_symbols) -join ",")
            expected = (@($family.symbols) -join ",")
        }
    }

    $checks += [pscustomobject]$row
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    ok = ($issues.Count -eq 0)
    checks = @($checks)
    issues = @($issues)
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonReport -Encoding UTF8

$lines = @()
$lines += "Family reference validation report"
$lines += "ok=$($report.ok)"
$lines += ""
foreach ($row in $checks) {
    $lines += ("{0}: source={1}, source_in_family={2}, targets_match={3}, ok={4}" -f $row.family,$row.source_symbol,$row.source_in_family,$row.target_symbols_match,$row.ok)
}
if ($issues.Count -gt 0) {
    $lines += ""
    $lines += "Issues:"
    foreach ($issue in $issues) {
        $lines += ("- {0} {1}: actual={2}, expected={3}" -f $issue.family,$issue.field,$issue.actual,$issue.expected)
    }
}
$lines | Set-Content -LiteralPath $txtReport -Encoding UTF8

$report | ConvertTo-Json -Depth 8

if ($issues.Count -gt 0) {
    exit 1
}
