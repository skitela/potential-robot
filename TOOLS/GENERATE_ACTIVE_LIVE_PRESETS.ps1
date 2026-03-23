param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\SERVER_PROFILE\PACKAGE\MQL5\Presets\ActiveLive",
    [switch]$AllowBlockedAuditGate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$registryPath = Join-Path $projectPath "CONFIG\microbots_registry.json"

& (Join-Path $projectPath "TOOLS\ASSERT_AUDIT_SUPERVISOR_GATE.ps1") `
    -ProjectRoot $projectPath `
    -GateType LIVE `
    -AllowBlocked:$AllowBlockedAuditGate | Out-Null

if (-not (Test-Path -LiteralPath $registryPath)) {
    throw "Missing registry: $registryPath"
}

$registry = Get-Content -Raw $registryPath | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$generated = @()

foreach ($row in $registry.symbols) {
    $sourcePreset = Join-Path $projectPath ("MQL5\Presets\" + $row.preset)
    if (-not (Test-Path -LiteralPath $sourcePreset)) {
        throw "Missing preset: $sourcePreset"
    }

    $targetPresetName = [System.IO.Path]::GetFileNameWithoutExtension($row.preset) + "_ACTIVE.set"
    $targetPreset = Join-Path $OutputRoot $targetPresetName

    $content = Get-Content -LiteralPath $sourcePreset
    $rewritten = foreach ($line in $content) {
        if ($line -match '^InpEnableLiveEntries=') {
            'InpEnableLiveEntries=true'
        }
        else {
            $line
        }
    }

    Set-Content -LiteralPath $targetPreset -Value $rewritten -Encoding ASCII

    $generated += [ordered]@{
        symbol = $row.symbol
        source_preset = $row.preset
        active_preset = $targetPresetName
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    ts_utc = [DateTime]::UtcNow.ToString("o")
    output_root = $OutputRoot
    generated = $generated
}

$reportPath = Join-Path $projectPath "EVIDENCE\active_live_presets_report.json"
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 5
