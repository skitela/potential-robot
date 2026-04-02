param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ServerName = "OANDATMS-MT5",
    [string]$TerminalDataDirOverride = "",
    [string]$PreferredProductionTerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [Alias("BotName")]
    [string]$ExpertName = "MicroBot_EURUSD",
    [string]$Symbol = "",
    [string]$PortableLabRoot = "C:\TRADING_TOOLS\MT5_NEAR_PROFIT_LAB",
    [string]$PortableQdmLabRoot = "C:\TRADING_TOOLS\MT5_QDM_CUSTOM_LAB",
    [switch]$CopySourcesToTerminal
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

function Get-IniValue {
    param(
        [string[]]$Lines,
        [string]$Section,
        [string]$Key
    )
    $sec = "[" + $Section + "]"
    $inSection = $false
    foreach ($line in $Lines) {
        $t = $line.Trim()
        if ($t -match '^\[.*\]$') {
            $inSection = ($t -ieq $sec)
            continue
        }
        if (-not $inSection) { continue }
        if ($t -match ('^' + [regex]::Escape($Key) + '\s*=(.*)$')) {
            return $matches[1].Trim()
        }
    }
    return ""
}

function Resolve-TerminalDataDir {
    param([string]$Server)
    $base = Join-Path $env:APPDATA "MetaQuotes\\Terminal"
    if (-not (Test-Path $base)) {
        return $null
    }

    $best = $null
    $bestScore = -1
    Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $ini = Join-Path $_.FullName "config\\common.ini"
        if (-not (Test-Path $ini)) { return }
        $lines = Get-Content $ini -Encoding UTF8
        $srv = Get-IniValue -Lines $lines -Section "Common" -Key "Server"
        $score = 1
        if ($srv -ieq $Server) { $score += 1000 }
        try { $score += [int]((Get-Item $ini).LastWriteTimeUtc.ToFileTimeUtc() / 10000000) } catch {}
        if ($score -gt $bestScore) {
            $bestScore = $score
            $best = $_.FullName
        }
    }
    return $best
}

function Resolve-MetaEditor {
    $candidates = @(
        (Join-Path $env:ProgramW6432 "OANDA TMS MT5 Terminal\\MetaEditor64.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "OANDA TMS MT5 Terminal\\MetaEditor64.exe"),
        (Join-Path $env:ProgramFiles "OANDA TMS MT5 Terminal\\MetaEditor64.exe")
    ) | Where-Object { $_ -and (Test-Path $_) }
    return ($candidates | Select-Object -First 1)
}

function Get-CompiledExpertCandidates {
    param([string]$CompiledExpertName)

    $base = Join-Path $env:APPDATA "MetaQuotes\\Terminal"
    if (-not (Test-Path -LiteralPath $base)) {
        return @()
    }

    $rows = @()
    Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $candidate = Join-Path $_.FullName ("MQL5\\Experts\\MicroBots\\{0}.ex5" -f $CompiledExpertName)
        if (Test-Path -LiteralPath $candidate) {
            try {
                $item = Get-Item -LiteralPath $candidate -ErrorAction Stop
                $rows += [pscustomobject]@{
                    expert_path = $candidate
                    terminal_data_dir = $_.FullName
                    last_write_utc = $item.LastWriteTimeUtc
                    size = $item.Length
                }
            }
            catch {
            }
        }
    }

    return @($rows)
}

function Resolve-FreshCompiledExpertArtifact {
    param(
        [string]$CompiledExpertName,
        [datetime]$CompileStartedUtc,
        [string]$PreferredTerminalDataDir
    )

    $candidates = @(Get-CompiledExpertCandidates -CompiledExpertName $CompiledExpertName)
    if (-not $candidates) {
        return $null
    }

    $recentThreshold = $CompileStartedUtc.AddMinutes(-2)
    $recent = @($candidates | Where-Object { $_.last_write_utc -ge $recentThreshold })
    if ($recent.Count -gt 0) {
        return @(
            $recent |
                Sort-Object @{Expression = { if ($_.terminal_data_dir -eq $PreferredTerminalDataDir) { 1 } else { 0 } }; Descending = $true },
                            @{Expression = { $_.last_write_utc }; Descending = $true },
                            @{Expression = { $_.size }; Descending = $true }
        )[0]
    }

    return @(
        $candidates |
            Sort-Object @{Expression = { if ($_.terminal_data_dir -eq $PreferredTerminalDataDir) { 1 } else { 0 } }; Descending = $true },
                        @{Expression = { $_.last_write_utc }; Descending = $true },
                        @{Expression = { $_.size }; Descending = $true }
    )[0]
}

function Sync-CompiledExpertToTerminalDataDir {
    param(
        [string]$SourceExpertPath,
        [string]$TargetTerminalDataDir,
        [string]$CompiledExpertName
    )

    $result = [ordered]@{
        attempted = $false
        source_path = $SourceExpertPath
        target_path = $null
        synced = $false
        skipped_reason = ""
    }

    if ([string]::IsNullOrWhiteSpace($SourceExpertPath) -or -not (Test-Path -LiteralPath $SourceExpertPath)) {
        $result.skipped_reason = "compiled_expert_missing"
        return [pscustomobject]$result
    }

    $targetDir = Join-Path $TargetTerminalDataDir "MQL5\\Experts\\MicroBots"
    $targetPath = Join-Path $targetDir ("{0}.ex5" -f $CompiledExpertName)
    $result.attempted = $true
    $result.target_path = $targetPath

    $sourcePathNormalized = [System.IO.Path]::GetFullPath($SourceExpertPath).TrimEnd('\\').ToLowerInvariant()
    $targetPathNormalized = [System.IO.Path]::GetFullPath($targetPath).TrimEnd('\\').ToLowerInvariant()
    if ($sourcePathNormalized -eq $targetPathNormalized) {
        $result.skipped_reason = "source_equals_target"
        return [pscustomobject]$result
    }

    try {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        Copy-Item -LiteralPath $SourceExpertPath -Destination $targetPath -Force -ErrorAction Stop
        $result.synced = $true
        return [pscustomobject]$result
    }
    catch {
        $result.skipped_reason = $_.Exception.Message
        return [pscustomobject]$result
    }
}

function Sync-CompiledExpertToPortableLab {
    param(
        [string]$SourceTerminalDataDir,
        [string]$PortableLabRootPath,
        [string]$CompiledExpertName
    )

    $result = [ordered]@{
        attempted = $false
        target_path = $null
        synced = $false
        skipped_reason = ""
    }

    if ([string]::IsNullOrWhiteSpace($PortableLabRootPath) -or -not (Test-Path -LiteralPath $PortableLabRootPath)) {
        $result.skipped_reason = "portable_lab_missing"
        return [pscustomobject]$result
    }

    $sourcePath = Join-Path $SourceTerminalDataDir ("MQL5\\Experts\\MicroBots\\{0}.ex5" -f $CompiledExpertName)
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        $result.skipped_reason = "compiled_expert_missing"
        return [pscustomobject]$result
    }

    $targetDir = Join-Path $PortableLabRootPath "MQL5\\Experts\\MicroBots"
    $targetPath = Join-Path $targetDir ("{0}.ex5" -f $CompiledExpertName)
    $result.attempted = $true
    $result.target_path = $targetPath

    $sourcePathNormalized = [System.IO.Path]::GetFullPath($sourcePath).TrimEnd('\\').ToLowerInvariant()
    $targetPathNormalized = [System.IO.Path]::GetFullPath($targetPath).TrimEnd('\\').ToLowerInvariant()
    if ($sourcePathNormalized -eq $targetPathNormalized) {
        $result.skipped_reason = "source_equals_target"
        return [pscustomobject]$result
    }

    try {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force -ErrorAction Stop
        $result.synced = $true
        return [pscustomobject]$result
    }
    catch {
        $result.skipped_reason = $_.Exception.Message
        return [pscustomobject]$result
    }
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$registryPath = Join-Path $projectPath "CONFIG\\microbots_registry.json"
if ($Symbol) {
    if (-not (Test-Path -LiteralPath $registryPath)) {
        throw "Missing registry: $registryPath"
    }
    $registry = Get-Content -Path $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $match = Find-RegistryEntryByAlias -Registry $registry -Alias $Symbol
    if ($null -eq $match) {
        throw "Symbol not found in registry: $Symbol"
    }
    $ExpertName = [string]$match.expert
}
$expertFile = "$ExpertName.mq5"
$expertSource = Join-Path $projectPath ("MQL5\\Experts\\MicroBots\\{0}" -f $expertFile)
if (-not (Test-Path -LiteralPath $expertSource)) {
    throw "Missing expert source: $expertSource"
}

$terminalDataDir = $null
if (-not [string]::IsNullOrWhiteSpace($TerminalDataDirOverride)) {
    $terminalDataDir = (Resolve-Path -LiteralPath $TerminalDataDirOverride).Path
}
elseif ($ServerName -eq "OANDATMS-MT5" -and -not [string]::IsNullOrWhiteSpace($PreferredProductionTerminalDataDir) -and (Test-Path -LiteralPath $PreferredProductionTerminalDataDir)) {
    $terminalDataDir = (Resolve-Path -LiteralPath $PreferredProductionTerminalDataDir).Path
}
else {
    $terminalDataDir = Resolve-TerminalDataDir -Server $ServerName
}
if (-not $terminalDataDir) {
    throw "Could not resolve MT5 terminal data directory."
}

$metaEditor = Resolve-MetaEditor
if (-not $metaEditor) {
    throw "MetaEditor64.exe not found."
}

$targetMql5 = Join-Path $terminalDataDir "MQL5"
$targetExperts = Join-Path $targetMql5 "Experts\\MicroBots"
$targetCore = Join-Path $targetMql5 "Include\\Core"
$targetProfiles = Join-Path $targetMql5 "Include\\Profiles"
$targetStrategies = Join-Path $targetMql5 "Include\\Strategies"
$targetStrategiesCommon = Join-Path $targetMql5 "Include\\Strategies\\Common"
$logDir = Join-Path $projectPath "LOGS"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$compileLog = Join-Path $logDir ("COMPILE_{0}.log" -f $ExpertName)

$shouldCopySources = $true
if ($CopySourcesToTerminal) {
    $shouldCopySources = $true
}

if ($shouldCopySources) {
    New-Item -ItemType Directory -Force -Path $targetExperts | Out-Null
    New-Item -ItemType Directory -Force -Path $targetCore | Out-Null
    New-Item -ItemType Directory -Force -Path $targetProfiles | Out-Null
    New-Item -ItemType Directory -Force -Path $targetStrategies | Out-Null
    New-Item -ItemType Directory -Force -Path $targetStrategiesCommon | Out-Null

    Copy-Item (Join-Path $projectPath "MQL5\\Experts\\MicroBots\\*.mq5") $targetExperts -Force
    Copy-Item (Join-Path $projectPath "MQL5\\Include\\Core\\*.mqh") $targetCore -Force
    Copy-Item (Join-Path $projectPath "MQL5\\Include\\Profiles\\*.mqh") $targetProfiles -Force
    Copy-Item (Join-Path $projectPath "MQL5\\Include\\Strategies\\*.mqh") $targetStrategies -Force
    Copy-Item (Join-Path $projectPath "MQL5\\Include\\Strategies\\Common\\*.mqh") $targetStrategiesCommon -Force
}

$expertTarget = Join-Path $targetExperts $expertFile
if (-not (Test-Path -LiteralPath $expertTarget)) {
    throw "Expert file not present in terminal data dir. Re-run with -CopySourcesToTerminal."
}

$compileStartedUtc = (Get-Date).ToUniversalTime()
& $metaEditor "/compile:$expertTarget" "/log:$compileLog" | Out-Null

$compileOk = $false
if (Test-Path -LiteralPath $compileLog) {
    $compileText = $null
    foreach ($encoding in @('Unicode','UTF8','Default')) {
        try {
            $compileText = Get-Content -Path $compileLog -Raw -Encoding $encoding -ErrorAction Stop
        } catch {
            $compileText = $null
        }
        if ($compileText) { break }
    }

    if ($compileText -and ($compileText -match 'Result:\s+0 errors' -or $compileText -match '0 error\(s\)')) {
        $compileOk = $true
    }
}

$compiledArtifact = $null
$terminalSync = $null
if ($compileOk) {
    $compiledArtifact = Resolve-FreshCompiledExpertArtifact `
        -CompiledExpertName $ExpertName `
        -CompileStartedUtc $compileStartedUtc `
        -PreferredTerminalDataDir $terminalDataDir

    if ($null -ne $compiledArtifact) {
        $terminalSync = Sync-CompiledExpertToTerminalDataDir `
            -SourceExpertPath ([string]$compiledArtifact.expert_path) `
            -TargetTerminalDataDir $terminalDataDir `
            -CompiledExpertName $ExpertName
    }
    else {
        $terminalSync = [pscustomobject]@{
            attempted = $false
            source_path = $null
            target_path = (Join-Path $terminalDataDir ("MQL5\\Experts\\MicroBots\\{0}.ex5" -f $ExpertName))
            synced = $false
            skipped_reason = "compiled_artifact_not_found"
        }
    }
}

$result = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    server_name = $ServerName
    symbol = $Symbol
    terminal_data_dir = $terminalDataDir
    metaeditor = $metaEditor
    expert = $ExpertName
    copied_sources = [bool]$shouldCopySources
    compile_log = $compileLog
    compile_ok = $compileOk
    actual_compiled_expert_path = if ($null -ne $compiledArtifact) { [string]$compiledArtifact.expert_path } else { $null }
    actual_compiled_terminal_data_dir = if ($null -ne $compiledArtifact) { [string]$compiledArtifact.terminal_data_dir } else { $null }
    terminal_sync = $terminalSync
}

if ($compileOk) {
    $result.portable_lab_sync = Sync-CompiledExpertToPortableLab -SourceTerminalDataDir $terminalDataDir -PortableLabRootPath $PortableLabRoot -CompiledExpertName $ExpertName
    $result.portable_qdm_lab_sync = Sync-CompiledExpertToPortableLab -SourceTerminalDataDir $terminalDataDir -PortableLabRootPath $PortableQdmLabRoot -CompiledExpertName $ExpertName
}

$result | ConvertTo-Json -Depth 5

if (-not $compileOk) {
    exit 1
}
