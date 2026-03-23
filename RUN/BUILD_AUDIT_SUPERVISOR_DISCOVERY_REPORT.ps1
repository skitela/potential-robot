param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$EvidenceRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE",
    [string]$OpsRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$LookbackDays = 7
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-OptionalValue {
    param(
        [object]$Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function Add-FindingRecord {
    param(
        [System.Collections.Generic.List[object]]$Collection,
        [string]$Source,
        [string]$Severity,
        [string]$Component,
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Component)) {
        return
    }

    $Collection.Add([pscustomobject]@{
            source = $Source
            severity = $(if ([string]::IsNullOrWhiteSpace($Severity)) { "unknown" } else { $Severity.Trim().ToLowerInvariant() })
            component = $Component.Trim()
            message = $(if ([string]::IsNullOrWhiteSpace($Message)) { "UNKNOWN" } else { ($Message -replace '\s+', ' ').Trim() })
        }) | Out-Null
}

function Get-SeverityRank {
    param([string]$Severity)

    $normalized = ""
    if (-not [string]::IsNullOrWhiteSpace($Severity)) {
        $normalized = $Severity.ToLowerInvariant()
    }

    switch ($normalized) {
        "critical" { return 4 }
        "high" { return 3 }
        "medium" { return 2 }
        "low" { return 1 }
        default { return 0 }
    }
}

function Get-DomainForComponent {
    param([string]$Component)

    switch ($Component) {
        "registry_files" { return "POCHODZENIE_WDROZENIA" }
        "retired_symbol_references" { return "SPOJNOSC_FLOTY" }
        "family_symbol_naming" { return "SPOJNOSC_FLOTY" }
        "family_reference_registry" { return "SPOJNOSC_FLOTY" }
        "orphan_dirs" { return "HIGIENA_RUNTIME" }
        "runtime_logs" { return "HIGIENA_RUNTIME" }
        "git" { return "HIGIENA_RUNTIME" }
        "terminal_ping_in_core" { return "JAKOSC_WYKONANIA" }
        "learning_runtime" { return "STOS_UCZENIA" }
        "learning_stack" { return "STOS_UCZENIA" }
        "onnx_feedback" { return "ONNX_I_SPRZEZENIE_ZWROTNE" }
        "onnx_runtime" { return "ONNX_I_SPRZEZENIE_ZWROTNE" }
        "onnx_fallbacks" { return "ONNX_I_SPRZEZENIE_ZWROTNE" }
        "onnx_quality" { return "ONNX_I_SPRZEZENIE_ZWROTNE" }
        "triple_loop_audit" { return "ONNX_I_SPRZEZENIE_ZWROTNE" }
        default { return "INNE" }
    }
}

function Get-ActionClassForComponent {
    param([string]$Component)

    switch ($Component) {
        "registry_files" { return "BLOKUJ_ROLLOUT" }
        "retired_symbol_references" { return "BLOKUJ_ROLLOUT" }
        "family_symbol_naming" { return "NAPRAW_W_CYKLU" }
        "family_reference_registry" { return "NAPRAW_W_CYKLU" }
        "orphan_dirs" { return "CZYSZC_AUTOMATYCZNIE" }
        "runtime_logs" { return "ROTACJA_AUTOMATYCZNA" }
        "git" { return "RAPORTUJ_I_WYMAGAJ_CZYSTEGO_STANU_PRZED_ROLLOUTEM" }
        "terminal_ping_in_core" { return "BLOKUJ_LIVE" }
        "learning_runtime" { return "NAPRAW_W_CYKLU" }
        "learning_stack" { return "MONITORUJ_I_PRIORYTETYZUJ" }
        "onnx_feedback" { return "MONITORUJ_I_CZEKAJ_NA_SYGNAL" }
        "onnx_runtime" { return "MONITORUJ_I_CZEKAJ_NA_SYGNAL" }
        "onnx_fallbacks" { return "MONITORUJ_I_DOSZKALAJ" }
        "onnx_quality" { return "MONITORUJ_I_DOSZKALAJ" }
        "triple_loop_audit" { return "MONITORUJ_I_NAPRAWIAJ" }
        default { return "RAPORTUJ" }
    }
}

New-Item -ItemType Directory -Force -Path $OpsRoot | Out-Null

$cutoff = (Get-Date).AddDays(-1 * [math]::Abs($LookbackDays))
$jsonFiles = Get-ChildItem -LiteralPath $EvidenceRoot -Recurse -File -Filter *.json -ErrorAction SilentlyContinue |
    Where-Object {
        $_.LastWriteTime -ge $cutoff -and (
            $_.Name -match 'audit' -or
            $_.Name -match 'verify' -or
            $_.Name -match 'validation' -or
            $_.Name -match 'readiness' -or
            $_.Name -match 'feedback'
        )
    }

$findings = New-Object System.Collections.Generic.List[object]
$sourcesAnalyzed = New-Object System.Collections.Generic.List[string]

foreach ($file in @($jsonFiles)) {
    $relativePath = $file.FullName.Replace($EvidenceRoot.TrimEnd('\') + '\', '')
    $sourcesAnalyzed.Add($relativePath) | Out-Null
    $data = Read-JsonSafe -Path $file.FullName
    if ($null -eq $data) {
        continue
    }

    foreach ($finding in @(Get-OptionalValue -Object $data -Name 'findings' -Default @())) {
        if ($finding -is [pscustomobject] -or $finding -is [hashtable]) {
            Add-FindingRecord -Collection $findings -Source $relativePath -Severity ([string](Get-OptionalValue -Object $finding -Name 'severity' -Default 'unknown')) -Component ([string](Get-OptionalValue -Object $finding -Name 'component' -Default ([string](Get-OptionalValue -Object $finding -Name 'code' -Default ([string](Get-OptionalValue -Object $finding -Name 'label' -Default 'UNKNOWN')))))) -Message ([string](Get-OptionalValue -Object $finding -Name 'message' -Default ([string](Get-OptionalValue -Object $finding -Name 'summary' -Default 'UNKNOWN'))))
        }
    }

    $verification = Get-OptionalValue -Object $data -Name 'verification' -Default $null
    foreach ($finding in @(Get-OptionalValue -Object $verification -Name 'findings' -Default @())) {
        if ($finding -is [pscustomobject] -or $finding -is [hashtable]) {
            Add-FindingRecord -Collection $findings -Source $relativePath -Severity ([string](Get-OptionalValue -Object $finding -Name 'severity' -Default 'unknown')) -Component ([string](Get-OptionalValue -Object $finding -Name 'component' -Default ([string](Get-OptionalValue -Object $finding -Name 'code' -Default ([string](Get-OptionalValue -Object $finding -Name 'label' -Default 'UNKNOWN')))))) -Message ([string](Get-OptionalValue -Object $finding -Name 'message' -Default ([string](Get-OptionalValue -Object $finding -Name 'summary' -Default 'UNKNOWN'))))
        }
    }
}

$componentGroups = @($findings | Group-Object component | Sort-Object Count -Descending)
$componentItems = New-Object System.Collections.Generic.List[object]

foreach ($group in $componentGroups) {
    $sortedBySeverity = @($group.Group | Sort-Object @{ Expression = { Get-SeverityRank -Severity $_.severity }; Descending = $true }, @{ Expression = { $_.source }; Descending = $true })
    $head = $sortedBySeverity | Select-Object -First 1
    $messageHead = @($group.Group | Group-Object message | Sort-Object Count -Descending | Select-Object -First 1)
    $domain = Get-DomainForComponent -Component ([string]$group.Name)
    $actionClass = Get-ActionClassForComponent -Component ([string]$group.Name)

    $componentItems.Add([pscustomobject]@{
            component = [string]$group.Name
            count = [int]$group.Count
            highest_severity = [string]$head.severity
            domain = $domain
            action_class = $actionClass
            representative_message = [string]$messageHead.Name
            latest_source = [string]$head.source
        }) | Out-Null
}

$domainItems = @($componentItems | Group-Object domain | ForEach-Object {
        $components = @($_.Group | Sort-Object count -Descending | Select-Object -ExpandProperty component)
        $maxSeverity = @($_.Group | Sort-Object @{ Expression = { Get-SeverityRank -Severity $_.highest_severity }; Descending = $true } | Select-Object -First 1).highest_severity
        [pscustomobject]@{
            domain = [string]$_.Name
            total_hits = [int](($_.Group | Measure-Object -Property count -Sum).Sum)
            components = $components
            highest_severity = [string]$maxSeverity
        }
    } | Sort-Object total_hits -Descending)

$manualDocs = @(
    @{
        path = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\SYSTEM_HEAVY_AUDIT_AND_CLEANUP_20260314.md"
        note = "Powtarzalny problem: osierocone artefakty runtime i katalogi tymczasowe tworza szum oraz falszywe tropy w audytach."
        domain = "HIGIENA_RUNTIME"
    },
    @{
        path = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\PRELIVE_STATE_MACHINE_AUDIT_20260314.md"
        note = "Powtarzalny problem: raport ma odrozniać realna sprzecznosc od niepelnego montazu operacyjnego, zamiast wrzucac wszystko do jednego worka."
        domain = "SPOJNOSC_FLOTY"
    },
    @{
        path = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\RIGOROUS_AUDIT_17_MICROBOTS_20260316.md"
        note = "Powtarzalny problem: stare pliki koordynatora i stale snapshoty nie sa wiarygodne bez krzyzowej weryfikacji z zywego runtime."
        domain = "SPOJNOSC_FLOTY"
    },
    @{
        path = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\NETWORK_PROTECTION_AUDIT_AND_ADOPTION_20260316.md"
        note = "Powtarzalny problem: infrastruktura i ping musza miec osobny, jawny kontrakt telemetryczny i nie moga mieszac sie z uproszczonymi heurystykami."
        domain = "JAKOSC_WYKONANIA"
    },
    @{
        path = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\TUNING_AGENT_PARITY_AUDIT_20260316.md"
        note = "Powtarzalny problem: brak pelnego parytetu warstw paper/runtime/agent rodzinny wraca jako dlug techniczny i rozjazd miedzy symbolami."
        domain = "STOS_UCZENIA"
    }
)

$manualItems = @($manualDocs | Where-Object { Test-Path -LiteralPath $_.path } | ForEach-Object {
        [pscustomobject]@{
            path = $_.path.Replace($ProjectRoot.TrimEnd('\') + '\', '')
            domain = $_.domain
            note = $_.note
        }
    })

$recommendedSupervisor = [ordered]@{
    tryb_reczny = @{
        command = "RUN\RUN_AUDIT_SUPERVISOR.ps1"
        purpose = "pelny audyt na zadanie, z wymuszeniem wszystkich domen i jednej wspolnej decyzji koncowej"
    }
    tryb_tlo = @{
        command = "RUN\START_AUDIT_SUPERVISOR_BACKGROUND.ps1"
        purpose = "lekka petla stalego nadzoru co kilka minut"
    }
    tryb_trwaly_windows = @{
        command = "RUN\INSTALL_AUDIT_SUPERVISOR_SCHEDULED_TASK.ps1"
        purpose = "start przy logowaniu lub starcie maszyny i dalsze pilnowanie cyklu"
    }
    preferowany_model_pracy = "mieszany: reczny start na zadanie plus stala petla w tle plus trwały start z Harmonogramu zadan"
    gate_levels = @(
        "RAPORTUJ",
        "NAPRAW_W_CYKLU",
        "CZYSZC_AUTOMATYCZNIE",
        "BLOKUJ_ROLLOUT",
        "BLOKUJ_LIVE"
    )
    minimalne_domeny = @(
        "POCHODZENIE_WDROZENIA",
        "SPOJNOSC_FLOTY",
        "HIGIENA_RUNTIME",
        "JAKOSC_WYKONANIA",
        "STOS_UCZENIA",
        "ONNX_I_SPRZEZENIE_ZWROTNE"
    )
}

$analyzedJsonFiles = [int]$sourcesAnalyzed.Count
$totalFindings = [int]$findings.Count
$topRecurringComponents = @($componentItems | Select-Object -First 20)
$topDomains = @($domainItems)
$manualAuditNotes = @($manualItems)
$conclusions = @(
    "Najbardziej powtarzalne problemy sa zwiazane nie z jedna funkcja, tylko z dyscyplina wdrozenia, higiena runtime i petla zwrotna ONNX.",
    "Superwizor audytu musi byc bramka sterujaca, nie tylko kolejnym raportem.",
    "Najpierw trzeba blokowac zla paczke i rozjazd floty, potem czyscic i monitorowac reszte."
)

$report = New-Object System.Collections.Specialized.OrderedDictionary
$report.Add("generated_at_local", (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
$report.Add("generated_at_utc", (Get-Date).ToUniversalTime().ToString("o"))
$report.Add("lookback_days", [int]$LookbackDays)
$report.Add("analyzed_json_files", $analyzedJsonFiles)
$report.Add("total_findings", $totalFindings)
$report.Add("top_recurring_components", $topRecurringComponents)
$report.Add("top_domains", $topDomains)
$report.Add("manual_audit_notes", $manualAuditNotes)
$report.Add("recommended_supervisor", $recommendedSupervisor)
$report.Add("conclusions", $conclusions)

$jsonPath = Join-Path $OpsRoot "audit_supervisor_discovery_latest.json"
$mdPath = Join-Path $OpsRoot "audit_supervisor_discovery_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Rozeznanie Dla Superwizora Audytu")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- lookback_days: {0}" -f $report.lookback_days))
$lines.Add(("- analyzed_json_files: {0}" -f $report.analyzed_json_files))
$lines.Add(("- total_findings: {0}" -f $report.total_findings))
$lines.Add("")
$lines.Add("## Najczestsze Komponenty")
$lines.Add("")
foreach ($item in @($report.top_recurring_components)) {
    $lines.Add(("- {0}: {1}x | najwyzsza_waga={2} | domena={3} | akcja={4}" -f $item.component, $item.count, $item.highest_severity, $item.domain, $item.action_class))
    $lines.Add(("  komunikat: {0}" -f $item.representative_message))
}
$lines.Add("")
$lines.Add("## Domeny")
$lines.Add("")
foreach ($item in @($report.top_domains)) {
    $lines.Add(("- {0}: {1} trafien | najwyzsza_waga={2}" -f $item.domain, $item.total_hits, $item.highest_severity))
    $lines.Add(("  komponenty: {0}" -f ($item.components -join ", ")))
}
$lines.Add("")
$lines.Add("## Notatki Ze Starszych Audytow")
$lines.Add("")
foreach ($item in @($report.manual_audit_notes)) {
    $lines.Add(("- {0} | domena={1}" -f $item.path, $item.domain))
    $lines.Add(("  wniosek: {0}" -f $item.note))
}
$lines.Add("")
$lines.Add("## Rekomendacja Dla Superwizora")
$lines.Add("")
$lines.Add(("- preferowany_model_pracy: {0}" -f $report.recommended_supervisor.preferowany_model_pracy))
$lines.Add(("- tryb_reczny: {0}" -f $report.recommended_supervisor.tryb_reczny.command))
$lines.Add(("- tryb_tlo: {0}" -f $report.recommended_supervisor.tryb_tlo.command))
$lines.Add(("- tryb_trwaly_windows: {0}" -f $report.recommended_supervisor.tryb_trwaly_windows.command))
$lines.Add(("  domeny: {0}" -f ($report.recommended_supervisor.minimalne_domeny -join ", ")))
$lines.Add(("  gate_levels: {0}" -f ($report.recommended_supervisor.gate_levels -join ", ")))

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report
