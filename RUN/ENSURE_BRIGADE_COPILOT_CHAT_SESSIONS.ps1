param(
    [string]$WorkspacePath = "C:\MAKRO_I_MIKRO_BOT"
)

$ErrorActionPreference = "Stop"

function Get-NormalizedPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Path cannot be empty."
    }

    $candidate = $Path.Trim()

    if ($candidate -match '^[A-Za-z]+://') {
        try {
            $candidate = ([uri]$candidate).LocalPath
        }
        catch {
        }
    }

    if ($candidate -match '^/[A-Za-z]:/') {
        $candidate = $candidate.Substring(1)
    }

    $candidate = $candidate -replace '/', '\'

    try {
        if ([System.IO.Path]::IsPathRooted($candidate)) {
            $candidate = [System.IO.Path]::GetFullPath($candidate)
        }
    }
    catch {
    }

    if (Test-Path -LiteralPath $candidate) {
        $candidate = (Get-Item -LiteralPath $candidate).FullName
    }

    return $candidate.TrimEnd('\').ToLowerInvariant()
}

function Get-WorkspaceStorageDir {
    param([string]$WorkspacePath)
    $workspaceRoot = Join-Path $env:APPDATA "Code\User\workspaceStorage"
    $expectedPath = Get-NormalizedPath -Path $WorkspacePath
    $workspaceJsons = Get-ChildItem -Path $workspaceRoot -Recurse -Filter "workspace.json" -File -ErrorAction SilentlyContinue
    foreach ($workspaceJson in $workspaceJsons) {
        try {
            $payload = Get-Content -LiteralPath $workspaceJson.FullName -Raw | ConvertFrom-Json
        } catch {
            continue
        }
        if (-not $payload.folder) {
            continue
        }
        try {
            $candidatePath = ([uri]$payload.folder).LocalPath
        } catch {
            continue
        }
        if ([string]::IsNullOrWhiteSpace($candidatePath)) {
            continue
        }
        if ((Get-NormalizedPath -Path $candidatePath) -eq $expectedPath) {
            return $workspaceJson.Directory.FullName
        }
    }
    throw "Nie znaleziono workspaceStorage dla '$WorkspacePath'."
}

function Get-SessionTitle {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path -TotalCount 10 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        try {
            $obj = $line | ConvertFrom-Json
        } catch {
            continue
        }
        if ($obj.kind -eq 1 -and $obj.k -and $obj.k.Count -eq 1 -and $obj.k[0] -eq "customTitle") {
            return [string]$obj.v
        }
    }
    try {
        $obj = ($lines | Select-Object -First 1) | ConvertFrom-Json
        if ($obj.v.customTitle) {
            return [string]$obj.v.customTitle
        }
    } catch {
    }
    return ""
}

function Get-SessionMessageText {
    param([string]$Path)
    $firstLine = Get-Content -LiteralPath $Path -TotalCount 1 -ErrorAction SilentlyContinue
    if (-not $firstLine) {
        return ""
    }
    try {
        $obj = $firstLine | ConvertFrom-Json
        if ($obj.v.requests -and $obj.v.requests.Count -gt 0) {
            return [string]$obj.v.requests[0].message.text
        }
    } catch {
    }
    return ""
}

function New-SessionLine0 {
    param(
        [string]$SessionId,
        [string]$AccountLabel
    )
    return @{
        kind = 0
        v = @{
            version = 3
            creationDate = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            initialLocation = "panel"
            responderUsername = "GitHub Copilot"
            sessionId = $SessionId
            hasPendingEdits = $false
            requests = @()
            pendingRequests = @()
            inputState = @{
                attachments = @()
                mode = @{
                    id = "agent"
                    kind = "agent"
                }
                selectedModel = @{
                    identifier = "copilot/gpt-5.4"
                    metadata = @{
                        extension = @{
                            value = "GitHub.copilot-chat"
                            _lower = "github.copilot-chat"
                        }
                        id = "gpt-5.4"
                        vendor = "copilot"
                        name = "GPT-5.4"
                        family = "gpt-5.4"
                        tooltip = "Szybkosc Niezawodny model GPT-4 odpowiedni do szerokiego zakresu zadan kodowania i ogolnych. jest liczona jako 1x."
                        version = "gpt-5.4"
                        multiplier = "1x"
                        multiplierNumeric = 1
                        maxInputTokens = 271805
                        maxOutputTokens = 128000
                        auth = @{
                            providerLabel = "GitHub Copilot Chat"
                            accountLabel = $AccountLabel
                        }
                        isDefaultForLocation = @{
                            panel = $false
                            terminal = $false
                            notebook = $false
                            editor = $false
                        }
                        isUserSelectable = $true
                        configurationSchema = @{
                            properties = @{
                                reasoningEffort = @{
                                    type = "string"
                                    title = "Naklad pracy w zakresie myslenia"
                                    enum = @("low", "medium", "high", "xhigh")
                                    enumItemLabels = @("Low", "Medium", "High", "Xhigh")
                                    enumDescriptions = @(
                                        "Szybsze odpowiedzi przy mniejszym wnioskowaniu",
                                        "Zrownowazone wnioskowanie i szybkosc",
                                        "Maksymalna glebokosc wnioskowania",
                                        "xhigh"
                                    )
                                    default = "xhigh"
                                    group = "navigation"
                                }
                            }
                        }
                        modelPickerCategory = @{
                            label = "Modele Premium"
                            order = 1
                        }
                        capabilities = @{
                            vision = $true
                            toolCalling = $true
                            agentMode = $true
                        }
                    }
                }
                inputText = ""
                selections = @(
                    @{
                        startLineNumber = 1
                        startColumn = 1
                        endLineNumber = 1
                        endColumn = 1
                        selectionStartLineNumber = 1
                        selectionStartColumn = 1
                        positionLineNumber = 1
                        positionColumn = 1
                    }
                )
                contrib = @{
                    chatDynamicVariableModel = @()
                }
            }
        }
    }
}

function New-SessionLine1 {
    param([string]$Title)
    return @{
        kind = 1
        k = @("customTitle")
        v = $Title
    }
}

$storageDir = Get-WorkspaceStorageDir -WorkspacePath $WorkspacePath
$chatSessionsDir = Join-Path $storageDir "chatSessions"
$opsDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"

New-Item -ItemType Directory -Path $chatSessionsDir -Force | Out-Null
New-Item -ItemType Directory -Path $opsDir -Force | Out-Null

$backupDir = Join-Path $chatSessionsDir ("brigade_session_backup_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

$existingFiles = @(Get-ChildItem -LiteralPath $chatSessionsDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue)
$dispatcherTitle = "BRYGADY - DYSPOZYTORNIA [GPT-5.4 XHIGH]"

$registryPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\orchestrator_brigades_registry_v1.json"
$registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
$accountLabel = "skitela"

$sessionSpecs = @(
    [pscustomobject]@{
        title = $dispatcherTitle
        brigade_id = ""
        prompt_path = "BRYGADY/00_PANEL_STEROWANIA_BRYGAD.md"
        registry_chat_name = $dispatcherTitle
        existing_match = "dispatcher"
    },
    [pscustomobject]@{
        title = "BRYGADA ML I MIGRACJA MT5 [GPT-5.4 XHIGH]"
        brigade_id = "ml_migracja_mt5"
        prompt_path = ".github/prompts/wejdz-brygada-ml-migracja-mt5.prompt.md"
        registry_chat_name = "BRYGADA ML I MIGRACJA MT5 [GPT-5.4 XHIGH]"
        existing_match = ""
    },
    [pscustomobject]@{
        title = "BRYGADA AUDYT I CLEANUP [GPT-5.4 XHIGH]"
        brigade_id = "audyt_cleanup"
        prompt_path = ".github/prompts/wejdz-brygada-audyt-cleanup.prompt.md"
        registry_chat_name = "BRYGADA AUDYT I CLEANUP [GPT-5.4 XHIGH]"
        existing_match = ""
    },
    [pscustomobject]@{
        title = "BRYGADA WDROZENIA MT5 [GPT-5.4 XHIGH]"
        brigade_id = "wdrozenia_mt5"
        prompt_path = ".github/prompts/wejdz-brygada-wdrozenia-mt5.prompt.md"
        registry_chat_name = "BRYGADA WDROZENIA MT5 [GPT-5.4 XHIGH]"
        existing_match = ""
    },
    [pscustomobject]@{
        title = "BRYGADA ROZWOJ KODU [GPT-5.4 XHIGH]"
        brigade_id = "rozwoj_kodu"
        prompt_path = ".github/prompts/wejdz-brygada-rozwoj-kodu.prompt.md"
        registry_chat_name = "BRYGADA ROZWOJ KODU [GPT-5.4 XHIGH]"
        existing_match = ""
    },
    [pscustomobject]@{
        title = "BRYGADA ARCHITEKTURA I INNOWACJE [GPT-5.4 XHIGH]"
        brigade_id = "architektura_innowacje"
        prompt_path = ".github/prompts/wejdz-brygada-architektura-innowacje.prompt.md"
        registry_chat_name = "BRYGADA ARCHITEKTURA I INNOWACJE [GPT-5.4 XHIGH]"
        existing_match = ""
    },
    [pscustomobject]@{
        title = "BRYGADA NADZOR UCZENIA I GO-NO-GO [GPT-5.4 XHIGH]"
        brigade_id = "nadzor_uczenia_rolloutu"
        prompt_path = ".github/prompts/wejdz-brygada-nadzor-uczenia-gonogo.prompt.md"
        registry_chat_name = "BRYGADA NADZOR UCZENIA I GO-NO-GO [GPT-5.4 XHIGH]"
        existing_match = ""
    }
)

$created = @()
$reused = @()
$retitled = @()

foreach ($spec in $sessionSpecs) {
    $existingByTitle = $existingFiles | Where-Object { (Get-SessionTitle -Path $_.FullName) -eq $spec.title } | Select-Object -First 1
    if ($existingByTitle) {
        $reused += [pscustomobject]@{
            title = $spec.title
            file = $existingByTitle.FullName
            prompt_path = $spec.prompt_path
        }
        continue
    }

    $dispatcherCandidate = $null
    if ($spec.existing_match -eq "dispatcher") {
        $dispatcherCandidate = $existingFiles | Where-Object {
            ((Get-SessionTitle -Path $_.FullName) -eq "BRYGADA") -or ((Get-SessionMessageText -Path $_.FullName) -eq "BRYGADA")
        } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }

    if ($dispatcherCandidate) {
        Copy-Item -LiteralPath $dispatcherCandidate.FullName -Destination (Join-Path $backupDir $dispatcherCandidate.Name) -Force
        $lines = Get-Content -LiteralPath $dispatcherCandidate.FullName
        $titleLineIndex = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            try {
                $obj = $lines[$i] | ConvertFrom-Json
            } catch {
                continue
            }
            if ($obj.kind -eq 1 -and $obj.k -and $obj.k.Count -eq 1 -and $obj.k[0] -eq "customTitle") {
                $titleLineIndex = $i
                break
            }
        }
        $newTitleLine = (New-SessionLine1 -Title $spec.title) | ConvertTo-Json -Compress -Depth 20
        if ($titleLineIndex -ge 0) {
            $lines[$titleLineIndex] = $newTitleLine
        } else {
            $lines = @($newTitleLine) + $lines
        }
        Set-Content -LiteralPath $dispatcherCandidate.FullName -Value $lines -Encoding UTF8
        $retitled += [pscustomobject]@{
            title = $spec.title
            file = $dispatcherCandidate.FullName
            prompt_path = $spec.prompt_path
        }
        continue
    }

    $sessionId = [guid]::NewGuid().ToString()
    $filePath = Join-Path $chatSessionsDir ($sessionId + ".jsonl")
    $line0 = (New-SessionLine0 -SessionId $sessionId -AccountLabel $accountLabel) | ConvertTo-Json -Compress -Depth 50
    $line1 = (New-SessionLine1 -Title $spec.title) | ConvertTo-Json -Compress -Depth 20
    Set-Content -LiteralPath $filePath -Value @($line0, $line1) -Encoding UTF8
    $created += [pscustomobject]@{
        title = $spec.title
        file = $filePath
        prompt_path = $spec.prompt_path
    }
}

foreach ($brigade in $registry.brigades) {
    $match = $sessionSpecs | Where-Object { $_.brigade_id -eq $brigade.brigade_id } | Select-Object -First 1
    if ($match) {
        $brigade.chat_name = $match.registry_chat_name
    }
}

$registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding UTF8

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    workspace_path = $WorkspacePath
    workspace_storage_dir = $storageDir
    chat_sessions_dir = $chatSessionsDir
    backup_dir = $backupDir
    dispatcher_title = $dispatcherTitle
    created_count = $created.Count
    reused_count = $reused.Count
    retitled_count = $retitled.Count
    created = $created
    reused = $reused
    retitled = $retitled
    note = "Sesje sa ustawione jako agent plus GPT-5.4. Pole reasoningEffort nie jest jawnie przechowywane jako aktywna wartosc w plaintext storage Copilota, wiec ustawiono session-local default xhigh w metadanych modelu."
}

$jsonReportPath = Join-Path $opsDir "brigade_copilot_chat_sessions_latest.json"
$mdReportPath = Join-Path $opsDir "brigade_copilot_chat_sessions_latest.md"

$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonReportPath -Encoding UTF8

$md = @()
$md += "# Brigade Copilot Chat Sessions"
$md += ""
$md += "- Generated at: $($report.generated_at)"
$md += "- Workspace: $($report.workspace_path)"
$md += "- Storage: $($report.workspace_storage_dir)"
$md += "- Created: $($report.created_count)"
$md += "- Reused: $($report.reused_count)"
$md += "- Retitled: $($report.retitled_count)"
$md += ""
$md += "## Created"
foreach ($item in $created) {
    $md += "- $($item.title) -> $($item.file)"
}
$md += ""
$md += "## Reused"
foreach ($item in $reused) {
    $md += "- $($item.title) -> $($item.file)"
}
$md += ""
$md += "## Retitled"
foreach ($item in $retitled) {
    $md += "- $($item.title) -> $($item.file)"
}
$md += ""
$md += "## Note"
$md += "- $($report.note)"
$md | Set-Content -LiteralPath $mdReportPath -Encoding UTF8

Write-Host "BRIGADE COPILOT CHAT SESSIONS READY"
Write-Host ""
Write-Host "Workspace storage: $storageDir"
Write-Host "Created: $($created.Count)"
Write-Host "Reused: $($reused.Count)"
Write-Host "Retitled: $($retitled.Count)"
Write-Host "Report: $jsonReportPath"
