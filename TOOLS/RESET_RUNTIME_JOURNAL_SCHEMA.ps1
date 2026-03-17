param(
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [Parameter(Mandatory = $true)]
    [string]$LogName,
    [string[]]$Symbols = @(),
    [string[]]$RelativeDirectories = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $CommonRoot)) {
    throw "CommonRoot not found: $CommonRoot"
}

if ($Symbols.Count -eq 0 -and $RelativeDirectories.Count -eq 0) {
    throw "Provide at least one symbol or one relative directory."
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$moved = @()
$missing = @()
$targetDirs = @()

foreach ($symbol in $Symbols) {
    $targetDirs += Join-Path $CommonRoot ("logs\" + $symbol)
}

foreach ($relativeDir in $RelativeDirectories) {
    $targetDirs += Join-Path $CommonRoot $relativeDir
}

foreach ($logDir in $targetDirs) {
    $filePath = Join-Path $logDir $LogName
    if (-not (Test-Path -LiteralPath $filePath)) {
        $missing += $filePath
        continue
    }

    $archiveDir = Join-Path $logDir ("archive\schema_reset_" + $stamp)
    New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
    $targetPath = Join-Path $archiveDir $LogName
    Move-Item -LiteralPath $filePath -Destination $targetPath -Force
    $moved += $targetPath
}

[pscustomobject]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    common_root = $CommonRoot
    log_name = $LogName
    target_directory_count = $targetDirs.Count
    moved_count = $moved.Count
    missing_count = $missing.Count
    moved = $moved
    missing = $missing
} | ConvertTo-Json -Depth 5
