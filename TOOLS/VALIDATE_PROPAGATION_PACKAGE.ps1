param(
    [string]$ProjectRoot = "C:\\MAKRO_I_MIKRO_BOT",
    [string]$PackageRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = Join-Path $ProjectRoot "EVIDENCE\\PROPAGATION_PACKAGE\\PACKAGE_FX_MAIN_EURUSD"
}

$manifestPath = Join-Path $PackageRoot "manifest.json"
$outJson = Join-Path $ProjectRoot "EVIDENCE\\propagation_package_validation_report.json"
$outTxt = Join-Path $ProjectRoot "EVIDENCE\\propagation_package_validation_report.txt"

$issues = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Missing propagation package manifest: $manifestPath"
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$payloadRoot = Join-Path $PackageRoot "PAYLOAD"

if (-not (Test-Path -LiteralPath $payloadRoot)) {
    $issues.Add("Missing PAYLOAD directory.")
}

foreach ($relativePath in $manifest.shared_payload_relative_paths) {
    $payloadPath = Join-Path $payloadRoot $relativePath
    if (-not (Test-Path -LiteralPath $payloadPath)) {
        $issues.Add("Missing payload file: $relativePath")
    }
}

foreach ($privatePath in $manifest.experimental_private_paths_not_included) {
    $payloadPrivatePath = Join-Path $payloadRoot $privatePath
    if (Test-Path -LiteralPath $payloadPrivatePath) {
        $issues.Add("Private EURUSD-only file leaked into payload: $privatePath")
    }
}

$forbiddenPatterns = @(
    "MQL5\\Experts\\MicroBots\\MicroBot_*.mq5",
    "MQL5\\Include\\Profiles\\Profile_*.mqh",
    "MQL5\\Include\\Strategies\\Strategy_*.mqh"
)

foreach ($pattern in $forbiddenPatterns) {
    $matches = Get-ChildItem -Path $payloadRoot -Recurse -File | Where-Object {
        $_.FullName -like (Join-Path $payloadRoot $pattern)
    }
    foreach ($match in $matches) {
        $issues.Add("Forbidden local-gene file found in payload: $($match.FullName.Substring($payloadRoot.Length + 1))")
    }
}

$familyRegistryPath = Join-Path $ProjectRoot "CONFIG\\family_policy_registry.json"
$familyRegistry = Get-Content -Raw -LiteralPath $familyRegistryPath | ConvertFrom-Json
$familyEntry = $familyRegistry.families | Where-Object { $_.family -eq $manifest.target_family } | Select-Object -First 1

if (-not $familyEntry) {
    $issues.Add("Target family '$($manifest.target_family)' not found in family registry.")
}
else {
    foreach ($symbol in $manifest.target_symbols) {
        if ($familyEntry.symbols -notcontains $symbol) {
            $issues.Add("Target symbol '$symbol' does not belong to family '$($manifest.target_family)'.")
        }
    }
}

if (-not $manifest.preserve_local -or $manifest.preserve_local.Count -eq 0) {
    $issues.Add("Missing preserve_local list in manifest.")
}

$result = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    package_root = $PackageRoot
    ok = ($issues.Count -eq 0)
    issue_count = $issues.Count
    issues = @($issues)
}

$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $outJson -Encoding UTF8

$lines = @()
$lines += "Walidacja pakietu propagacji"
$lines += ("package_root={0}" -f $PackageRoot)
$lines += ("ok={0}" -f $result.ok)
if ($issues.Count -gt 0) {
    $lines += ""
    $lines += "Problemy:"
    $issues | ForEach-Object { $lines += ("- {0}" -f $_) }
}
$lines | Set-Content -LiteralPath $outTxt -Encoding UTF8

$result | ConvertTo-Json -Depth 6
