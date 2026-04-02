param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TerminalDataRoot = "",
    [string]$CommonRoot = "",
    [switch]$FailOnIssues
)

$toolPath = Join-Path $ProjectRoot "TOOLS\BUILD_MT5_ACTIVE_SYMBOL_DEPLOYMENT_AUDIT.ps1"
if (-not (Test-Path -LiteralPath $toolPath)) {
    throw "Missing tool: $toolPath"
}

& $toolPath -ProjectRoot $ProjectRoot -TerminalDataRoot $TerminalDataRoot -CommonRoot $CommonRoot -FailOnIssues:$FailOnIssues
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
