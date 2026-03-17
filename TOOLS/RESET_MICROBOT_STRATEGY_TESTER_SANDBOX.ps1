param(
    [string]$CommonFilesRoot = (Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files"),
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [Parameter(Mandatory = $true)]
    [string]$SymbolAlias,
    [string]$SandboxTag = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToSandboxToken {
    param([string]$Value)
    $chars = $Value.ToCharArray() | ForEach-Object {
        if (($_ -ge 'A' -and $_ -le 'Z') -or ($_ -ge 'a' -and $_ -le 'z') -or ($_ -ge '0' -and $_ -le '9') -or $_ -eq '_' -or $_ -eq '-') {
            [string]$_
        } else {
            "_"
        }
    }
    $out = -join $chars
    if ([string]::IsNullOrWhiteSpace($out)) {
        return "DEFAULT"
    }
    return $out
}

$sanitizedAlias = Convert-ToSandboxToken $SymbolAlias
if ([string]::IsNullOrWhiteSpace($SandboxTag)) {
    $SandboxTag = "${sanitizedAlias}_AGENT"
}
$sanitizedTag = Convert-ToSandboxToken $SandboxTag
$sandboxName = "MAKRO_I_MIKRO_BOT_TESTER_${sanitizedAlias}_${sanitizedTag}"
$sandboxPath = Join-Path $CommonFilesRoot $sandboxName
$removed = $false

if (Test-Path -LiteralPath $sandboxPath) {
    Remove-Item -LiteralPath $sandboxPath -Recurse -Force
    $removed = $true
}

$report = [ordered]@{
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    symbol_alias     = $sanitizedAlias
    sandbox_tag      = $sanitizedTag
    sandbox_name     = $sandboxName
    sandbox_path     = $sandboxPath
    removed          = $removed
    exists_after     = (Test-Path -LiteralPath $sandboxPath)
}

$evidenceDir = Join-Path $ProjectRoot "EVIDENCE"
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$reportPath = Join-Path $evidenceDir ("reset_strategy_tester_sandbox_{0}.json" -f $sanitizedAlias.ToLowerInvariant())
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8

$report
