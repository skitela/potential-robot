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
        $safeArgs = @()
        if ($null -ne $Args) {
            foreach ($a in $Args) {
                if ($null -eq $a) { continue }
                $txt = [string]$a
                if ([string]::IsNullOrWhiteSpace($txt)) { continue }
                $safeArgs += $txt
            }
        }
        try {
            $allOut = (& $Exe @safeArgs 2>&1 | Out-String)
            $rc = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
            return @{
                rc = [int]$rc
                stdout = [string]$allOut
                stderr = ""
            }
        } catch {
            $argLine = ($safeArgs | ForEach-Object {
                if ([string]$_ -match "\s") { '"' + [string]$_ + '"' } else { [string]$_ }
            }) -join " "
            $cmdLine = [string]$Exe
            if (-not [string]::IsNullOrWhiteSpace($argLine)) {
                $cmdLine = $cmdLine + " " + $argLine
            }
            $allOut = (& cmd /c $cmdLine 2>&1 | Out-String)
            $rc = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
            return @{
                rc = [int]$rc
                stdout = [string]$allOut
                stderr = ""
            }
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
    if ($Text -match "([a-fA-F0-9\-]{36})") { return [string]$Matches[1] }
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
    if ($Text -match "(8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c)") {
        return [string]$Matches[1]
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

$listText = ""
$activeText = ""
try { $listText = (& powercfg /L 2>&1 | Out-String) } catch { $listText = "" }
try { $activeText = (& powercfg /GETACTIVESCHEME 2>&1 | Out-String) } catch { $activeText = "" }
$report.active_scheme_before = Parse-ActiveScheme -Text ([string]$activeText)
$report.high_performance_scheme = Find-HighPerformanceSchemeGuid -Text ([string]$listText)

$commands = @()
if (-not [string]::IsNullOrWhiteSpace($report.high_performance_scheme)) {
    $commands += [ordered]@{ exe = "powercfg"; args = @("/SETACTIVE", [string]$report.high_performance_scheme); id = "set_high_performance" }
}
$commands += [ordered]@{ exe = "powercfg"; args = @("/X", "-standby-timeout-ac", "0"); id = "disable_sleep_ac" }
$commands += [ordered]@{ exe = "powercfg"; args = @("/X", "-hibernate-timeout-ac", "0"); id = "disable_hibernate_ac" }

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
    $res = $null
    if ([string]$cmd.id -eq "disable_sleep_ac") {
        try {
            $o = (& powercfg /X -standby-timeout-ac 0 2>&1 | Out-String)
            $res = @{ rc = [int]$LASTEXITCODE; stdout = [string]$o; stderr = "" }
        } catch {
            $res = @{ rc = 125; stdout = ""; stderr = [string]$_.Exception.Message }
        }
    } elseif ([string]$cmd.id -eq "disable_hibernate_ac") {
        try {
            $o = (& powercfg /X -hibernate-timeout-ac 0 2>&1 | Out-String)
            $res = @{ rc = [int]$LASTEXITCODE; stdout = [string]$o; stderr = "" }
        } catch {
            $res = @{ rc = 125; stdout = ""; stderr = [string]$_.Exception.Message }
        }
    } else {
        $res = Run-Cmd -Exe ([string]$cmd.exe) -Args ([string[]]$cmd.args)
    }
    $ok = ([int]$res.rc -eq 0)
    $usedArgs = @($cmd.args)
    if (-not $ok -and [string]$cmd.id -eq "disable_sleep_ac") {
        $fallbackArgs = @("/CHANGE", "standby-timeout-ac", "0")
        $res2 = Run-Cmd -Exe ([string]$cmd.exe) -Args ([string[]]$fallbackArgs)
        if ([int]$res2.rc -eq 0) {
            $res = $res2
            $ok = $true
            $usedArgs = @($fallbackArgs)
        }
    } elseif (-not $ok -and [string]$cmd.id -eq "disable_hibernate_ac") {
        $fallbackArgs = @("/CHANGE", "hibernate-timeout-ac", "0")
        $res2 = Run-Cmd -Exe ([string]$cmd.exe) -Args ([string[]]$fallbackArgs)
        if ([int]$res2.rc -eq 0) {
            $res = $res2
            $ok = $true
            $usedArgs = @($fallbackArgs)
        }
    }
    if (-not $ok) { $report.status = "PARTIAL_FAIL" }
    $report.commands += [ordered]@{
        id = [string]$cmd.id
        exe = [string]$cmd.exe
        args = @($usedArgs)
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
