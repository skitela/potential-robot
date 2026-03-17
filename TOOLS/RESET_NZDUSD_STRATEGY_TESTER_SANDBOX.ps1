param(
    [string]$CommonFilesRoot = (Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files"),
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& (Join-Path $ProjectRoot "TOOLS\RESET_MICROBOT_STRATEGY_TESTER_SANDBOX.ps1") `
    -CommonFilesRoot $CommonFilesRoot `
    -ProjectRoot $ProjectRoot `
    -SymbolAlias "NZDUSD" `
    -SandboxTag "NZDUSD_AGENT"
