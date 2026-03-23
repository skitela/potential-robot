param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$evidenceDir = Join-Path $ProjectRoot "EVIDENCE"
$jsonReport = Join-Path $evidenceDir "runtime_artifact_audit_report.json"
$txtReport = Join-Path $evidenceDir "runtime_artifact_audit_report.txt"

if (!(Test-Path -LiteralPath $registryPath)) {
    throw "Missing registry: $registryPath"
}

$registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json

function Get-AllowedSymbolNames {
    param([object[]]$RegistrySymbols)

    $set = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($item in @($RegistrySymbols)) {
        foreach ($candidate in @(Get-RegistrySymbolCandidates -RegistryItem $item)) {
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                [void]$set.Add($candidate)
            }
        }
    }

    return @($set | Sort-Object)
}

$expectedSymbols = Get-AllowedSymbolNames -RegistrySymbols $registry.symbols

function Get-UnexpectedDirectories {
    param(
        [string]$RootPath,
        [string[]]$AllowedNames
    )

    if (!(Test-Path -LiteralPath $RootPath)) {
        return @()
    }

    $dirs = Get-ChildItem -LiteralPath $RootPath -Directory -Force
    return @(
        $dirs | Where-Object {
            $AllowedNames -notcontains $_.Name
        } | Sort-Object Name | ForEach-Object {
            [ordered]@{
                name = $_.Name
                path = $_.FullName
                last_write_time = $_.LastWriteTime.ToString("o")
            }
        }
    )
}

$allowedByRoot = @{
    state = @($expectedSymbols + @("_families","_coordinator","_global","_domains","_groups"))
    logs  = @($expectedSymbols + @("_families","_coordinator"))
    run   = @($expectedSymbols)
    key   = @($expectedSymbols + @("_GLOBAL"))
}

$roots = @(
    [ordered]@{ name = "state"; path = (Join-Path $CommonRoot "state"); allowed = $allowedByRoot.state },
    [ordered]@{ name = "logs";  path = (Join-Path $CommonRoot "logs");  allowed = $allowedByRoot.logs },
    [ordered]@{ name = "run";   path = (Join-Path $CommonRoot "run");   allowed = $allowedByRoot.run },
    [ordered]@{ name = "key";   path = (Join-Path $CommonRoot "key");   allowed = $allowedByRoot.key }
)

$unexpectedByRoot = @()
$removed = @()

foreach ($root in $roots) {
    $items = Get-UnexpectedDirectories -RootPath $root.path -AllowedNames $root.allowed
    $unexpectedByRoot += [ordered]@{
        root = $root.name
        path = $root.path
        unexpected = @($items)
    }

    if ($Apply) {
        foreach ($item in $items) {
            if (Test-Path -LiteralPath $item.path) {
                Remove-Item -LiteralPath $item.path -Recurse -Force
                $removed += [ordered]@{
                    category = "common_root_dir"
                    path = $item.path
                }
            }
        }
    }
}

$restoreTmpPath = Join-Path $ProjectRoot "_restore_tmp_101302"
$restoreTmpPresent = Test-Path -LiteralPath $restoreTmpPath
if ($Apply -and $restoreTmpPresent) {
    Remove-Item -LiteralPath $restoreTmpPath -Recurse -Force
    $removed += [ordered]@{
        category = "project_tmp_dir"
        path = $restoreTmpPath
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    common_root = $CommonRoot
    apply_mode = [bool]$Apply
    expected_symbols = @($expectedSymbols)
    unexpected_by_root = @($unexpectedByRoot)
    restore_tmp_present = $restoreTmpPresent
    restore_tmp_path = $restoreTmpPath
    removed = @($removed)
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonReport -Encoding UTF8

$lines = @()
$lines += "Runtime artifact audit"
$lines += "apply_mode=$([bool]$Apply)"
$lines += "expected_symbols=$($expectedSymbols -join ',')"
$lines += ""
foreach ($entry in $unexpectedByRoot) {
    $lines += ("[{0}] {1}" -f $entry.root,$entry.path)
    if ($entry.unexpected.Count -eq 0) {
        $lines += "- no unexpected directories"
    }
    else {
        foreach ($item in $entry.unexpected) {
            $lines += ("- unexpected: {0}" -f $item.path)
        }
    }
    $lines += ""
}
$lines += ("restore_tmp_present={0}" -f $restoreTmpPresent)
$lines += ("restore_tmp_path={0}" -f $restoreTmpPath)
$lines += ""
$lines += "removed:"
if ($removed.Count -eq 0) {
    $lines += "- none"
}
else {
    foreach ($item in $removed) {
        $lines += ("- {0}: {1}" -f $item.category,$item.path)
    }
}
$lines | Set-Content -LiteralPath $txtReport -Encoding UTF8

$report | ConvertTo-Json -Depth 8
