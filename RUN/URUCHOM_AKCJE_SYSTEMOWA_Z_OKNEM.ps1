param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [ValidateSet("START","CLOSE_ONLY","STOP")]
    [string]$Akcja = "START"
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Invoke-Tool {
    param([string]$RelativePath)
    $scriptPath = Join-Path $ProjectRoot $RelativePath
    & powershell.exe -ExecutionPolicy Bypass -File $scriptPath | Out-Null
}

function Show-Info {
    param(
        [string]$Title,
        [string]$Message,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
}

try {
    switch ($Akcja) {
        "START" {
            Invoke-Tool -RelativePath "RUN\WLACZ_TRYB_NORMALNY_SYSTEMU.ps1"
            $naglowek = "System uruchomiony"
            $opisAkcji = "Wlaczono normalna prace systemu w paper."
        }
        "CLOSE_ONLY" {
            Invoke-Tool -RelativePath "RUN\WLACZ_CLOSE_ONLY_SYSTEMU.ps1"
            $naglowek = "Tryb close-only wlaczony"
            $opisAkcji = "Nowe wejscia zostaly zablokowane. System zostaje w paper i moze tylko domykac logike wyjsc."
        }
        "STOP" {
            Invoke-Tool -RelativePath "RUN\ZATRZYMAJ_SYSTEM.ps1"
            $naglowek = "System zatrzymany"
            $opisAkcji = "Wlaczono HALT dla calego systemu paper."
        }
    }

    Invoke-Tool -RelativePath "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1"
    Invoke-Tool -RelativePath "TOOLS\GENERATE_DAILY_SYSTEM_REPORTS.ps1"
    Invoke-Tool -RelativePath "TOOLS\GENERATE_EVENING_OWNER_REPORT.ps1"

    $dailyPath = Join-Path $ProjectRoot "EVIDENCE\DAILY\raport_dzienny_latest.json"
    $daily = if (Test-Path -LiteralPath $dailyPath) { Get-Content -Raw -LiteralPath $dailyPath | ConvertFrom-Json } else { $null }

    if ($daily -and $daily.raport_dzienny) {
        $r = $daily.raport_dzienny
        $message = @"
$opisAkcji

Stan systemu: $($r.stan_systemu)
Swieze instrumenty: $($r.liczba_swiezych) / $($r.liczba_instrumentow)
Netto dzis: $($r.netto_dzis)
Zmiana do wczoraj: $($r.zmiana_netto_do_wczoraj)
Wygrane / przegrane: $($r.wygrane_dzis) / $($r.przegrane_dzis)
Otwarcia dzis: $($r.otwarcia_dzis)
Sredni ping: $($r.sredni_ping_ms) ms
Srednia latencja bota: $($r.srednia_latencja_bota_us) us
"@
    } else {
        $message = $opisAkcji
    }

    Show-Info -Title $naglowek -Message $message
}
catch {
    Show-Info -Title "Blad akcji operatorskiej" -Message $_.Exception.Message -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}
