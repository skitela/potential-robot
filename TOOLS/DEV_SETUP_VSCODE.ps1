param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [switch]$InstallExtensions
)

$ErrorActionPreference = "Stop"

function Write-Section([string]$Name) {
    Write-Host ""
    Write-Host "=== $Name ===" -ForegroundColor Cyan
}

function Get-VersionSafe([scriptblock]$Block) {
    try {
        & $Block
    }
    catch {
        "MISSING"
    }
}

Write-Section "ENV AUDIT"
Write-Host "Root: $Root"
Write-Host ("git: " + (Get-VersionSafe { git --version }))
Write-Host ("winget: " + (Get-VersionSafe { winget --version }))
Write-Host ("powershell: " + $PSVersionTable.PSVersion.ToString())
Write-Host ("python: " + (Get-VersionSafe { python --version }))
Write-Host ("py launcher: " + (Get-VersionSafe { py --version }))
Write-Host ("code cli: " + (Get-VersionSafe { code --version | Select-Object -First 1 }))

$extensions = @(
    "ms-python.python",
    "ms-python.vscode-pylance",
    "ms-vscode.powershell",
    "charliermarsh.ruff",
    "eamodio.gitlens",
    "EditorConfig.EditorConfig",
    "usernamehw.errorlens",
    "redhat.vscode-yaml",
    "DavidAnson.vscode-markdownlint"
)

Write-Section "RECOMMENDED EXTENSIONS"
$extensions | ForEach-Object { Write-Host "- $_" }

if ($InstallExtensions) {
    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        throw "VS Code CLI ('code') not found in PATH. Install CLI first."
    }
    Write-Section "INSTALL EXTENSIONS"
    foreach ($ext in $extensions) {
        Write-Host "Installing $ext ..."
        code --install-extension $ext --force | Out-Null
    }
    Write-Host "Extensions install finished."
}
else {
    Write-Section "DRY RUN"
    Write-Host "Run with -InstallExtensions to install recommended VS Code extensions."
}

Write-Section "DONE"
Write-Host "No strategy/runtime trading logic changed by this script."
