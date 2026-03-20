param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"
[System.Windows.Forms.Application]::EnableVisualStyles()

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

$runtimeSummaryPath = Join-Path $ProjectRoot "EVIDENCE\runtime_control_summary.json"
$dailyJsonPath = Join-Path $ProjectRoot "EVIDENCE\DAILY\raport_dzienny_latest.json"
$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$watchdogPath = Join-Path $ProjectRoot "EVIDENCE\runtime_watchdog_status.json"
$mt5ProfilePath = Join-Path $ProjectRoot "EVIDENCE\mt5_microbots_profile_setup_report.json"
$mt5InstallPath = Join-Path $ProjectRoot "EVIDENCE\validate_mt5_server_install_report.json"

function Invoke-ToolScript {
    param([string]$RelativePath, [string[]]$Arguments = @())
    $scriptPath = Join-Path $ProjectRoot $RelativePath
    $argText = @("-ExecutionPolicy","Bypass","-File",$scriptPath) + $Arguments
    Start-Process -FilePath "powershell.exe" -ArgumentList $argText -WindowStyle Hidden -Wait
}

function Read-JsonOrNull {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json } catch { return $null }
}

function Refresh-Reports {
    Invoke-ToolScript -RelativePath "TOOLS\GENERATE_DAILY_SYSTEM_REPORTS.ps1"
    Invoke-ToolScript -RelativePath "TOOLS\GENERATE_EVENING_OWNER_REPORT.ps1"
}

$registry = Read-JsonOrNull $registryPath
$symbols = @()
if ($registry) {
    $symbols = @($registry.symbols | ForEach-Object { Get-RegistryDisplaySymbol -RegistryItem $_ -PreferBroker } | Select-Object -Unique)
}
$families = @("FX_MAIN","FX_ASIA","FX_CROSS","METALS_SPOT_PM","METALS_FUTURES","INDEX_EU","INDEX_US")

$form = New-Object System.Windows.Forms.Form
$form.Text = "Panel operatora Makro i Mikro Bot"
$form.Size = New-Object System.Drawing.Size(980,640)
$form.MinimumSize = New-Object System.Drawing.Size(900,560)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(244,239,231)
$form.Font = New-Object System.Drawing.Font("Segoe UI",10)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Panel operatora Makro i Mikro Bot"
$title.Font = New-Object System.Drawing.Font("Segoe UI",20,[System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(24,20)
$form.Controls.Add($title)

$statusBadge = New-Object System.Windows.Forms.Label
$statusBadge.Text = "LADOWANIE..."
$statusBadge.TextAlign = "MiddleCenter"
$statusBadge.Font = New-Object System.Drawing.Font("Segoe UI",16,[System.Drawing.FontStyle]::Bold)
$statusBadge.Size = New-Object System.Drawing.Size(260,90)
$statusBadge.Location = New-Object System.Drawing.Point(680,18)
$statusBadge.BorderStyle = "FixedSingle"
$form.Controls.Add($statusBadge)

$repairBadge = New-Object System.Windows.Forms.Label
$repairBadge.Text = "SAMONAPRAWA: LADOWANIE..."
$repairBadge.TextAlign = "MiddleCenter"
$repairBadge.Font = New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Bold)
$repairBadge.Size = New-Object System.Drawing.Size(260,36)
$repairBadge.Location = New-Object System.Drawing.Point(680,112)
$repairBadge.BorderStyle = "FixedSingle"
$form.Controls.Add($repairBadge)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = "Polskie sterowanie systemem, rodzinami i parami bez obciazania hot-path botow."
$sub.AutoSize = $true
$sub.ForeColor = [System.Drawing.Color]::FromArgb(90,80,70)
$sub.Location = New-Object System.Drawing.Point(27,62)
$form.Controls.Add($sub)

$systemBox = New-Object System.Windows.Forms.GroupBox
$systemBox.Text = "Sterowanie calym systemem"
$systemBox.Size = New-Object System.Drawing.Size(300,214)
$systemBox.Location = New-Object System.Drawing.Point(24,120)
$form.Controls.Add($systemBox)

$btnNormal = New-Object System.Windows.Forms.Button
$btnNormal.Text = "Wlacz system"
$btnNormal.Size = New-Object System.Drawing.Size(240,34)
$btnNormal.Location = New-Object System.Drawing.Point(28,34)
$systemBox.Controls.Add($btnNormal)

$btnCloseOnly = New-Object System.Windows.Forms.Button
$btnCloseOnly.Text = "Close-only"
$btnCloseOnly.Size = New-Object System.Drawing.Size(240,34)
$btnCloseOnly.Location = New-Object System.Drawing.Point(28,76)
$systemBox.Controls.Add($btnCloseOnly)

$btnHalt = New-Object System.Windows.Forms.Button
$btnHalt.Text = "Zatrzymaj system"
$btnHalt.Size = New-Object System.Drawing.Size(240,34)
$btnHalt.Location = New-Object System.Drawing.Point(28,118)
$systemBox.Controls.Add($btnHalt)

$btnRepairNow = New-Object System.Windows.Forms.Button
$btnRepairNow.Text = "Sprawdz i napraw teraz"
$btnRepairNow.Size = New-Object System.Drawing.Size(240,34)
$btnRepairNow.Location = New-Object System.Drawing.Point(28,160)
$systemBox.Controls.Add($btnRepairNow)

$familyBox = New-Object System.Windows.Forms.GroupBox
$familyBox.Text = "Sterowanie rodzina"
$familyBox.Size = New-Object System.Drawing.Size(300,220)
$familyBox.Location = New-Object System.Drawing.Point(340,120)
$form.Controls.Add($familyBox)

$familyLabel = New-Object System.Windows.Forms.Label
$familyLabel.Text = "Rodzina:"
$familyLabel.AutoSize = $true
$familyLabel.Location = New-Object System.Drawing.Point(24,34)
$familyBox.Controls.Add($familyLabel)

$familyCombo = New-Object System.Windows.Forms.ComboBox
$familyCombo.DropDownStyle = "DropDownList"
$familyCombo.Size = New-Object System.Drawing.Size(240,30)
$familyCombo.Location = New-Object System.Drawing.Point(24,58)
[void]$familyCombo.Items.AddRange($families)
$familyCombo.SelectedIndex = 0
$familyBox.Controls.Add($familyCombo)

$btnFamilyNormal = New-Object System.Windows.Forms.Button
$btnFamilyNormal.Text = "Wlacz rodzine"
$btnFamilyNormal.Size = New-Object System.Drawing.Size(240,34)
$btnFamilyNormal.Location = New-Object System.Drawing.Point(24,102)
$familyBox.Controls.Add($btnFamilyNormal)

$btnFamilyClose = New-Object System.Windows.Forms.Button
$btnFamilyClose.Text = "Rodzina close-only"
$btnFamilyClose.Size = New-Object System.Drawing.Size(240,34)
$btnFamilyClose.Location = New-Object System.Drawing.Point(24,144)
$familyBox.Controls.Add($btnFamilyClose)

$btnFamilyHalt = New-Object System.Windows.Forms.Button
$btnFamilyHalt.Text = "Zatrzymaj rodzine"
$btnFamilyHalt.Size = New-Object System.Drawing.Size(240,34)
$btnFamilyHalt.Location = New-Object System.Drawing.Point(24,186)
$familyBox.Controls.Add($btnFamilyHalt)

$pairBox = New-Object System.Windows.Forms.GroupBox
$pairBox.Text = "Sterowanie pojedynczym instrumentem"
$pairBox.Size = New-Object System.Drawing.Size(300,220)
$pairBox.Location = New-Object System.Drawing.Point(656,120)
$form.Controls.Add($pairBox)

$pairLabel = New-Object System.Windows.Forms.Label
$pairLabel.Text = "Instrument:"
$pairLabel.AutoSize = $true
$pairLabel.Location = New-Object System.Drawing.Point(24,34)
$pairBox.Controls.Add($pairLabel)

$pairCombo = New-Object System.Windows.Forms.ComboBox
$pairCombo.DropDownStyle = "DropDownList"
$pairCombo.Size = New-Object System.Drawing.Size(240,30)
$pairCombo.Location = New-Object System.Drawing.Point(24,58)
[void]$pairCombo.Items.AddRange($symbols)
if ($pairCombo.Items.Count -gt 0) { $pairCombo.SelectedIndex = 0 }
$pairBox.Controls.Add($pairCombo)

$btnPairNormal = New-Object System.Windows.Forms.Button
$btnPairNormal.Text = "Wlacz pare"
$btnPairNormal.Size = New-Object System.Drawing.Size(240,34)
$btnPairNormal.Location = New-Object System.Drawing.Point(24,102)
$pairBox.Controls.Add($btnPairNormal)

$btnPairClose = New-Object System.Windows.Forms.Button
$btnPairClose.Text = "Para close-only"
$btnPairClose.Size = New-Object System.Drawing.Size(240,34)
$btnPairClose.Location = New-Object System.Drawing.Point(24,144)
$pairBox.Controls.Add($btnPairClose)

$btnPairHalt = New-Object System.Windows.Forms.Button
$btnPairHalt.Text = "Zatrzymaj pare"
$btnPairHalt.Size = New-Object System.Drawing.Size(240,34)
$btnPairHalt.Location = New-Object System.Drawing.Point(24,186)
$pairBox.Controls.Add($btnPairHalt)

$infoBox = New-Object System.Windows.Forms.GroupBox
$infoBox.Text = "Informacje"
$infoBox.Size = New-Object System.Drawing.Size(932,220)
$infoBox.Location = New-Object System.Drawing.Point(24,356)
$form.Controls.Add($infoBox)

$summaryLabel = New-Object System.Windows.Forms.Label
$summaryLabel.Text = "Ladowanie informacji..."
$summaryLabel.Size = New-Object System.Drawing.Size(880,68)
$summaryLabel.Location = New-Object System.Drawing.Point(24,32)
$summaryLabel.Font = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
$infoBox.Controls.Add($summaryLabel)

$detailsBox = New-Object System.Windows.Forms.TextBox
$detailsBox.Multiline = $true
$detailsBox.ReadOnly = $true
$detailsBox.ScrollBars = "Vertical"
$detailsBox.Size = New-Object System.Drawing.Size(880,98)
$detailsBox.Location = New-Object System.Drawing.Point(24,98)
$detailsBox.BackColor = [System.Drawing.Color]::White
$infoBox.Controls.Add($detailsBox)

$btnOpenDashboard = New-Object System.Windows.Forms.Button
$btnOpenDashboard.Text = "Otworz dashboard dzienny"
$btnOpenDashboard.Size = New-Object System.Drawing.Size(220,32)
$btnOpenDashboard.Location = New-Object System.Drawing.Point(24,586)
$form.Controls.Add($btnOpenDashboard)

$btnOpenEvening = New-Object System.Windows.Forms.Button
$btnOpenEvening.Text = "Otworz raport wieczorny"
$btnOpenEvening.Size = New-Object System.Drawing.Size(220,32)
$btnOpenEvening.Location = New-Object System.Drawing.Point(258,586)
$form.Controls.Add($btnOpenEvening)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Odswiez panel"
$btnRefresh.Size = New-Object System.Drawing.Size(160,32)
$btnRefresh.Location = New-Object System.Drawing.Point(492,586)
$form.Controls.Add($btnRefresh)

$btnOpenMt5 = New-Object System.Windows.Forms.Button
$btnOpenMt5.Text = "Uruchom OANDA MT5"
$btnOpenMt5.Size = New-Object System.Drawing.Size(220,32)
$btnOpenMt5.Location = New-Object System.Drawing.Point(666,586)
$form.Controls.Add($btnOpenMt5)

function Refresh-Panel {
    $summary = Read-JsonOrNull $runtimeSummaryPath
    $daily = Read-JsonOrNull $dailyJsonPath
    $watchdog = Read-JsonOrNull $watchdogPath
    $mt5Profile = Read-JsonOrNull $mt5ProfilePath
    $mt5Install = Read-JsonOrNull $mt5InstallPath
    $mt5Process = Get-Process terminal64 -ErrorAction SilentlyContinue | Select-Object -First 1

    $rows = @()
    if ($summary) { $rows = @($summary.kontrola) }

    $dailyRows = @()
    $dailySummary = $null
    if ($daily) {
        if ($daily.PSObject.Properties.Name -contains "instrumenty") { $dailyRows = @($daily.instrumenty) }
        if ($daily.PSObject.Properties.Name -contains "raport_dzienny") { $dailySummary = $daily.raport_dzienny }
    }

    if ($dailySummary) {
        switch ([string]$dailySummary.stan_systemu) {
            "DZIALA" {
                $statusBadge.Text = "DZIALA"
                $statusBadge.BackColor = [System.Drawing.Color]::FromArgb(35,140,74)
                $statusBadge.ForeColor = [System.Drawing.Color]::White
            }
            "UWAGA" {
                $statusBadge.Text = "UWAGA"
                $statusBadge.BackColor = [System.Drawing.Color]::FromArgb(201,128,18)
                $statusBadge.ForeColor = [System.Drawing.Color]::White
            }
            default {
                $statusBadge.Text = "PADL"
                $statusBadge.BackColor = [System.Drawing.Color]::FromArgb(183,32,32)
                $statusBadge.ForeColor = [System.Drawing.Color]::White
            }
        }
    } else {
        $statusBadge.Text = "BRAK RAPORTU"
        $statusBadge.BackColor = [System.Drawing.Color]::FromArgb(97,97,97)
        $statusBadge.ForeColor = [System.Drawing.Color]::White
    }

    if ($watchdog) {
        $wdStatus = [string]$watchdog.status
        switch ($wdStatus) {
            "ZDROWY" {
                $repairBadge.Text = "SAMONAPRAWA: GOTOWA"
                $repairBadge.BackColor = [System.Drawing.Color]::FromArgb(35,140,74)
                $repairBadge.ForeColor = [System.Drawing.Color]::White
            }
            "NAPRAWIONY" {
                $repairBadge.Text = "SAMONAPRAWA: NAPRAWIONO"
                $repairBadge.BackColor = [System.Drawing.Color]::FromArgb(39,89,136)
                $repairBadge.ForeColor = [System.Drawing.Color]::White
            }
            "OSTRZEZENIE" {
                $repairBadge.Text = "SAMONAPRAWA: OSTRZEZENIE"
                $repairBadge.BackColor = [System.Drawing.Color]::FromArgb(201,128,18)
                $repairBadge.ForeColor = [System.Drawing.Color]::White
            }
            default {
                $repairBadge.Text = "SAMONAPRAWA: WYMAGA NAPRAWY"
                $repairBadge.BackColor = [System.Drawing.Color]::FromArgb(183,32,32)
                $repairBadge.ForeColor = [System.Drawing.Color]::White
            }
        }
    } else {
        $repairBadge.Text = "SAMONAPRAWA: BRAK DANYCH"
        $repairBadge.BackColor = [System.Drawing.Color]::FromArgb(97,97,97)
        $repairBadge.ForeColor = [System.Drawing.Color]::White
    }

    if ($dailySummary) {
        $watchdogText = ""
        if ($watchdog) { $watchdogText = " | Samonaprawa: $($watchdog.status)" }
        $summaryLabel.Text = "Status: $($dailySummary.stan_systemu) | Netto dzis: $($dailySummary.netto_dzis) | Zmiana do wczoraj: $($dailySummary.zmiana_netto_do_wczoraj) | Wygrane / przegrane: $($dailySummary.wygrane_dzis) / $($dailySummary.przegrane_dzis) | Ping sr: $($dailySummary.sredni_ping_ms) ms | Latencja bota sr: $($dailySummary.srednia_latencja_bota_us) us$watchdogText"
    } else {
        $summaryLabel.Text = "Brak aktualnego raportu dziennego."
    }

    $lines = @()
    foreach ($row in ($dailyRows | Sort-Object swiezosc_s -Descending | Select-Object -First 8)) {
        $lines += ("{0} | {1} | praca={2} | swiezosc={3} | netto={4} | zmiana={5} | W/P={6}/{7} | ping={8} ms | lat={9}/{10} us" -f
            $row.instrument,
            $row.status_pracy,
            $row.czas_pracy_dzis_label,
            $row.swiezosc_label,
            $row.netto_dzis,
            $row.zmiana_do_wczoraj,
            $row.wygrane_dzis,
            $row.przegrane_dzis,
            $row.ping_ms,
            $row.latencja_sr_us,
            $row.latencja_max_us)
    }
    if ($lines.Count -eq 0) {
        $lines += "Brak swiezych danych dziennych."
    }
    if ($rows.Count -gt 0) {
        $lines += ""
        $lines += "TRYBY OPERATORSKIE"
        foreach ($row in ($rows | Select-Object -First 6)) {
            $lines += ("{0} | {1} | {2} | {3}" -f $row.para_walutowa, $row.rodzina, $row.requested_mode, $row.reason_code)
        }
    }
    if ($watchdog) {
        $lines += ""
        $lines += ("WATCHDOG | status={0} | repair_needed={1} | action={2} | cooldown_left={3}s" -f
            $watchdog.status, [int]$watchdog.repair_needed, $watchdog.repair_action, $watchdog.cooldown_left_sec)
        if (@($watchdog.stale_symbols).Count -gt 0) {
            $lines += ("Stale heartbeat: " + (@($watchdog.stale_symbols) -join ", "))
        }
        if (@($watchdog.missing_symbols).Count -gt 0) {
            $lines += ("Brak stanu: " + (@($watchdog.missing_symbols) -join ", "))
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$watchdog.repair_error)) {
            $lines += ("Blad naprawy: " + [string]$watchdog.repair_error)
        }
    }
    $lines += ""
    $mt5Status = if ($mt5Process) { "URUCHOMIONY" } else { "NIEAKTYWNY" }
    $lines += ("MT5 | status={0}" -f $mt5Status)
    if ($mt5Install) {
        $lines += ("MT5 | instalacja_ok={0}" -f [bool]$mt5Install.ok)
    }
    if ($mt5Profile) {
        $charts = 0
        if ($mt5Profile.PSObject.Properties.Name -contains "charts") {
            $charts = @($mt5Profile.charts).Count
        }
        $lines += ("MT5 | profil={0} | wykresy={1} | launched={2}" -f $mt5Profile.profile_name, $charts, $mt5Profile.launched)
    }
    if ($mt5Process) {
        $lines += ("MT5 | start lokalny={0}" -f (Get-Date $mt5Process.StartTime -Format "yyyy-MM-dd HH:mm:ss"))
    }
    $detailsBox.Text = ($lines -join [Environment]::NewLine)
}

$btnNormal.Add_Click({
    Invoke-ToolScript -RelativePath "RUN\WLACZ_TRYB_NORMALNY_SYSTEMU.ps1"
    Invoke-ToolScript -RelativePath "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1"
    Refresh-Reports
    Refresh-Panel
})
$btnCloseOnly.Add_Click({
    Invoke-ToolScript -RelativePath "RUN\WLACZ_CLOSE_ONLY_SYSTEMU.ps1"
    Invoke-ToolScript -RelativePath "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1"
    Refresh-Reports
    Refresh-Panel
})
$btnHalt.Add_Click({
    Invoke-ToolScript -RelativePath "RUN\ZATRZYMAJ_SYSTEM.ps1"
    Invoke-ToolScript -RelativePath "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1"
    Refresh-Reports
    Refresh-Panel
})
$btnRepairNow.Add_Click({
    Invoke-ToolScript -RelativePath "RUN\SPRAWDZ_I_NAPRAW_SYSTEM.ps1"
    Invoke-ToolScript -RelativePath "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1"
    Refresh-Reports
    Refresh-Panel
})

$btnFamilyNormal.Add_Click({
    if ($familyCombo.SelectedItem) {
        Invoke-ToolScript -RelativePath "TOOLS\SET_RUNTIME_CONTROL_PL.ps1" -Arguments @("-Zakres","rodzina","-WartoscZakresu",$familyCombo.SelectedItem.ToString(),"-Tryb","NORMALNY","-Powod","WLACZONO_RODZINE")
        Invoke-ToolScript -RelativePath "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1"
        Refresh-Reports
        Refresh-Panel
    }
})
$btnFamilyClose.Add_Click({
    if ($familyCombo.SelectedItem) {
        Invoke-ToolScript -RelativePath "TOOLS\SET_RUNTIME_CONTROL_PL.ps1" -Arguments @("-Zakres","rodzina","-WartoscZakresu",$familyCombo.SelectedItem.ToString(),"-Tryb","CLOSE_ONLY","-Powod","RODZINA_CLOSE_ONLY")
        Invoke-ToolScript -RelativePath "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1"
        Refresh-Reports
        Refresh-Panel
    }
})
$btnFamilyHalt.Add_Click({
    if ($familyCombo.SelectedItem) {
        Invoke-ToolScript -RelativePath "TOOLS\SET_RUNTIME_CONTROL_PL.ps1" -Arguments @("-Zakres","rodzina","-WartoscZakresu",$familyCombo.SelectedItem.ToString(),"-Tryb","HALT","-Powod","RODZINA_ZATRZYMANA")
        Invoke-ToolScript -RelativePath "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1"
        Refresh-Reports
        Refresh-Panel
    }
})

$btnPairNormal.Add_Click({
    if ($pairCombo.SelectedItem) {
        Invoke-ToolScript -RelativePath "TOOLS\SET_RUNTIME_CONTROL_PL.ps1" -Arguments @("-Zakres","para","-WartoscZakresu",$pairCombo.SelectedItem.ToString(),"-Tryb","NORMALNY","-Powod","WLACZONO_PARE")
        Invoke-ToolScript -RelativePath "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1"
        Refresh-Reports
        Refresh-Panel
    }
})
$btnPairClose.Add_Click({
    if ($pairCombo.SelectedItem) {
        Invoke-ToolScript -RelativePath "TOOLS\SET_RUNTIME_CONTROL_PL.ps1" -Arguments @("-Zakres","para","-WartoscZakresu",$pairCombo.SelectedItem.ToString(),"-Tryb","CLOSE_ONLY","-Powod","PARA_CLOSE_ONLY")
        Invoke-ToolScript -RelativePath "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1"
        Refresh-Reports
        Refresh-Panel
    }
})
$btnPairHalt.Add_Click({
    if ($pairCombo.SelectedItem) {
        Invoke-ToolScript -RelativePath "TOOLS\SET_RUNTIME_CONTROL_PL.ps1" -Arguments @("-Zakres","para","-WartoscZakresu",$pairCombo.SelectedItem.ToString(),"-Tryb","HALT","-Powod","PARA_ZATRZYMANA")
        Invoke-ToolScript -RelativePath "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1"
        Refresh-Reports
        Refresh-Panel
    }
})

$btnOpenDashboard.Add_Click({
    Refresh-Reports
    Start-Process (Join-Path $ProjectRoot "EVIDENCE\DAILY\dashboard_dzienny_latest.html")
})
$btnOpenEvening.Add_Click({
    Refresh-Reports
    Start-Process (Join-Path $ProjectRoot "EVIDENCE\DAILY\dashboard_wieczorny_latest.html")
})
$btnOpenMt5.Add_Click({
    Invoke-ToolScript -RelativePath "RUN\OPEN_OANDA_MT5_WITH_MICROBOTS.ps1"
    Start-Sleep -Seconds 2
    Refresh-Panel
})
$btnRefresh.Add_Click({
    Refresh-Reports
    Refresh-Panel
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 10000
$timer.Add_Tick({ Refresh-Panel })
$timer.Start()

Refresh-Panel
[void]$form.ShowDialog()
