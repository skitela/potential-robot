param(
    [string]$InstallerDir = "C:\Installers",
    [switch]$ForceReinstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-VcRedistInstalled {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"
    )
    foreach ($path in $paths) {
        try {
            $item = Get-ItemProperty -Path $path -ErrorAction Stop
            if (($item.Installed -as [int]) -eq 1) {
                return $true
            }
        } catch {
        }
    }
    return $false
}

$url = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
$installerDirResolved = [System.IO.Path]::GetFullPath($InstallerDir)
$installerPath = Join-Path $installerDirResolved "vc_redist.x64.exe"

New-Item -ItemType Directory -Force $installerDirResolved | Out-Null

if ((-not $ForceReinstall) -and (Test-VcRedistInstalled)) {
    Write-Host "MT5_PREREQS_OK status=already_installed path=$installerPath"
    exit 0
}

Write-Host "MT5_PREREQS_DOWNLOAD url=$url out=$installerPath"
Invoke-WebRequest -Uri $url -OutFile $installerPath

Write-Host "MT5_PREREQS_INSTALL start"
$proc = Start-Process -FilePath $installerPath -ArgumentList "/install","/quiet","/norestart" -PassThru -Wait
if ($proc.ExitCode -ne 0) {
    throw "vc_redist install failed exit_code=$($proc.ExitCode)"
}

if (-not (Test-VcRedistInstalled)) {
    throw "vc_redist install completed but registry marker is missing"
}

Write-Host "MT5_PREREQS_OK status=installed path=$installerPath"
