param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ContractPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\supervisor_scope_contract_v1.json",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing required JSON file: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-OptionalString {
    param(
        [object]$Object,
        [string]$Name,
        [string]$Default = ""
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return [string]$property.Value
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$contract = Read-JsonFile -Path $ContractPath
$matches = New-Object System.Collections.Generic.List[object]
$items = New-Object System.Collections.Generic.List[object]

foreach ($relativePath in @($contract.supervisor_scripts)) {
    $fullPath = Join-Path $ProjectRoot $relativePath
    $exists = Test-Path -LiteralPath $fullPath
    $scriptMatches = New-Object System.Collections.Generic.List[object]

    if ($exists) {
        $content = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
        foreach ($ref in @($contract.forbidden_auxiliary_refs_in_supervisors)) {
            $needle = Get-OptionalString -Object $ref -Name "needle"
            if ([string]::IsNullOrWhiteSpace($needle)) {
                continue
            }

            $result = Select-String -Path $fullPath -SimpleMatch -Pattern $needle -Encoding UTF8
            foreach ($hit in @($result)) {
                $entry = [pscustomobject]@{
                    path = $relativePath
                    full_path = $fullPath
                    ref_id = (Get-OptionalString -Object $ref -Name "id")
                    label = (Get-OptionalString -Object $ref -Name "label")
                    needle = $needle
                    line_number = $hit.LineNumber
                    line = ($hit.Line.Trim())
                }
                $scriptMatches.Add($entry) | Out-Null
                $matches.Add($entry) | Out-Null
            }
        }
    }

    $items.Add([pscustomobject]@{
        path = $relativePath
        full_path = $fullPath
        exists = $exists
        clean_boundary = ($exists -and $scriptMatches.Count -eq 0)
        forbidden_refs_count = $scriptMatches.Count
        forbidden_refs = @($scriptMatches.ToArray())
    }) | Out-Null
}

$itemArray = @($items.ToArray())
$matchArray = @($matches.ToArray())
$missingCount = @($itemArray | Where-Object { -not $_.exists }).Count
$contaminatedCount = @($itemArray | Where-Object { $_.exists -and $_.forbidden_refs_count -gt 0 }).Count
$cleanCount = @($itemArray | Where-Object { $_.exists -and $_.forbidden_refs_count -eq 0 }).Count

$verdict = if ($missingCount -gt 0) {
    "SUPERVISOR_SCRIPTS_MISSING"
}
elseif ($contaminatedCount -gt 0) {
    "SYSTEM_AUXILIARY_BOUNDARY_BROKEN"
}
else {
    "SUPERVISOR_SCOPE_BOUNDARY_OK"
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    contract_path = $ContractPath
    verdict = $verdict
    summary = [ordered]@{
        total_supervisor_scripts = $itemArray.Count
        clean_boundary_count = $cleanCount
        contaminated_count = $contaminatedCount
        missing_count = $missingCount
        forbidden_refs_count = $matchArray.Count
    }
    forbidden_reference_catalog = @($contract.forbidden_auxiliary_refs_in_supervisors)
    items = $itemArray
    matches = $matchArray
}

$jsonPath = Join-Path $OutputRoot "supervisor_scope_audit_latest.json"
$mdPath = Join-Path $OutputRoot "supervisor_scope_audit_latest.md"

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Supervisor Scope Audit")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- total_supervisor_scripts: {0}" -f $report.summary.total_supervisor_scripts))
$lines.Add(("- clean_boundary_count: {0}" -f $report.summary.clean_boundary_count))
$lines.Add(("- contaminated_count: {0}" -f $report.summary.contaminated_count))
$lines.Add(("- missing_count: {0}" -f $report.summary.missing_count))
$lines.Add(("- forbidden_refs_count: {0}" -f $report.summary.forbidden_refs_count))
$lines.Add("")
$lines.Add("## Scripts")
$lines.Add("")
foreach ($item in $itemArray) {
    $lines.Add(("- {0}: exists={1}, clean_boundary={2}, forbidden_refs_count={3}" -f
        $item.path,
        $item.exists,
        $item.clean_boundary,
        $item.forbidden_refs_count))
}
$lines.Add("")

if ($matchArray.Count -gt 0) {
    $lines.Add("## Forbidden Matches")
    $lines.Add("")
    foreach ($match in $matchArray) {
        $lines.Add(("- {0}:{1} [{2}] {3}" -f
            $match.path,
            $match.line_number,
            $match.ref_id,
            $match.line))
    }
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report
