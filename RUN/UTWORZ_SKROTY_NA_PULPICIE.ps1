param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$desktop = [Environment]::GetFolderPath("Desktop")
if ([string]::IsNullOrWhiteSpace($desktop)) {
    throw "Nie mozna odnalezc pulpitu Windows."
}

$iconsDir = Join-Path $ProjectRoot "ASSETS\desktop_icons"
New-Item -ItemType Directory -Force -Path $iconsDir | Out-Null

$wsh = New-Object -ComObject WScript.Shell

function Save-BitmapAsIcon {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [string]$IcoPath
    )

    $pngStream = New-Object System.IO.MemoryStream
    $Bitmap.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngBytes = $pngStream.ToArray()
    $pngStream.Dispose()

    $fileStream = [System.IO.File]::Open($IcoPath, [System.IO.FileMode]::Create)
    $writer = New-Object System.IO.BinaryWriter($fileStream)
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]1)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]32)
    $writer.Write([UInt32]$pngBytes.Length)
    $writer.Write([UInt32]22)
    $writer.Write($pngBytes)
    $writer.Dispose()
    $fileStream.Dispose()
}

function New-ShortcutIcon {
    param(
        [string]$MainText,
        [string]$SubText,
        [string]$FooterText,
        [string]$Mode,
        [string]$BaseName
    )

    $pngPath = Join-Path $iconsDir ($BaseName + ".png")
    $icoPath = Join-Path $iconsDir ($BaseName + ".ico")

    $size = 256
    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $graphics.Clear([System.Drawing.Color]::Transparent)

    if ($Mode -eq "START") {
        $colorA = [System.Drawing.Color]::FromArgb(255, 11, 94, 58)
        $colorB = [System.Drawing.Color]::FromArgb(255, 67, 160, 71)
        $accent = [System.Drawing.Color]::FromArgb(255, 200, 255, 212)
        $symbolBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 232, 255, 237))
    } elseif ($Mode -eq "CLOSE_ONLY") {
        $colorA = [System.Drawing.Color]::FromArgb(255, 168, 94, 0)
        $colorB = [System.Drawing.Color]::FromArgb(255, 245, 171, 53)
        $accent = [System.Drawing.Color]::FromArgb(255, 255, 236, 179)
        $symbolBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(238, 255, 248, 225))
    } else {
        $colorA = [System.Drawing.Color]::FromArgb(255, 135, 22, 22)
        $colorB = [System.Drawing.Color]::FromArgb(255, 211, 47, 47)
        $accent = [System.Drawing.Color]::FromArgb(255, 255, 205, 210)
        $symbolBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 255, 235, 238))
    }

    $rect = New-Object System.Drawing.Rectangle(8, 8, 240, 240)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $radius = 36
    $path.AddArc($rect.X, $rect.Y, $radius, $radius, 180, 90)
    $path.AddArc($rect.Right - $radius, $rect.Y, $radius, $radius, 270, 90)
    $path.AddArc($rect.Right - $radius, $rect.Bottom - $radius, $radius, $radius, 0, 90)
    $path.AddArc($rect.X, $rect.Bottom - $radius, $radius, $radius, 90, 90)
    $path.CloseFigure()

    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $colorA, $colorB, 90)
    $graphics.FillPath($brush, $path)
    $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(160,255,255,255), 4)
    $graphics.DrawPath($borderPen, $path)

    $accentPen = New-Object System.Drawing.Pen($accent, 10)
    $graphics.DrawLine($accentPen, 36, 36, 220, 36)

    if ($Mode -eq "START") {
        $triangle = @(
            (New-Object System.Drawing.Point(42, 82)),
            (New-Object System.Drawing.Point(42, 138)),
            (New-Object System.Drawing.Point(92, 110))
        )
        $graphics.FillPolygon($symbolBrush, $triangle)
    } elseif ($Mode -eq "CLOSE_ONLY") {
        $graphics.FillRectangle($symbolBrush, 40, 82, 16, 54)
        $graphics.FillRectangle($symbolBrush, 66, 82, 16, 54)
    } else {
        $graphics.FillRectangle($symbolBrush, 40, 84, 48, 48)
    }

    $mainFont = New-Object System.Drawing.Font("Segoe UI", 34, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $subFont = New-Object System.Drawing.Font("Segoe UI", 28, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $footFont = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $textBrush = [System.Drawing.Brushes]::White
    $mutedBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 247, 247, 247))

    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center

    $graphics.DrawString($MainText, $mainFont, $textBrush, (New-Object System.Drawing.RectangleF(96, 62, 132, 46)), $format)
    $graphics.DrawString($SubText, $subFont, $textBrush, (New-Object System.Drawing.RectangleF(24, 128, 208, 44)), $format)
    $graphics.DrawString($FooterText, $footFont, $mutedBrush, (New-Object System.Drawing.RectangleF(24, 183, 208, 28)), $format)

    $bitmap.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Save-BitmapAsIcon -Bitmap $bitmap -IcoPath $icoPath

    $mainFont.Dispose()
    $subFont.Dispose()
    $footFont.Dispose()
    $mutedBrush.Dispose()
    $format.Dispose()
    $symbolBrush.Dispose()
    $accentPen.Dispose()
    $borderPen.Dispose()
    $brush.Dispose()
    $path.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()

    return [pscustomobject]@{
        png = $pngPath
        ico = $icoPath
    }
}

function New-DesktopShortcut {
    param(
        [string]$Name,
        [string]$TargetPath,
        [string]$Arguments = "",
        [string]$WorkingDirectory = $ProjectRoot,
        [string]$Description = "",
        [string]$IconLocation = "$env:SystemRoot\System32\shell32.dll,220"
    )

    $shortcutPath = Join-Path $desktop ($Name + ".lnk")
    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        $shortcut.Arguments = $Arguments
    }
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = $Description
    $shortcut.IconLocation = $IconLocation
    $shortcut.Save()

    return $shortcutPath
}

$startIcon = New-ShortcutIcon -MainText "START" -SubText "SYSTEM" -FooterText "PAPER" -Mode "START" -BaseName "start_system_paper"
$closeOnlyIcon = New-ShortcutIcon -MainText "CLOSE" -SubText "ONLY" -FooterText "PAPER" -Mode "CLOSE_ONLY" -BaseName "close_only_system_paper"
$stopIcon = New-ShortcutIcon -MainText "STOP" -SubText "SYSTEM" -FooterText "PAPER" -Mode "STOP" -BaseName "stop_system_paper"

$items = @(
    @{
        Name = "Makro Mikro - START SYSTEM PAPER"
        TargetPath = "powershell.exe"
        Arguments = "-ExecutionPolicy Bypass -File `"$ProjectRoot\RUN\URUCHOM_AKCJE_SYSTEMOWA_Z_OKNEM.ps1`" -Akcja START"
        Description = "Wlacza normalna prace systemu w paper i pokazuje okno potwierdzenia."
        IconLocation = $startIcon.ico
    },
    @{
        Name = "Makro Mikro - CLOSE ONLY SYSTEM PAPER"
        TargetPath = "powershell.exe"
        Arguments = "-ExecutionPolicy Bypass -File `"$ProjectRoot\RUN\URUCHOM_AKCJE_SYSTEMOWA_Z_OKNEM.ps1`" -Akcja CLOSE_ONLY"
        Description = "Wlacza tryb close-only dla calego systemu paper i pokazuje okno potwierdzenia."
        IconLocation = $closeOnlyIcon.ico
    },
    @{
        Name = "Makro Mikro - STOP SYSTEM PAPER"
        TargetPath = "powershell.exe"
        Arguments = "-ExecutionPolicy Bypass -File `"$ProjectRoot\RUN\URUCHOM_AKCJE_SYSTEMOWA_Z_OKNEM.ps1`" -Akcja STOP"
        Description = "Zatrzymuje caly system paper i pokazuje okno potwierdzenia."
        IconLocation = $stopIcon.ico
    },
    @{
        Name = "Makro Mikro - MT5 Panel i Dashboard"
        TargetPath = "cmd.exe"
        Arguments = "/c `"$ProjectRoot\RUN\START_MT5_PANEL_I_DASHBOARD.bat`""
        Description = "Uruchamia OANDA MT5, panel operatora i dashboardy."
    },
    @{
        Name = "Makro Mikro - Panel Operatora"
        TargetPath = "cmd.exe"
        Arguments = "/c `"$ProjectRoot\RUN\START_TYLKO_PANEL.bat`""
        Description = "Otwiera panel operatora."
    },
    @{
        Name = "Makro Mikro - Dashboard Dzienny"
        TargetPath = "cmd.exe"
        Arguments = "/c `"$ProjectRoot\RUN\START_DASHBOARD_DZIENNY.bat`""
        Description = "Otwiera dzienny dashboard HTML."
    },
    @{
        Name = "Makro Mikro - Raport Wieczorny"
        TargetPath = "cmd.exe"
        Arguments = "/c `"$ProjectRoot\RUN\START_RAPORT_WIECZORNY.bat`""
        Description = "Otwiera wieczorny dashboard HTML."
    },
    @{
        Name = "Makro Mikro - Tylko Dashboardy"
        TargetPath = "cmd.exe"
        Arguments = "/c `"$ProjectRoot\RUN\START_TYLKO_DASHBOARDY.bat`""
        Description = "Otwiera oba dashboardy."
    },
    @{
        Name = "Makro Mikro - OANDA MT5"
        TargetPath = "powershell.exe"
        Arguments = "-ExecutionPolicy Bypass -File `"$ProjectRoot\RUN\OPEN_OANDA_MT5_WITH_MICROBOTS.ps1`""
        Description = "Uruchamia OANDA MT5 z profilem mikro-botow."
    }
)

$created = @()
foreach ($item in $items) {
    $created += New-DesktopShortcut @item
}

$report = [ordered]@{
    schema_version = "2.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    desktop = $desktop
    icons_dir = $iconsDir
    icons = @(
        [ordered]@{ name = "start_system_paper"; png = $startIcon.png; ico = $startIcon.ico }
        [ordered]@{ name = "close_only_system_paper"; png = $closeOnlyIcon.png; ico = $closeOnlyIcon.ico }
        [ordered]@{ name = "stop_system_paper"; png = $stopIcon.png; ico = $stopIcon.ico }
    )
    created = $created
}

$jsonPath = Join-Path $ProjectRoot "EVIDENCE\desktop_shortcuts_report.json"
$txtPath = Join-Path $ProjectRoot "EVIDENCE\desktop_shortcuts_report.txt"
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $txtPath -Encoding UTF8
$report | ConvertTo-Json -Depth 6
