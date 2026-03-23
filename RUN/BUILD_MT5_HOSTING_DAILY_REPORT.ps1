param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$DateStamp = (Get-Date).ToString('yyyyMMdd'),
    [string]$CommonFilesRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
)

$ErrorActionPreference = 'Stop'

function Normalize-AsciiText {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }
    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $normalized.ToCharArray()) {
        $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($cat -ne [Globalization.UnicodeCategory]::NonSpacingMark -and [int][char]$ch -le 127) {
            [void]$sb.Append($ch)
        }
    }
    ($sb.ToString() -replace '[^\x20-\x7E]','').Trim()
}

function Get-HostingTerminalLogs {
    param([string]$DateStamp)
    Get-ChildItem -Path 'C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal' -Recurse -File -Filter "$DateStamp.log" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'hosting\.6797020\.terminal' }
}

function Resolve-HostingLogSelection {
    param([string]$PreferredDateStamp)

    $preferred = @(Get-HostingTerminalLogs -DateStamp $PreferredDateStamp)
    if (@($preferred).Count -gt 0) {
        return [pscustomobject]@{
            RequestedDateStamp = $PreferredDateStamp
            ResolvedDateStamp  = $PreferredDateStamp
            FallbackApplied    = $false
            Files              = @($preferred)
        }
    }

    $latest = Get-ChildItem -Path 'C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal' -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -match 'hosting\.6797020\.terminal' -and
            $_.BaseName -match '^\d{8}$'
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latest) {
        $resolvedDateStamp = $latest.BaseName
        return [pscustomobject]@{
            RequestedDateStamp = $PreferredDateStamp
            ResolvedDateStamp  = $resolvedDateStamp
            FallbackApplied    = ($resolvedDateStamp -ne $PreferredDateStamp)
            Files              = @(Get-HostingTerminalLogs -DateStamp $resolvedDateStamp)
        }
    }

    return [pscustomobject]@{
        RequestedDateStamp = $PreferredDateStamp
        ResolvedDateStamp  = $PreferredDateStamp
        FallbackApplied    = $false
        Files              = @()
    }
}

function Get-Sha256Hex {
    param([string]$Path)

    if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
        return [string](Get-FileHash -Algorithm SHA256 -Path $Path).Hash
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $hashBytes = $sha256.ComputeHash($stream)
            return ([System.BitConverter]::ToString($hashBytes)).Replace("-", "")
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-CanonicalLogs {
    param([System.IO.FileInfo[]]$Files)
    $rows = foreach ($file in $Files) {
        $hash = Get-Sha256Hex -Path $file.FullName
        [pscustomobject]@{
            Path = $file.FullName
            LastWriteTime = $file.LastWriteTime
            Length = $file.Length
            Hash = $hash
        }
    }
    $rows | Group-Object Hash | ForEach-Object {
        $chosen = $_.Group | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        [pscustomobject]@{
            Hash = $_.Name
            CanonicalPath = $chosen.Path
            DuplicateCount = $_.Count
            DuplicatePaths = @($_.Group.Path)
        }
    }
}

function Parse-HostingTerminalLog {
    param([string]$Path)
    $lines = Get-Content -Path $Path

    $heartbeatRows = New-Object System.Collections.Generic.List[object]
    $ramRows = New-Object System.Collections.Generic.List[object]
    $pingRows = New-Object System.Collections.Generic.List[object]
    $warningRows = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        if ($line -match "\t(?<time>\d{2}:\d{2}:\d{2}\.\d{3})\tTerminal\t'(?<acct>\d+)': (?<charts>\d+) charts, (?<eas>\d+) EAs, (?<inds>\d+) custom indicators, signal disabled, last known ping to .* is (?<ping>[0-9]+\.[0-9]+) ms") {
            $heartbeatRows.Add([pscustomobject]@{
                Time = $Matches.time
                Account = $Matches.acct
                Charts = [int]$Matches.charts
                EAs = [int]$Matches.eas
                Indicators = [int]$Matches.inds
                LastKnownPingMs = [double]$Matches.ping
            })
            continue
        }

        if ($line -match "\t(?<time>\d{2}:\d{2}:\d{2}\.\d{3})\tTerminal\tRAM: (?<reserved>\d+) Mb reserved, (?<committed>\d+) Mb committed; CPU: EA (?<ea>[0-9]+\.[0-9]+)% in (?<ea_threads>\d+) threads, symbols (?<symbols>[0-9]+\.[0-9]+)% in (?<symbol_threads>\d+) threads, workers (?<workers>[0-9]+\.[0-9]+)% in (?<worker_threads>\d+) threads, (?<disk>\d+) kb written on disk") {
            $ramRows.Add([pscustomobject]@{
                Time = $Matches.time
                ReservedMb = [int]$Matches.reserved
                CommittedMb = [int]$Matches.committed
                CpuEA = [double]$Matches.ea
                CpuSymbols = [double]$Matches.symbols
                CpuWorkers = [double]$Matches.workers
                DiskWrittenKb = [int]$Matches.disk
            })
            continue
        }

        if ($line -match "\t(?<time>\d{2}:\d{2}:\d{2}\.\d{3})\tNetwork\t'(?<acct>\d+)': ping to current access point .*? is (?<ping>[0-9]+\.[0-9]+) ms") {
            $pingRows.Add([pscustomobject]@{
                Time = $Matches.time
                Account = $Matches.acct
                PingMs = [double]$Matches.ping
            })
            continue
        }

        if ($line -match "\t(?:Error|error|failed|disconnected|shutdown|stopped)\b" -or $line -match "\t(?:Signal|Journal|Network)\t.*(?:failed|disconnected|shutdown|stopped)") {
            $warningRows.Add($line)
        }
    }

    [pscustomobject]@{
        Heartbeats = @($heartbeatRows.ToArray())
        RamStats = @($ramRows.ToArray())
        Pings = @($pingRows.ToArray())
        Warnings = @($warningRows.ToArray() | Select-Object -Unique)
    }
}

function Get-LatestExpertsLog {
    Get-ChildItem -Path 'C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal' -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'hosting\.6797020\.experts\\.*\.log$' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Parse-ExpertsRoster {
    param([string]$Path)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($line in (Get-Content -Path $Path)) {
        if ($line -match "\t(?<time>\d{2}:\d{2}:\d{2}\.\d{3})\t(?<ea>MicroBot_[^(]+) \((?<symbol>[^,]+),") {
            $rows.Add([pscustomobject]@{
                Time = $Matches.time
                EA = $Matches.ea
                Symbol = $Matches.symbol
                Instrument = ($Matches.symbol -replace '\.pro$','')
            })
        }
    }
    $rows | Sort-Object Instrument -Unique
}

function Load-JsonOrNull {
    param([string]$Path)
    if (Test-Path $Path) {
        return Get-Content -Raw -Path $Path | ConvertFrom-Json
    }
    return $null
}

function Get-ActiveRegistryInstrumentSet {
    param([string]$ProjectRoot)

    $registryPath = Join-Path $ProjectRoot 'CONFIG\microbots_registry.json'
    $set = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

    if (-not (Test-Path -LiteralPath $registryPath)) {
        return $set
    }

    $registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json
    foreach ($item in @($registry.symbols)) {
        foreach ($candidate in @(
            [string]$item.symbol,
            ([string]$item.symbol -replace '\.pro$',''),
            [string]$item.broker_symbol,
            ([string]$item.broker_symbol -replace '\.pro$',''),
            [string]$item.code_symbol
        )) {
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                [void]$set.Add(($candidate -replace '\.pro$',''))
            }
        }
    }

    return $set
}

function Write-OperationalPingContract {
    param(
        [string]$CommonRoot,
        [double]$PingMs,
        [string]$SourceLabel
    )

    if ($PingMs -le 0) {
        return $null
    }

    $globalDir = Join-Path $CommonRoot 'state\_global'
    New-Item -ItemType Directory -Force -Path $globalDir | Out-Null
    $path = Join-Path $globalDir 'execution_ping_contract.csv'
    $revision = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $lines = @(
        "enabled`t1"
        "revision`t$revision"
        "refresh_interval_sec`t300"
        ("paper_operational_ping_ms`t{0}" -f ([Math]::Round($PingMs, 2).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)))
        ("live_operational_ping_ms`t{0}" -f ([Math]::Round($PingMs, 2).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)))
        ("source`t{0}" -f $SourceLabel)
    )
    ($lines -join [Environment]::NewLine) | Set-Content -Path $path -Encoding UTF8
    return $path
}

$logSelection = Resolve-HostingLogSelection -PreferredDateStamp $DateStamp
$terminalLogs = @($logSelection.Files)
if (-not $terminalLogs) {
    throw "No hosting terminal logs found for requested date stamp $DateStamp or any fallback day"
}

$canonical = @(Get-CanonicalLogs -Files $terminalLogs)
$selected = $canonical | Select-Object -First 1
$parsed = Parse-HostingTerminalLog -Path $selected.CanonicalPath

$expertsFile = Get-LatestExpertsLog
$roster = @()
$historicalRosterExcluded = @()
$activeRegistryInstruments = Get-ActiveRegistryInstrumentSet -ProjectRoot $ProjectRoot
if ($expertsFile) {
    $parsedRoster = @(Parse-ExpertsRoster -Path $expertsFile.FullName)
    $historicalRosterExcluded = @(
        $parsedRoster |
            Where-Object { -not $activeRegistryInstruments.Contains($_.Instrument) } |
            Sort-Object Instrument -Unique
    )
    $roster = @(
        $parsedRoster |
            Where-Object { $activeRegistryInstruments.Contains($_.Instrument) } |
            Sort-Object Instrument -Unique
    )
}

$runtimeCompactPath = Join-Path $ProjectRoot 'EVIDENCE\OPS\paper_live_feedback_latest.json'
$syncPath = Join-Path $ProjectRoot 'EVIDENCE\OPS\paper_live_sync_latest.json'
$runtimeCompact = Load-JsonOrNull -Path $runtimeCompactPath
$syncInfo = Load-JsonOrNull -Path $syncPath

$instrumentStatus = @{}
if ($runtimeCompact) {
    foreach ($row in @($runtimeCompact.top_active)) {
        $instrumentStatus[$row.instrument] = [pscustomobject]@{
            Instrument = $row.instrument
            Source = 'paper_live_feedback.top_active'
            Opens = $row.opens
            Closes = $row.closes
            Wins = $row.wins
            Losses = $row.losses
            Neutral = $row.neutral
            Net = $row.net
            Trust = $row.trust
            Cost = $row.cost
            Market = $row.market
            LastEvent = $null
        }
    }
    foreach ($row in @($runtimeCompact.key_instruments)) {
        $instrumentStatus[$row.instrument] = [pscustomobject]@{
            Instrument = $row.instrument
            Source = 'paper_live_feedback.key_instruments'
            Opens = $row.opens
            Closes = $row.closes
            Wins = $row.wins
            Losses = $row.losses
            Neutral = $row.neutral
            Net = $row.net
            Trust = $row.trust
            Cost = $row.cost
            Market = $row.market
            LastEvent = $row.last_event
        }
    }
}

$allInstruments = @($roster.Instrument | Sort-Object -Unique)
$instrumentRows = foreach ($instrument in $allInstruments) {
    if ($instrumentStatus.ContainsKey($instrument)) {
        $instrumentStatus[$instrument]
    }
    else {
        [pscustomobject]@{
            Instrument = $instrument
            Source = 'experts_roster_only'
            Opens = $null
            Closes = $null
            Wins = $null
            Losses = $null
            Neutral = $null
            Net = $null
            Trust = $null
            Cost = $null
            Market = $null
            LastEvent = $null
        }
    }
}

$heartbeatCount = @($parsed.Heartbeats).Count
$firstHeartbeat = @($parsed.Heartbeats | Select-Object -First 1).Time
$lastHeartbeat = @($parsed.Heartbeats | Select-Object -Last 1).Time
$chartCounts = @($parsed.Heartbeats | ForEach-Object Charts | Sort-Object -Unique)
$eaCounts = @($parsed.Heartbeats | ForEach-Object EAs | Sort-Object -Unique)
$pingValues = @($parsed.Pings | ForEach-Object PingMs)
$committedValues = @($parsed.RamStats | ForEach-Object CommittedMb)
$cpuEAValues = @($parsed.RamStats | ForEach-Object CpuEA)
$cpuWorkerValues = @($parsed.RamStats | ForEach-Object CpuWorkers)
$cpuSymbolValues = @($parsed.RamStats | ForEach-Object CpuSymbols)

$summary = [pscustomobject]@{
    generated_local = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    requested_date_stamp = $logSelection.RequestedDateStamp
    date_stamp = $logSelection.ResolvedDateStamp
    fallback_to_latest_available = [bool]$logSelection.FallbackApplied
    canonical_terminal_log = $selected.CanonicalPath
    duplicate_terminal_log_count = $selected.DuplicateCount
    duplicate_terminal_log_paths = @($selected.DuplicatePaths)
    heartbeat_count = $heartbeatCount
    first_heartbeat = $firstHeartbeat
    last_heartbeat = $lastHeartbeat
    chart_counts = @($chartCounts)
    ea_counts = @($eaCounts)
    ping_min_ms = if ($pingValues) { [Math]::Round(($pingValues | Measure-Object -Minimum).Minimum, 2) } else { $null }
    ping_max_ms = if ($pingValues) { [Math]::Round(($pingValues | Measure-Object -Maximum).Maximum, 2) } else { $null }
    ping_avg_ms = if ($pingValues) { [Math]::Round(($pingValues | Measure-Object -Average).Average, 2) } else { $null }
    committed_ram_min_mb = if ($committedValues) { ($committedValues | Measure-Object -Minimum).Minimum } else { $null }
    committed_ram_max_mb = if ($committedValues) { ($committedValues | Measure-Object -Maximum).Maximum } else { $null }
    cpu_ea_max_pct = if ($cpuEAValues) { [Math]::Round(($cpuEAValues | Measure-Object -Maximum).Maximum, 2) } else { $null }
    cpu_symbols_max_pct = if ($cpuSymbolValues) { [Math]::Round(($cpuSymbolValues | Measure-Object -Maximum).Maximum, 2) } else { $null }
    cpu_workers_max_pct = if ($cpuWorkerValues) { [Math]::Round(($cpuWorkerValues | Measure-Object -Maximum).Maximum, 2) } else { $null }
    warning_count_today = @($parsed.Warnings).Count
    latest_experts_log = if ($expertsFile) { $expertsFile.FullName } else { $null }
    latest_experts_log_last_write = if ($expertsFile) { $expertsFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
    roster_count = @($roster).Count
    historical_roster_excluded_count = @($historicalRosterExcluded).Count
    historical_roster_excluded_symbols = @($historicalRosterExcluded | ForEach-Object { $_.Instrument })
    migration_last_line = if ($syncInfo) { Normalize-AsciiText $syncInfo.last_migration_line } else { $null }
    migration_scope = if ($syncInfo) { Normalize-AsciiText $syncInfo.migration_scope_label } else { $null }
    runtime_snapshot_generated_local = if ($runtimeCompact) { $runtimeCompact.generated_local } else { $null }
    runtime_window_start_local = if ($runtimeCompact) { $runtimeCompact.window_start_local } else { $null }
    runtime_net = if ($runtimeCompact) { $runtimeCompact.net } else { $null }
    runtime_active_instruments = if ($runtimeCompact) { $runtimeCompact.active_instruments } else { $null }
    runtime_warning_count = if ($runtimeCompact) { $runtimeCompact.warnings } else { $null }
    instrument_rows = @($instrumentRows)
}

$executionPingContractPath = Write-OperationalPingContract -CommonRoot $CommonFilesRoot -PingMs ([double]$summary.ping_avg_ms) -SourceLabel 'hosting_vps_broker'
if ($executionPingContractPath) {
    Add-Member -InputObject $summary -NotePropertyName execution_ping_contract_path -NotePropertyValue $executionPingContractPath
}

$outDir = Join-Path $ProjectRoot 'EVIDENCE\OPS'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$jsonPath = Join-Path $outDir 'mt5_hosting_daily_report_latest.json'
$mdPath = Join-Path $outDir 'mt5_hosting_daily_report_latest.md'

$summary | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Raport Dzienny MT5 Hosting')
$md.Add('')
$md.Add("Wygenerowano lokalnie: $($summary.generated_local)")
$md.Add("Data logu hostingu: $($summary.date_stamp)")
if ($summary.fallback_to_latest_available) {
    $md.Add("Prosba o date stamp $($summary.requested_date_stamp) zostala obsluzona fallbackiem do najnowszego dostepnego logu.")
}
$md.Add('')
$md.Add('## Werdykt')
$md.Add('')
$md.Add('- Hosting MT5 jest zywy i raportuje regularne heartbeat-y dzisiaj.')
$md.Add("- Ostatni heartbeat terminala w logu: $($summary.last_heartbeat)")
$md.Add("- Srodowisko hostingu utrzymuje stale: $((($summary.chart_counts) -join ', ')) charts / $((($summary.ea_counts) -join ', ')) EAs.")
$md.Add('- Dzisiejsze logi terminala sa zdublowane w dwoch katalogach, ale maja ta sama tresc.')
$md.Add('- Dzienny log ekspertow nie powstal dzisiaj; ostatni log ekspertow pochodzi z czasu migracji i jest czytany tylko jako historyczny slad.')
$md.Add('- Lista EA w tym raporcie jest filtrowana do aktywnej floty z rejestru, wiec wycofane symbole nie wracaja juz do prawdy operacyjnej.')
$md.Add('- Per-instrument runtime ponizej pochodzi z ostatniego dostepnego snapshotu paper/live, a nie z dzisiejszego logu terminala.')
$md.Add('')
$md.Add('## Heartbeat Dnia')
$md.Add('')
$md.Add("- Heartbeat count: $($summary.heartbeat_count)")
$md.Add("- Pierwszy heartbeat: $($summary.first_heartbeat)")
$md.Add("- Ostatni heartbeat: $($summary.last_heartbeat)")
$md.Add("- Ping min/max/avg: $($summary.ping_min_ms) / $($summary.ping_max_ms) / $($summary.ping_avg_ms) ms")
$md.Add("- Ten ping traktujemy jako glowny ping operacyjny VPS <-> broker.")
$md.Add("- RAM committed min/max: $($summary.committed_ram_min_mb) / $($summary.committed_ram_max_mb) MB")
$md.Add("- CPU max: EA $($summary.cpu_ea_max_pct)% ; symbols $($summary.cpu_symbols_max_pct)% ; workers $($summary.cpu_workers_max_pct)%")
$md.Add('')
$md.Add('## Migracja i Roster EA')
$md.Add('')
$md.Add("- Ostatnia potwierdzona migracja: $($summary.migration_last_line)")
$md.Add("- Zakres migracji: $($summary.migration_scope)")
$md.Add("- Ostatni log ekspertow: $($summary.latest_experts_log_last_write)")
$md.Add("- Zaladowane EA z logu ekspertow: $($summary.roster_count)")
if (@($summary.historical_roster_excluded_symbols).Count -gt 0) {
    $md.Add("- Historycznie wykluczone symbole odfiltrowane z rosteru: $((@($summary.historical_roster_excluded_symbols) -join ', '))")
}
$md.Add('')
$md.Add('### Lista EA / Instrumentow')
$md.Add('')
foreach ($row in $roster) {
    $md.Add("- $($row.Instrument) : $($row.EA) ; load_time=$($row.Time)")
}
$md.Add('')
$md.Add('## Ostatni Znany Stan Paper/Live Per Instrument')
$md.Add('')
$md.Add("Zrodlo runtime snapshotu: $($summary.runtime_snapshot_generated_local) (okno od $($summary.runtime_window_start_local))")
$md.Add('')
$md.Add('| Instrument | Net | Opens | Wins | Losses | Trust | Cost | Market | Source | LastEvent |')
$md.Add('|---|---:|---:|---:|---:|---|---|---|---|---|')
foreach ($row in ($instrumentRows | Sort-Object Instrument)) {
    $net = if ($null -ne $row.Net) { [string]$row.Net } else { '' }
    $opens = if ($null -ne $row.Opens) { [string]$row.Opens } else { '' }
    $wins = if ($null -ne $row.Wins) { [string]$row.Wins } else { '' }
    $losses = if ($null -ne $row.Losses) { [string]$row.Losses } else { '' }
    $trust = if ($row.Trust) { [string]$row.Trust } else { '' }
    $cost = if ($row.Cost) { [string]$row.Cost } else { '' }
    $market = if ($row.Market) { [string]$row.Market } else { '' }
    $source = if ($row.Source) { [string]$row.Source } else { '' }
    $lastEvent = if ($row.LastEvent) { [string]$row.LastEvent } else { '' }
    $md.Add("| $($row.Instrument) | $net | $opens | $wins | $losses | $trust | $cost | $market | $source | $lastEvent |")
}
$md.Add('')
$md.Add('## Uwagi')
$md.Add('')
if (@($parsed.Warnings).Count -gt 0) {
    $md.Add('- W dzisiejszym logu terminala znaleziono ostrzegawcze wpisy:')
    foreach ($warn in ($parsed.Warnings | Select-Object -First 10)) {
        $md.Add("  - $warn")
    }
}
else {
    $md.Add('- W dzisiejszym logu terminala nie znaleziono oczywistych bledow typu disconnect/shutdown/failed w ogonie dnia.')
}
$md.Add('- Dzisiejszy log terminala nie zawiera wpisow per symbol; pokazuje zdrowie hostingu jako calego kontenera VPS.')
$md.Add('- Lista instrumentow i zaladowanych EA jest ograniczona do aktywnej floty z rejestru; historyczny log ekspertow nie moze juz reaktywowac wycofanych symboli w raporcie.')
$md.Add('- Wartosci paper/live per instrument pochodza z ostatniego dostepnego runtime compact, wiec trzeba je czytac jako ostatnia znana prawde, a nie dzisiejszy swiezy pull z VPS.')

$md -join [Environment]::NewLine | Set-Content -Path $mdPath -Encoding UTF8

Write-Output "REPORT_OK $mdPath"
Write-Output "REPORT_OK $jsonPath"
