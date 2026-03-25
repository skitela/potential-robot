param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$desktop = [Environment]::GetFolderPath("Desktop")
if ([string]::IsNullOrWhiteSpace($desktop)) {
    throw "Nie mozna odnalezc pulpitu Windows."
}

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
$reportPath = Join-Path $opsRoot "desktop_open_close_shortcuts_latest.json"
$reportMdPath = Join-Path $opsRoot "desktop_open_close_shortcuts_latest.md"
New-Item -ItemType Directory -Force -Path $opsRoot | Out-Null

$wsh = New-Object -ComObject WScript.Shell

$legacyPatterns = @(
    "Makro Mikro - *.lnk",
    "MicroBot - *.lnk",
    "FX LAB - *.lnk",
    "QDM - *.lnk",
    "VPS OANDA PANEL.lnk"
)

$newNames = @(
    "OTWORZ SYSTEM.lnk",
    "ZAMKNIJ SYSTEM.lnk"
)

$removed = New-Object System.Collections.Generic.List[string]
foreach ($pattern in $legacyPatterns) {
    $matches = @(
        Get-ChildItem -LiteralPath $desktop -File -Filter $pattern -ErrorAction SilentlyContinue |
            Where-Object { $newNames -notcontains $_.Name }
    )

    foreach ($item in $matches) {
        Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
        $removed.Add($item.FullName) | Out-Null
    }
}

function New-DesktopShortcut {
    param(
        [string]$Name,
        [string]$ScriptPath,
        [string]$Description,
        [string]$IconLocation
    )

    $shortcutPath = Join-Path $desktop $Name
    if (Test-Path -LiteralPath $shortcutPath) {
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
    }

    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $shortcut.WorkingDirectory = $ProjectRoot
    $shortcut.Description = $Description
    $shortcut.IconLocation = $IconLocation
    $shortcut.Save()

    return $shortcutPath
}

$openScript = Join-Path $ProjectRoot "RUN\OTWORZ_PELNY_SYSTEM.ps1"
$closeScript = Join-Path $ProjectRoot "RUN\ZAMKNIJ_PELNY_SYSTEM.ps1"

foreach ($path in @($openScript, $closeScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

$created = @(
    New-DesktopShortcut -Name "OTWORZ SYSTEM.lnk" -ScriptPath $openScript -Description "Uruchamia caly system Makro i Mikro Bot wraz z MT5 i supervisorami." -IconLocation "$env:SystemRoot\System32\shell32.dll,220"
    New-DesktopShortcut -Name "ZAMKNIJ SYSTEM.lnk" -ScriptPath $closeScript -Description "Zatrzymuje caly system Makro i Mikro Bot w bezpiecznej kolejnosci." -IconLocation "$env:SystemRoot\System32\shell32.dll,131"
)

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    desktop = $desktop
    removed_legacy_shortcuts = $removed.ToArray()
    created_shortcuts = $created
}

$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Desktop Open Close Shortcuts")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add("")
$lines.Add("## Usuniete skroty")
$lines.Add("")
foreach ($item in $removed) {
    $lines.Add(("- {0}" -f $item))
}
$lines.Add("")
$lines.Add("## Utworzone skroty")
$lines.Add("")
foreach ($item in $created) {
    $lines.Add(("- {0}" -f $item))
}
$lines -join [Environment]::NewLine | Set-Content -LiteralPath $reportMdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 6
