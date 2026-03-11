param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM"
)

$tokenEnvPath = ""
foreach ($candidate in @("D:\TOKEN\BotKey.env", "C:\TOKEN\BotKey.env")) {
    if (Test-Path -LiteralPath $candidate) {
        $tokenEnvPath = $candidate
        break
    }
}

$paths = @(
    "BIN\\safetybot.py",
    "BIN\\zeromq_bridge.py",
    "BIN\\runtime_supervisor.py",
    "BIN\\deployment_plane.py",
    "BIN\\kernel_config_plane.py",
    "TOOLS\\setup_mt5_hybrid_profile.py",
    "MQL5\\Experts\\HybridAgent.mq5",
    "Aktualizuj_EA.bat",
    "RUN\\START_WITH_OANDAKEY.ps1",
    "TOOLS\\SYSTEM_CONTROL.ps1"
)

$params = @{
    Root = $Root
    TokenEnvPath = $tokenEnvPath
    Paths = $paths
    RunProfileSetup = $true
    RunEaDeploy = $true
    StartRuntime = $true
    Profile = "safety_only"
}

& (Join-Path $Root "TOOLS\VPS_SSH_DELTA_DEPLOY.ps1") @params
