param(
    [string]$TerminalDataDir = "",
    [string]$Server = "OANDATMS-MT5",
    [string]$TerminalExe = "",
    [string]$OutDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-IniValue {
    param(
        [string[]]$Lines,
        [string]$Section,
        [string]$Key
    )
    $sec = "[$Section]"
    $inSection = $false
    foreach ($line in $Lines) {
        $t = $line.Trim()
        if ($t -match "^\[.*\]$") {
            $inSection = ($t -ieq $sec)
            continue
        }
        if (-not $inSection) { continue }
        if ($t -match ("^" + [regex]::Escape($Key) + "\s*=(.*)$")) {
            return $matches[1].Trim()
        }
    }
    return ""
}

function Find-TerminalDataDir {
    param([string]$ServerName, [string]$ExplicitDir)
    if (-not [string]::IsNullOrWhiteSpace($ExplicitDir)) {
        $p = Resolve-Path $ExplicitDir -ErrorAction Stop
        return $p.Path
    }

    $base = Join-Path $env:APPDATA "MetaQuotes\Terminal"
    if (-not (Test-Path $base)) {
        throw "MT5 data root not found: $base"
    }

    $best = $null
    $bestScore = -1
    foreach ($dir in Get-ChildItem $base -Directory -ErrorAction SilentlyContinue) {
        $ini = Join-Path $dir.FullName "config\common.ini"
        if (-not (Test-Path $ini)) { continue }
        $lines = Get-Content $ini -Encoding UTF8
        $srv = Get-IniValue -Lines $lines -Section "Common" -Key "Server"
        $score = 1
        if ($srv -ieq $ServerName) { $score += 1000 }
        try { $score += [int]((Get-Item $ini).LastWriteTimeUtc.ToFileTimeUtc() / 10000000) } catch {}
        if ($score -gt $bestScore) {
            $bestScore = $score
            $best = $dir.FullName
        }
    }
    if (-not $best) {
        throw "No MT5 data directory with common.ini found"
    }
    return $best
}

function Find-TerminalExe {
    $proc = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq "terminal64.exe" -and -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) } |
        Select-Object -First 1
    if ($proc -and (Test-Path $proc.ExecutablePath)) {
        return $proc.ExecutablePath
    }
    $candidates = @(
        "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
        "C:\Program Files\MetaTrader 5\terminal64.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return ""
}

function Invoke-Mt5Probe {
    param([string]$TerminalExePath)

    $tmpPy = Join-Path $env:TEMP ("mt5_probe_" + [guid]::NewGuid().ToString("N") + ".py")
    $tmpJson = Join-Path $env:TEMP ("mt5_probe_" + [guid]::NewGuid().ToString("N") + ".json")
    $py = @'
import argparse
import json
import traceback
import sys

def _tuple_to_list(v):
    try:
        if isinstance(v, tuple):
            return list(v)
    except Exception:
        pass
    return v

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--terminal", default="")
    args = ap.parse_args()

    out = {
        "ok": False,
        "mt5_import": False,
        "init_ok": False,
        "last_error": None,
        "error": None,
        "python_version": sys.version,
        "python_executable": sys.executable,
        "account": None,
        "terminal": None,
        "symbols": {}
    }
    symbols = [
        "EURUSD.pro","GBPUSD.pro","USDJPY.pro","USDCHF.pro","USDCAD.pro",
        "AUDUSD.pro","NZDUSD.pro","EURGBP.pro","GOLD.pro","SILVER.pro"
    ]
    try:
        import MetaTrader5 as mt5
        out["mt5_import"] = True
        if args.terminal:
            init_ok = mt5.initialize(args.terminal)
        else:
            init_ok = mt5.initialize()
        out["init_ok"] = bool(init_ok)
        out["last_error"] = _tuple_to_list(mt5.last_error())
        if not init_ok:
            out["error"] = "mt5.initialize=False"
        else:
            acc = mt5.account_info()
            if acc is not None:
                out["account"] = {
                    "login": getattr(acc, "login", None),
                    "server": getattr(acc, "server", None),
                    "trade_allowed": bool(getattr(acc, "trade_allowed", False)),
                    "trade_expert": bool(getattr(acc, "trade_expert", False)),
                    "margin_free": getattr(acc, "margin_free", None),
                    "balance": getattr(acc, "balance", None),
                }
            ti = mt5.terminal_info()
            if ti is not None:
                out["terminal"] = {
                    "connected": bool(getattr(ti, "connected", False)),
                    "trade_allowed": bool(getattr(ti, "trade_allowed", False)),
                    "tradeapi_disabled": bool(getattr(ti, "tradeapi_disabled", False)),
                    "community_connection": bool(getattr(ti, "community_connection", False)),
                    "name": getattr(ti, "name", None),
                    "company": getattr(ti, "company", None),
                }
            for sym in symbols:
                s = mt5.symbol_info(sym)
                if s is None:
                    out["symbols"][sym] = {"exists": False}
                else:
                    out["symbols"][sym] = {
                        "exists": True,
                        "trade_mode": getattr(s, "trade_mode", None),
                        "select": bool(getattr(s, "select", False)),
                        "visible": bool(getattr(s, "visible", False)),
                        "filling_mode": getattr(s, "filling_mode", None),
                    }
            out["ok"] = True
    except Exception as e:
        out["error"] = str(e)
        out["traceback"] = traceback.format_exc()
    finally:
        try:
            import MetaTrader5 as mt5
            mt5.shutdown()
        except Exception:
            pass
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    main()
'@

    Set-Content -Path $tmpPy -Value $py -Encoding UTF8

    $attempts = @(
        @{ cmd = "python"; pre = @() },
        @{ cmd = "py"; pre = @("-3.12") }
    )

    $lastErr = ""
    $attemptTrace = New-Object System.Collections.Generic.List[object]
    $lastProbe = $null
    foreach ($a in $attempts) {
        try {
            $args = @() + $a.pre + @($tmpPy, "--out", $tmpJson)
            if (-not [string]::IsNullOrWhiteSpace($TerminalExePath) -and (Test-Path $TerminalExePath)) {
                $args += @("--terminal", $TerminalExePath)
            }
            & $a.cmd @args | Out-Null
            $rc = $LASTEXITCODE
            if (Test-Path $tmpJson) {
                $raw = Get-Content $tmpJson -Raw -Encoding UTF8
                if (-not [string]::IsNullOrWhiteSpace($raw)) {
                    $probe = ($raw | ConvertFrom-Json)
                    $lastProbe = $probe
                    [void]$attemptTrace.Add([pscustomobject]@{
                        cmd = $a.cmd
                        args = ($a.pre -join " ")
                        rc = $rc
                        mt5_import = $probe.mt5_import
                        init_ok = $probe.init_ok
                        ok = $probe.ok
                        python_executable = $probe.python_executable
                    })
                    if ([bool]$probe.mt5_import -and [bool]$probe.ok) {
                        $probe | Add-Member -NotePropertyName probe_attempts -NotePropertyValue $attemptTrace -Force
                        return $probe
                    }
                }
            }
        } catch {
            $lastErr = $_.Exception.Message
            [void]$attemptTrace.Add([pscustomobject]@{
                cmd = $a.cmd
                args = ($a.pre -join " ")
                rc = -1
                mt5_import = $false
                init_ok = $false
                ok = $false
                python_executable = ""
                error = $lastErr
            })
        }
    }

    if ($lastProbe -ne $null) {
        $lastProbe | Add-Member -NotePropertyName probe_attempts -NotePropertyValue $attemptTrace -Force
        return $lastProbe
    }

    return [pscustomobject]@{
        ok = $false
        mt5_import = $false
        init_ok = $false
        error = "Python probe failed: $lastErr"
        account = $null
        terminal = $null
        symbols = @{}
        probe_attempts = $attemptTrace
    }
}

function Get-LogSummary {
    param([string]$DataDir)
    $mqlLogDir = Join-Path $DataDir "MQL5\Logs"
    $termLogDir = Join-Path $DataDir "logs"

    $latestMql = $null
    $latestTerm = $null
    if (Test-Path $mqlLogDir) {
        $latestMql = Get-ChildItem $mqlLogDir -Filter "*.log" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
    }
    if (Test-Path $termLogDir) {
        $latestTerm = Get-ChildItem $termLogDir -Filter "*.log" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
    }

    $patterns = @(
        "retcode=10017",
        "TRADE_RETCODE_TRADE_DISABLED",
        "ORDER_SEND_FAIL",
        "ORDER_SEND_RESULT",
        "automated trading is disabled"
    )

    $result = [ordered]@{
        latest_mql_log = if ($latestMql) { $latestMql.FullName } else { "" }
        latest_terminal_log = if ($latestTerm) { $latestTerm.FullName } else { "" }
        hits = [ordered]@{}
        samples = @()
    }
    foreach ($p in $patterns) { $result.hits[$p] = 0 }

    $sources = @()
    if ($latestMql) { $sources += $latestMql.FullName }
    if ($latestTerm) { $sources += $latestTerm.FullName }

    foreach ($src in $sources) {
        try {
            $lines = Get-Content $src -Tail 4000 -Encoding UTF8 -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                foreach ($p in $patterns) {
                    if ($line -match [regex]::Escape($p)) {
                        $result.hits[$p] = [int]$result.hits[$p] + 1
                        if ($result.samples.Count -lt 25) {
                            $result.samples += ("[" + [IO.Path]::GetFileName($src) + "] " + $line.Trim())
                        }
                    }
                }
            }
        } catch {}
    }

    return [pscustomobject]$result
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $repoRoot "RUN\DIAG_REPORTS"
}
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$reportJson = Join-Path $OutDir ("MT5_FULL_DIAG_" + $ts + ".json")
$reportTxt = Join-Path $OutDir ("MT5_FULL_DIAG_" + $ts + ".txt")

$dataDir = Find-TerminalDataDir -ServerName $Server -ExplicitDir $TerminalDataDir
$commonIni = Join-Path $dataDir "config\common.ini"
$commonLines = Get-Content $commonIni -Encoding UTF8

$experts = [ordered]@{
    Enabled = (Get-IniValue -Lines $commonLines -Section "Experts" -Key "Enabled")
    AllowDllImport = (Get-IniValue -Lines $commonLines -Section "Experts" -Key "AllowDllImport")
    Account = (Get-IniValue -Lines $commonLines -Section "Experts" -Key "Account")
    Profile = (Get-IniValue -Lines $commonLines -Section "Experts" -Key "Profile")
    Chart = (Get-IniValue -Lines $commonLines -Section "Experts" -Key "Chart")
    Api = (Get-IniValue -Lines $commonLines -Section "Experts" -Key "Api")
}

$terminalExeUse = $TerminalExe
if ([string]::IsNullOrWhiteSpace($terminalExeUse)) {
    $terminalExeUse = Find-TerminalExe
}

$probe = Invoke-Mt5Probe -TerminalExePath $terminalExeUse
$logs = Get-LogSummary -DataDir $dataDir

$localSettingsOk = (
    $experts.Enabled -eq "1" -and
    $experts.AllowDllImport -eq "1" -and
    $experts.Account -eq "0" -and
    $experts.Profile -eq "0" -and
    $experts.Chart -eq "0" -and
    $experts.Api -eq "0"
)

$accAllowed = $true
$accExpert = $true
$termAllowed = $true
$termConnected = $true

if ($probe.account -ne $null) {
    $accAllowed = [bool]$probe.account.trade_allowed
    $accExpert = [bool]$probe.account.trade_expert
}
if ($probe.terminal -ne $null) {
    $termAllowed = [bool]$probe.terminal.trade_allowed
    $termConnected = [bool]$probe.terminal.connected
}

$verdict = "PASS"
$nextSteps = New-Object System.Collections.Generic.List[string]
if (-not $probe.ok -or -not $probe.mt5_import -or -not $probe.init_ok) {
    $verdict = "FAIL_MT5_API_ATTACH"
    [void]$nextSteps.Add("Sprawdz Python 3.12 + pakiet MetaTrader5 i czy terminal MT5 jest uruchomiony.")
}
if (-not $localSettingsOk) {
    if ($verdict -eq "PASS") { $verdict = "FAIL_TERMINAL_SETTINGS" }
    [void]$nextSteps.Add("Uruchom FIX_MT5_AUTOTRADE.bat i ponow test.")
}
if (-not $termConnected) {
    if ($verdict -eq "PASS") { $verdict = "FAIL_MT5_NOT_CONNECTED" }
    [void]$nextSteps.Add("Zaloguj konto handlowe do serwera LIVE i potwierdz stabilne polaczenie w prawym dolnym rogu MT5.")
}
if ((-not $accAllowed) -or (-not $accExpert) -or (-not $termAllowed)) {
    if ($verdict -eq "PASS") { $verdict = "FAIL_TRADE_DISABLED" }
    [void]$nextSteps.Add("Konto/serwer blokuje trading. Sprawdz login haslem glownym (nie inwestorskim) i skontaktuj OANDA TMS ws. flagi trade_allowed.")
}
if (($verdict -eq "PASS") -and ([int]$logs.hits["retcode=10017"] -gt 0 -or [int]$logs.hits["TRADE_RETCODE_TRADE_DISABLED"] -gt 0)) {
    $verdict = "WARN_RECENT_TRADE_DISABLED_IN_LOGS"
    [void]$nextSteps.Add("W logach sa ostatnie odrzucenia 10017. Jesli to stare wpisy, wyczysc/odswiez i testuj ponownie po odblokowaniu konta.")
}
if ($nextSteps.Count -eq 0) {
    [void]$nextSteps.Add("Brak krytycznych blokad wykrytych w tym przebiegu.")
}

$summary = [ordered]@{
    schema_version = 1
    ts_utc = $utc
    repo_root = $repoRoot
    terminal_data_dir = $dataDir
    terminal_exe = $terminalExeUse
    common_ini = $commonIni
    experts_settings = $experts
    local_settings_ok = $localSettingsOk
    mt5_probe = $probe
    log_summary = $logs
    verdict = $verdict
    next_steps = $nextSteps
}

$summary | ConvertTo-Json -Depth 12 | Set-Content -Path $reportJson -Encoding UTF8

$txt = New-Object System.Collections.Generic.List[string]
[void]$txt.Add("===== MT5 FULL DIAGNOSTIC =====")
[void]$txt.Add("ts_utc: $utc")
[void]$txt.Add("repo_root: $repoRoot")
[void]$txt.Add("terminal_data_dir: $dataDir")
[void]$txt.Add("terminal_exe: $terminalExeUse")
[void]$txt.Add("")
[void]$txt.Add("[Experts settings]")
[void]$txt.Add("Enabled=$($experts.Enabled) AllowDllImport=$($experts.AllowDllImport) Account=$($experts.Account) Profile=$($experts.Profile) Chart=$($experts.Chart) Api=$($experts.Api)")
[void]$txt.Add("local_settings_ok=$localSettingsOk")
[void]$txt.Add("")
[void]$txt.Add("[MT5 probe]")
[void]$txt.Add("ok=$($probe.ok) mt5_import=$($probe.mt5_import) init_ok=$($probe.init_ok)")
if ($probe.account -ne $null) {
    [void]$txt.Add("account login=$($probe.account.login) server=$($probe.account.server) trade_allowed=$($probe.account.trade_allowed) trade_expert=$($probe.account.trade_expert)")
}
if ($probe.terminal -ne $null) {
    [void]$txt.Add("terminal connected=$($probe.terminal.connected) trade_allowed=$($probe.terminal.trade_allowed) tradeapi_disabled=$($probe.terminal.tradeapi_disabled)")
}
if ($probe.error) {
    [void]$txt.Add("probe_error=$($probe.error)")
}
[void]$txt.Add("")
[void]$txt.Add("[Log summary]")
[void]$txt.Add("latest_mql_log=$($logs.latest_mql_log)")
[void]$txt.Add("latest_terminal_log=$($logs.latest_terminal_log)")
foreach ($k in $logs.hits.Keys) {
    [void]$txt.Add("$k=$($logs.hits[$k])")
}
[void]$txt.Add("samples:")
foreach ($s in $logs.samples) { [void]$txt.Add(" - $s") }
[void]$txt.Add("")
[void]$txt.Add("[Verdict]")
[void]$txt.Add("verdict=$verdict")
[void]$txt.Add("next_steps:")
foreach ($n in $nextSteps) { [void]$txt.Add(" - $n") }

$txt | Set-Content -Path $reportTxt -Encoding UTF8

Write-Output "MT5_FULL_DIAG_DONE"
Write-Output "report_json=$reportJson"
Write-Output "report_txt=$reportTxt"
Write-Output "verdict=$verdict"

if ($verdict -like "FAIL*") {
    exit 2
}
exit 0
