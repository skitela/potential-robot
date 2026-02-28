param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [switch]$Apply,
    [string]$EvidencePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RootPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    }
    return (Resolve-Path $Path).Path
}

function Run-Cmd {
    param([string]$Exe, [string[]]$Args)
    try {
        $p = Start-Process -FilePath $Exe -ArgumentList $Args -NoNewWindow -PassThru -Wait -RedirectStandardOutput "$env:TEMP\low_jitter_out.txt" -RedirectStandardError "$env:TEMP\low_jitter_err.txt"
        $out = ""
        $err = ""
        if (Test-Path "$env:TEMP\low_jitter_out.txt") { $out = Get-Content "$env:TEMP\low_jitter_out.txt" -Raw -ErrorAction SilentlyContinue }
        if (Test-Path "$env:TEMP\low_jitter_err.txt") { $err = Get-Content "$env:TEMP\low_jitter_err.txt" -Raw -ErrorAction SilentlyContinue }
        return @{
            rc = [int]$p.ExitCode
            stdout = [string]$out
            stderr = [string]$err
        }
    } catch {
        return @{
            rc = 125
            stdout = ""
            stderr = [string]$_.Exception.Message
        }
    }
}

function Parse-ActiveScheme {
    param([string]$Text)
    if ($Text -match "GUID schematu zasilania:\s*([a-fA-F0-9\-]{36})") { return [string]$Matches[1] }
    if ($Text -match "Power Scheme GUID:\s*([a-fA-F0-9\-]{36})") { return [string]$Matches[1] }
    return ""
}

function Find-HighPerformanceSchemeGuid {
    param([string]$Text)
    $lines = @($Text -split "`r?`n")
    foreach ($line in $lines) {
        if ($line -match "([a-fA-F0-9\-]{36}).*(High performance|Wysoka wydajność)") {
            return [string]$Matches[1]
        }
    }
    return ""
}

$runtimeRoot = Resolve-RootPath -Path $Root
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
if ([string]::IsNullOrWhiteSpace($EvidencePath)) {
    $EvidencePath = Join-Path $runtimeRoot ("EVIDENCE\runtime_stability\low_jitter_power_" + $stamp + ".json")
}

$report = [ordered]@{
    schema = "oanda_mt5.low_jitter_power.v1"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    root = $runtimeRoot
    apply = [bool]$Apply
    status = "PASS"
    active_scheme_before = ""
    high_performance_scheme = ""
    commands = @()
    manual_steps_required = @()
}

$listRes = Run-Cmd -Exe "powercfg" -Args @("/L")
$activeRes = Run-Cmd -Exe "powercfg" -Args @("/GETACTIVESCHEME")
$report.active_scheme_before = Parse-ActiveScheme -Text ([string]$activeRes.stdout + "`n" + [string]$activeRes.stderr)
$report.high_performance_scheme = Find-HighPerformanceSchemeGuid -Text ([string]$listRes.stdout + "`n" + [string]$listRes.stderr)

$commands = @()
if (-not [string]::IsNullOrWhiteSpace($report.high_performance_scheme)) {
    $commands += [ordered]@{ exe = "powercfg"; args = @("/SETACTIVE", [string]$report.high_performance_scheme); id = "set_high_performance" }
}
$commands += [ordered]@{ exe = "powercfg"; args = @("/CHANGE", "standby-timeout-ac", "0"); id = "disable_sleep_ac" }
$commands += [ordered]@{ exe = "powercfg"; args = @("/CHANGE", "hibernate-timeout-ac", "0"); id = "disable_hibernate_ac" }

foreach ($cmd in $commands) {
    if (-not $Apply) {
        $report.commands += [ordered]@{
            id = [string]$cmd.id
            exe = [string]$cmd.exe
            args = @($cmd.args)
            rc = "DRY_RUN"
            ok = $true
            stdout_tail = ""
            stderr_tail = ""
        }
        continue
    }
    $res = Run-Cmd -Exe ([string]$cmd.exe) -Args ([string[]]$cmd.args)
    $ok = ([int]$res.rc -eq 0)
    if (-not $ok) { $report.status = "PARTIAL_FAIL" }
    $report.commands += [ordered]@{
        id = [string]$cmd.id
        exe = [string]$cmd.exe
        args = @($cmd.args)
        rc = [int]$res.rc
        ok = [bool]$ok
        stdout_tail = [string]($res.stdout | Out-String | Select-Object -First 1)
        stderr_tail = [string]($res.stderr | Out-String | Select-Object -First 1)
    }
}

$report.manual_steps_required += "USB selective suspend (AC): ustaw na Disabled w Advanced Power Settings."
$report.manual_steps_required += "Karta sieciowa: Device Manager -> NIC -> Power Management -> odznacz 'Allow the computer to turn off this device...'."
$report.manual_steps_required += "Windows Update/AV scan: zaplanuj poza oknami handlowymi."

$evParent = Split-Path -Parent $EvidencePath
if (-not (Test-Path $evParent)) { New-Item -ItemType Directory -Path $evParent -Force | Out-Null }
($report | ConvertTo-Json -Depth 8) | Set-Content -Path $EvidencePath -Encoding UTF8

Write-Output ("LOW_JITTER_POWER_DONE status={0} apply={1} out={2}" -f $report.status, [bool]$Apply, $EvidencePath)
exit 0
