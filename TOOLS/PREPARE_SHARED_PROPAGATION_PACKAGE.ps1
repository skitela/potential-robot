param(
    [string]$ProjectRoot = "C:\\MAKRO_I_MIKRO_BOT",
    [ValidateSet("common","family","symbol")]
    [string]$Scope = "family",
    [string]$SourceSymbol = "EURUSD",
    [string]$Family = "",
    [string]$OutputRoot = "",
    [string]$PackageName = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectRoot "EVIDENCE\\PROPAGATION_PACKAGE"
}

$planTool = Join-Path $ProjectRoot "TOOLS\\PLAN_STRATEGY_PROPAGATION.ps1"
if (-not (Test-Path -LiteralPath $planTool)) {
    throw "Missing propagation planner: $planTool"
}

$planJson = & $planTool -ProjectRoot $ProjectRoot -Scope $Scope -SourceSymbol $SourceSymbol -Family $Family
$plan = $planJson | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($Family)) {
    $Family = [string]$plan.target_family
}

if ([string]::IsNullOrWhiteSpace($PackageName)) {
    $PackageName = "PACKAGE_{0}_{1}" -f $Family,$SourceSymbol
}

$packageRoot = Join-Path $OutputRoot $PackageName
$payloadRoot = Join-Path $packageRoot "PAYLOAD"

if (Test-Path -LiteralPath $packageRoot) {
    Remove-Item -LiteralPath $packageRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null

$sharedRelativePaths = @(
    "MQL5\\Include\\Core\\MbRuntimeTypes.mqh",
    "MQL5\\Include\\Core\\MbRuntimeKernel.mqh",
    "MQL5\\Include\\Core\\MbStorage.mqh",
    "MQL5\\Include\\Core\\MbStatusPlane.mqh",
    "MQL5\\Include\\Core\\MbRuntimeControl.mqh",
    "MQL5\\Include\\Core\\MbKillSwitchGuard.mqh",
    "MQL5\\Include\\Core\\MbRateGuard.mqh",
    "MQL5\\Include\\Core\\MbSessionGuard.mqh",
    "MQL5\\Include\\Core\\MbMarketState.mqh",
    "MQL5\\Include\\Core\\MbMarketGuards.mqh",
    "MQL5\\Include\\Core\\MbLatencyProfile.mqh",
    "MQL5\\Include\\Core\\MbBrokerProfilePlane.mqh",
    "MQL5\\Include\\Core\\MbExecutionSummaryPlane.mqh",
    "MQL5\\Include\\Core\\MbInformationalPolicyPlane.mqh",
    "MQL5\\Include\\Core\\MbExecutionCommon.mqh",
    "MQL5\\Include\\Core\\MbExecutionPrecheck.mqh",
    "MQL5\\Include\\Core\\MbExecutionSend.mqh",
    "MQL5\\Include\\Core\\MbExecutionFeedback.mqh",
    "MQL5\\Include\\Core\\MbDecisionJournal.mqh",
    "MQL5\\Include\\Core\\MbIncidentJournal.mqh",
    "MQL5\\Include\\Core\\MbTradeTransactionJournal.mqh",
    "MQL5\\Include\\Core\\MbClosedDealTracker.mqh",
    "MQL5\\Include\\Core\\MbLearningPolicy.mqh",
    "MQL5\\Include\\Core\\MbPaperTrading.mqh",
    "MQL5\\Include\\Strategies\\Common\\MbStrategyCommon.mqh",
    "TOOLS\\COMPILE_MICROBOT.ps1",
    "TOOLS\\COMPILE_ALL_MICROBOTS.ps1",
    "TOOLS\\REBUILD_GENERATED_MICROBOTS.ps1",
    "TOOLS\\PLAN_STRATEGY_PROPAGATION.ps1",
    "TOOLS\\PREPARE_SHARED_PROPAGATION_PACKAGE.ps1",
    "TOOLS\\VALIDATE_PROPAGATION_PACKAGE.ps1",
    "DOCS\\12_STRATEGY_PROPAGATION_MODEL.md",
    "DOCS\\16_PROPAGATION_WORKFLOW.md",
    "DOCS\\30_SHARED_PROPAGATION_PACKAGE.md"
)

$experimentalPrivatePaths = @(
    "MQL5\\Include\\Core\\MbContextPolicy.mqh",
    "MQL5\\Include\\Core\\MbLearningContext.mqh",
    "MQL5\\Include\\Core\\MbCandleAdvisory.mqh",
    "MQL5\\Include\\Core\\MbRenkoAdvisory.mqh",
    "MQL5\\Include\\Core\\MbAuxSignalFusion.mqh",
    "MQL5\\Include\\Strategies\\Strategy_EURUSD.mqh",
    "MQL5\\Experts\\MicroBots\\MicroBot_EURUSD.mq5",
    "MQL5\\Include\\Profiles\\Profile_EURUSD.mqh"
)

$missingShared = @()
$copiedPaths = @()

foreach ($relativePath in $sharedRelativePaths) {
    $sourcePath = Join-Path $ProjectRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        $missingShared += $relativePath
        continue
    }

    $destinationPath = Join-Path $payloadRoot $relativePath
    $destinationDir = Split-Path -Parent $destinationPath
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    $copiedPaths += $relativePath
}

$manifest = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    package_name = $PackageName
    package_root = $packageRoot
    payload_root = $payloadRoot
    scope = $Scope
    source_symbol = $plan.source_symbol
    source_family = $plan.source_family
    target_family = $plan.target_family
    target_symbols = @($plan.targets | ForEach-Object { $_.symbol })
    preserve_local = @($plan.local_gene_items)
    shared_payload_relative_paths = @($copiedPaths)
    missing_shared_paths = @($missingShared)
    experimental_private_paths_not_included = @($experimentalPrivatePaths)
    notes = @(
        "Pakiet zawiera tylko wspolne, bezpieczne do rozlania elementy.",
        "Pakiet nie zawiera strategii symbolowych, profili i eksperta EURUSD.",
        "Pakiet jest przygotowaniem do propagacji, a nie automatycznym nadpisaniem genotypu."
    )
}

$manifestJsonPath = Join-Path $packageRoot "manifest.json"
$manifestTxtPath = Join-Path $packageRoot "manifest.txt"

$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestJsonPath -Encoding UTF8

$lines = @()
$lines += "Pakiet wspolnej propagacji"
$lines += ("nazwa={0}" -f $PackageName)
$lines += ("source_symbol={0}" -f $plan.source_symbol)
$lines += ("source_family={0}" -f $plan.source_family)
$lines += ("target_family={0}" -f $plan.target_family)
$lines += ("targets={0}" -f (($plan.targets | ForEach-Object { $_.symbol }) -join ", "))
$lines += ""
$lines += "Zachowaj lokalne geny:"
$plan.local_gene_items | ForEach-Object { $lines += ("- {0}" -f $_) }
$lines += ""
$lines += "Dolaczone wspolne pliki:"
$copiedPaths | ForEach-Object { $lines += ("- {0}" -f $_) }
$lines += ""
$lines += "NIE dolaczono (warstwa prywatna EURUSD):"
$experimentalPrivatePaths | ForEach-Object { $lines += ("- {0}" -f $_) }
if ($missingShared.Count -gt 0) {
    $lines += ""
    $lines += "Brakujace wspolne pliki:"
    $missingShared | ForEach-Object { $lines += ("- {0}" -f $_) }
}
$lines | Set-Content -LiteralPath $manifestTxtPath -Encoding UTF8

$manifest | ConvertTo-Json -Depth 8
