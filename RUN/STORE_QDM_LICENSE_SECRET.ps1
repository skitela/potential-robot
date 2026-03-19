param(
    [string]$Code = "",
    [string]$VaultName = "MicroBotVault",
    [string]$SecretName = "QDM-LicenseCode"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module Microsoft.PowerShell.SecretManagement

if ([string]::IsNullOrWhiteSpace($Code)) {
    $Code = Read-Host "Podaj kod licencji QDM"
}

$Code = $Code.Trim()
if ([string]::IsNullOrWhiteSpace($Code)) {
    throw "Kod licencji jest pusty."
}

Set-Secret -Vault $VaultName -Name $SecretName -Secret $Code
Write-Host "Kod licencji QDM zostal zapisany w vault '$VaultName' jako '$SecretName'."
