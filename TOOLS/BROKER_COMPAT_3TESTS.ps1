param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$Mt5Path = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [string]$PyExe = "py",
    [string]$Py312Ver = "-3.12",
    [string]$Py314Ver = "-3.14"
)

$ErrorActionPreference = "Stop"

function _Run-Cmd {
    param(
        [string]$Exe,
        [string[]]$ArgList,
        [string]$Workdir,
        [string]$OutPath,
        [string]$ErrPath
    )
    function _Quote-Arg([string]$s) {
        if ($null -eq $s) { return '""' }
        if ($s -notmatch '[\s"]') { return $s }
        $escaped = $s -replace '(\\*)"', '$1$1\"'
        $escaped = $escaped -replace '(\\+)$', '$1$1'
        return '"' + $escaped + '"'
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Exe
    $psi.WorkingDirectory = $Workdir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Arguments = (($ArgList | ForEach-Object { _Quote-Arg ([string]$_) }) -join ' ')

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    Set-Content -Path $OutPath -Value $stdout -Encoding UTF8
    Set-Content -Path $ErrPath -Value $stderr -Encoding UTF8
    return @{
        rc = [int]$proc.ExitCode
        out = $OutPath
        err = $ErrPath
        exe = $Exe
        args = $ArgList
    }
}

if (-not (Test-Path $Root)) {
    Write-Host "BROKER_COMPAT_3TESTS_FAIL root_missing=$Root"
    exit 2
}

$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$evDir = Join-Path $Root ("EVIDENCE\broker_compat_3tests\" + $runId)
New-Item -ItemType Directory -Path $evDir -Force | Out-Null

$summary = @{
    schema = "oanda_mt5.broker_compat_3tests.v1"
    ts_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    root = $Root
    mt5_path = $Mt5Path
    tests = @{}
}

# ---------------------------------------------------------------------------
# TEST 1: Python runtime matrix vs broker attach/import (3.12 vs 3.14)
# ---------------------------------------------------------------------------
$t1 = @{
    name = "python_runtime_matrix_vs_broker"
    versions = @{}
}

foreach ($ver in @(
    @{ key = "py312"; pyarg = $Py312Ver },
    @{ key = "py314"; pyarg = $Py314Ver }
)) {
    $k = $ver.key
    $pyArg = $ver.pyarg
    $smokeOut = Join-Path $evDir ("test1_" + $k + "_online_smoke.json")
    $cmdOut = Join-Path $evDir ("test1_" + $k + "_cmd_out.log")
    $cmdErr = Join-Path $evDir ("test1_" + $k + "_cmd_err.log")
    $argList1 = @($pyArg, "-B", "$Root\TOOLS\online_smoke_mt5.py", "--mt5-path", $Mt5Path, "--out", $smokeOut)
    $res = _Run-Cmd -Exe $PyExe -ArgList $argList1 -Workdir $Root -OutPath $cmdOut -ErrPath $cmdErr
    $jsonOk = $false
    if (Test-Path $smokeOut) {
        try {
            $null = Get-Content $smokeOut -Raw | ConvertFrom-Json
            $jsonOk = $true
        }
        catch {
            $jsonOk = $false
        }
    }
    $t1.versions[$k] = @{
        exe = $res.exe
        args = $res.args
        rc = [int]$res.rc
        smoke_json = $smokeOut
        smoke_json_ok = [bool]$jsonOk
        stdout = $cmdOut
        stderr = $cmdErr
    }
}
$summary.tests.test1_python_runtime_matrix_vs_broker = $t1

# ---------------------------------------------------------------------------
# TEST 2: Instrument compatibility on external broker server (strict)
# ---------------------------------------------------------------------------
$t2Out = Join-Path $evDir "test2_symbols_get_audit.json"
$t2CmdOut = Join-Path $evDir "test2_cmd_out.log"
$t2CmdErr = Join-Path $evDir "test2_cmd_err.log"
$t2ArgList = @($Py312Ver, "-B", "$Root\TOOLS\audit_symbols_get_mt5.py", "--mt5-path", $Mt5Path, "--strict", "--out", $t2Out)
$t2Res = _Run-Cmd -Exe $PyExe -ArgList $t2ArgList -Workdir $Root -OutPath $t2CmdOut -ErrPath $t2CmdErr
$summary.tests.test2_instrument_server_compat = @{
    name = "instrument_server_compat_strict"
    exe = $t2Res.exe
    args = $t2Res.args
    rc = [int]$t2Res.rc
    report = $t2Out
    stdout = $t2CmdOut
    stderr = $t2CmdErr
}

# ---------------------------------------------------------------------------
# TEST 3: Local contract/instrument policy regression suite
# ---------------------------------------------------------------------------
$t3CmdOut = Join-Path $evDir "test3_cmd_out.log"
$t3CmdErr = Join-Path $evDir "test3_cmd_err.log"
$t3ArgList = @($Py312Ver, "-m", "unittest", "tests.test_symbol_aliases_oanda_mt5_pl", "tests.test_oanda_limits_integration", "tests.test_contract_run_v2", "-v")
$t3Res = _Run-Cmd -Exe $PyExe -ArgList $t3ArgList -Workdir $Root -OutPath $t3CmdOut -ErrPath $t3CmdErr
$summary.tests.test3_local_instrument_contracts = @{
    name = "local_instrument_contracts_regression"
    exe = $t3Res.exe
    args = $t3Res.args
    rc = [int]$t3Res.rc
    stdout = $t3CmdOut
    stderr = $t3CmdErr
}

$summaryPath = Join-Path $evDir "BROKER_COMPAT_3TESTS_SUMMARY.json"
$summary | ConvertTo-Json -Depth 8 | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host "BROKER_COMPAT_3TESTS_DONE summary=$summaryPath"
exit 0
