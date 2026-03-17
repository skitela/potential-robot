[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Message,
    [string]$TagName = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = "C:\MAKRO_I_MIKRO_BOT"

git -C $repo add -A

$porcelain = git -C $repo status --porcelain
if([string]::IsNullOrWhiteSpace(($porcelain | Out-String))) {
    Write-Output "Brak zmian do zapisania."
    exit 0
}

git -C $repo commit -m $Message

if(-not [string]::IsNullOrWhiteSpace($TagName)) {
    git -C $repo tag -a $TagName -m $TagName
}

git -C $repo log -1 --stat
