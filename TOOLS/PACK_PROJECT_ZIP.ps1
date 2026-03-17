param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$OutDir = "C:\MAKRO_I_MIKRO_BOT\BACKUP"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Copy-ProjectTreeSafe {
    param(
        [string]$SourceRoot,
        [string]$StageRoot
    )

    $copied = 0
    $skipped = New-Object System.Collections.Generic.List[string]
    $rootItem = Get-Item -LiteralPath $SourceRoot
    $allItems = Get-ChildItem -LiteralPath $SourceRoot -Force -Recurse

    foreach ($item in $allItems) {
        $relative = $item.FullName.Substring($rootItem.FullName.Length).TrimStart('\')
        if ($relative -eq "BACKUP" -or $relative.StartsWith("BACKUP\")) {
            continue
        }
        $targetPath = Join-Path $StageRoot $relative

        if ($item.PSIsContainer) {
            New-Item -ItemType Directory -Force -Path $targetPath | Out-Null
            continue
        }

        $targetDir = Split-Path -Path $targetPath -Parent
        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        }

        try {
            Copy-Item -LiteralPath $item.FullName -Destination $targetPath -Force -ErrorAction Stop
            $copied++
        }
        catch {
            $skipped.Add($item.FullName)
        }
    }

    return [pscustomobject]@{
        copied_count = $copied
        skipped_files = $skipped
    }
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$zipPath = Join-Path $OutDir ("MAKRO_I_MIKRO_BOT_{0}.zip" -f $stamp)
$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("MAKRO_I_MIKRO_BOT_STAGE_{0}" -f $stamp)

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null

$copyResult = Copy-ProjectTreeSafe -SourceRoot $projectPath -StageRoot $stageRoot
[System.IO.Compression.ZipFile]::CreateFromDirectory($stageRoot,$zipPath,[System.IO.Compression.CompressionLevel]::Optimal,$false)
Remove-Item -LiteralPath $stageRoot -Recurse -Force

$status = if ($copyResult.skipped_files.Count -eq 0) { "OK" } else { "OK_WITH_SKIPPED_FILES" }

$result = [ordered]@{
    schema_version = "1.1"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $projectPath
    zip_path = $zipPath
    status = $status
    copied_count = $copyResult.copied_count
    skipped_count = $copyResult.skipped_files.Count
    skipped_files = @($copyResult.skipped_files)
}

$result | ConvertTo-Json -Depth 6
