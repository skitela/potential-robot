param(
    [string]$VaultName = "MicroBotVault",
    [string]$SecretName = "QDM-LicenseCode",
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module Microsoft.PowerShell.SecretManagement

$code = Get-Secret -Vault $VaultName -Name $SecretName -AsPlainText
if ([string]::IsNullOrWhiteSpace($code)) {
    throw "Nie znaleziono kodu licencji QDM w vault '$VaultName' pod nazwa '$SecretName'."
}

$licenseScript = Join-Path $ProjectRoot "RUN\QDM_LICENSE.ps1"
if (-not (Test-Path -LiteralPath $licenseScript)) {
    throw "License helper script not found: $licenseScript"
}

& $licenseScript -Action update -Code $code
