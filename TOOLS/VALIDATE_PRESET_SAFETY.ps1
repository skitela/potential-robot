param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$registryPath = Join-Path $projectPath "CONFIG\microbots_registry.json"
$activeRoot = Join-Path $projectPath "SERVER_PROFILE\PACKAGE\MQL5\Presets\ActiveLive"

if (-not (Test-Path -LiteralPath $registryPath)) {
    throw "Missing registry: $registryPath"
}

$registry = Get-Content -Raw $registryPath | ConvertFrom-Json
$issues = New-Object System.Collections.Generic.List[string]
$symbols = @()

foreach ($row in $registry.symbols) {
    $presetPath = Join-Path $projectPath ("MQL5\Presets\" + $row.preset)
    if (-not (Test-Path -LiteralPath $presetPath)) {
        $issues.Add("PRESET_MISSING:$($row.symbol):$($row.preset)")
        continue
    }

    $baseLine = Get-Content -LiteralPath $presetPath | Where-Object { $_ -match '^InpEnableLiveEntries=' } | Select-Object -First 1
    $baseValue = if ($null -eq $baseLine) { "" } else { ($baseLine -split '=',2)[1] }
    $baseSafe = ($baseValue -eq "false")

    if (-not $baseSafe) {
        $issues.Add("BASE_PRESET_NOT_SAFE:$($row.symbol):$($row.preset)")
    }

    $activeName = ([System.IO.Path]::GetFileNameWithoutExtension($row.preset)) + "_ACTIVE.set"
    $activePath = Join-Path $activeRoot $activeName
    $activePresent = Test-Path -LiteralPath $activePath
    $activeValue = ""
    $activeValid = $true

    if ($activePresent) {
        $activeLine = Get-Content -LiteralPath $activePath | Where-Object { $_ -match '^InpEnableLiveEntries=' } | Select-Object -First 1
        $activeValue = if ($null -eq $activeLine) { "" } else { ($activeLine -split '=',2)[1] }
        $activeValid = ($activeValue -eq "true")
        if (-not $activeValid) {
            $issues.Add("ACTIVE_PRESET_NOT_LIVE:$($row.symbol):$activeName")
        }
    }

    $symbols += [ordered]@{
        symbol = $row.symbol
        base_preset = $row.preset
        base_live_value = $baseValue
        base_safe = $baseSafe
        active_preset = $activeName
        active_present = $activePresent
        active_live_value = $activeValue
        active_valid = $activeValid
    }
}

$result = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $projectPath
    ok = ($issues.Count -eq 0)
    issues = @($issues)
    symbols = $symbols
}

$jsonPath = Join-Path $projectPath "EVIDENCE\preset_safety_report.json"
$txtPath = Join-Path $projectPath "EVIDENCE\preset_safety_report.txt"

$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$txt = @()
$txt += "PRESET SAFETY REPORT"
$txt += ("OK={0}" -f $result.ok)
$txt += ""
foreach ($row in $symbols) {
    $txt += ("{0} | base={1} | base_safe={2} | active_present={3} | active_valid={4}" -f $row.symbol,$row.base_live_value,$row.base_safe,$row.active_present,$row.active_valid)
}
$txt | Set-Content -LiteralPath $txtPath -Encoding ASCII

$result | ConvertTo-Json -Depth 6

if (-not $result.ok) {
    exit 1
}
