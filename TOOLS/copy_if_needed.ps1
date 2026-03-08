param(
    [Parameter(Mandatory = $true)]
    [string]$Source,
    [Parameter(Mandatory = $true)]
    [string]$Destination
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
}

if (-not (Test-Path -LiteralPath $Source)) {
    Write-Output "ERROR:missing-source"
    exit 1
}

$dstDir = Split-Path -Parent $Destination
if (-not [string]::IsNullOrWhiteSpace($dstDir) -and -not (Test-Path -LiteralPath $dstDir)) {
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
}

if (Test-Path -LiteralPath $Destination) {
    try {
        if ((Get-Sha256 -Path $Source) -eq (Get-Sha256 -Path $Destination)) {
            Write-Output "UNCHANGED"
            exit 0
        }
    } catch {
        # Fall through to copy attempt.
    }
}

try {
    Copy-Item -Force -LiteralPath $Source -Destination $Destination -ErrorAction Stop
    Write-Output "COPIED"
    exit 0
} catch {
    if (Test-Path -LiteralPath $Destination) {
        try {
            if ((Get-Sha256 -Path $Source) -eq (Get-Sha256 -Path $Destination)) {
                Write-Output "LOCKED_MATCH"
                exit 0
            }
        } catch {
            # Keep the original copy failure below.
        }
    }

    Write-Output ("ERROR:" + $_.Exception.Message)
    exit 1
}
