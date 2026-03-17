param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$BackupZip = "C:\MAKRO_I_MIKRO_BOT\BACKUP\MAKRO_I_MIKRO_BOT_20260312_101302.zip"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$tmp = Join-Path $ProjectRoot "_restore_tmp_101302"
if (Test-Path -LiteralPath $tmp) {
    Remove-Item -LiteralPath $tmp -Recurse -Force
}

Expand-Archive -LiteralPath $BackupZip -DestinationPath $tmp -Force

Copy-Item -LiteralPath (Join-Path $tmp "MQL5\Include\Profiles") -Destination (Join-Path $ProjectRoot "MQL5\Include") -Recurse -Force
Copy-Item -LiteralPath (Join-Path $tmp "MQL5\Include\Strategies") -Destination (Join-Path $ProjectRoot "MQL5\Include") -Recurse -Force
Copy-Item -LiteralPath (Join-Path $tmp "MQL5\Presets") -Destination (Join-Path $ProjectRoot "MQL5") -Recurse -Force

Write-Output "restored"
