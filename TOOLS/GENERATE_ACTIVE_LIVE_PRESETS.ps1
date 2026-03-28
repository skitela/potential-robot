param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\SERVER_PROFILE\PACKAGE\MQL5\Presets\ActiveLive",
    [switch]$AllowBlockedAuditGate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$registryPath = Join-Path $projectPath "CONFIG\microbots_registry.json"
$planPath = Join-Path $projectPath "CONFIG\scalping_universe_plan.json"

& (Join-Path $projectPath "TOOLS\ASSERT_AUDIT_SUPERVISOR_GATE.ps1") `
    -ProjectRoot $projectPath `
    -GateType LIVE `
    -AllowBlocked:$AllowBlockedAuditGate | Out-Null

if (-not (Test-Path -LiteralPath $registryPath)) {
    throw "Missing registry: $registryPath"
}
if (-not (Test-Path -LiteralPath $planPath)) {
    throw "Missing scalping universe plan: $planPath"
}

$registry = Get-Content -Raw $registryPath | ConvertFrom-Json
$plan = Get-Content -Raw $planPath | ConvertFrom-Json
$planHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $planPath).Hash
$paperLiveSymbols = @($plan.paper_live_first_wave | ForEach-Object { [string]$_ })
if ($paperLiveSymbols.Count -le 0) {
    throw "Universe plan has empty paper_live_first_wave."
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$generated = @()

foreach ($row in @($registry.symbols | Where-Object { $paperLiveSymbols -contains [string]$_.symbol })) {
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
    universe_version = [string]$plan.universe_version
    plan_hash = $planHash
    paper_live_symbols = $paperLiveSymbols
    generated = $generated
}

$reportPath = Join-Path $projectPath "EVIDENCE\active_live_presets_report.json"
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 5
