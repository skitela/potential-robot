param(
    [string]$Url = "https://vps.cyberfolks.pl/"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Start-Process $Url
Write-Output ("VPS_PROVIDER_PORTAL_OPENED url={0}" -f $Url)
exit 0
