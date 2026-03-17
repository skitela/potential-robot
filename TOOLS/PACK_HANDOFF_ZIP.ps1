param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$OutDir = "C:\MAKRO_I_MIKRO_BOT\BACKUP"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$handoffRoot = Join-Path $projectPath "SERVER_PROFILE\HANDOFF"

if (-not (Test-Path -LiteralPath $handoffRoot)) {
    throw "Missing handoff root: $handoffRoot"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$zipPath = Join-Path $OutDir ("MAKRO_I_MIKRO_BOT_HANDOFF_{0}.zip" -f $stamp)

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

[System.IO.Compression.ZipFile]::CreateFromDirectory($handoffRoot,$zipPath,[System.IO.Compression.CompressionLevel]::Optimal,$false)

$result = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    handoff_root = $handoffRoot
    zip_path = $zipPath
    status = "OK"
}

$jsonPath = Join-Path $projectPath "EVIDENCE\handoff_zip_report.json"
$txtPath = Join-Path $projectPath "EVIDENCE\handoff_zip_report.txt"

$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $txtPath -Encoding ASCII
$result | ConvertTo-Json -Depth 5
