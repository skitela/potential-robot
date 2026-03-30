param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [switch]$AllowBlockedAuditGate
)

& (Join-Path $ProjectRoot "TOOLS\VALIDATE_PRELIVE_GONOGO.ps1") `
    -ProjectRoot $ProjectRoot `
    -AllowBlockedAuditGate:$AllowBlockedAuditGate