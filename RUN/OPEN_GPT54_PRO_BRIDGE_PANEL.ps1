param(
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ConfigPath = Join-Path $RepoRoot "TOOLS\orchestrator\orchestrator_config.json"

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Missing orchestrator config: $ConfigPath"
}

$Config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$MailboxDir = [string]$Config.mailbox_dir
$ChatUrl = [string]$Config.chat_url
$RegistryPath = Join-Path $RepoRoot "CONFIG\orchestrator_brigades_registry_v1.json"
$BrigadeRegistry = if (Test-Path -LiteralPath $RegistryPath) {
    Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
}
else {
    $null
}
$BrigadeRows = @()
if ($null -ne $BrigadeRegistry -and $BrigadeRegistry.PSObject.Properties.Name -contains "brigades") {
    $BrigadeRows = @(
        $BrigadeRegistry.brigades | ForEach-Object {
            [pscustomobject]@{
                brigade_id = [string]$_.brigade_id
                actor_id = [string]$_.actor_id
                chat_name = [string]$_.chat_name
                display_name = "{0} | {1}" -f [string]$_.brigade_id, [string]$_.chat_name
            }
        }
    )
}

$ScriptMap = [ordered]@{
    start_autoflow = Join-Path $RepoRoot "RUN\START_ORCHESTRATOR_AUTOFLOW.ps1"
    start_orchestrator = Join-Path $RepoRoot "RUN\START_CHATGPT_CODEX_ORCHESTRATOR.ps1"
    queue_file = Join-Path $RepoRoot "RUN\QUEUE_FILE_FOR_GPT54_PRO.ps1"
    queue_text = Join-Path $RepoRoot "RUN\QUEUE_TEXT_FOR_GPT54_PRO.ps1"
    build_from_report = Join-Path $RepoRoot "RUN\BUILD_CODEX_REQUEST_FROM_REPORT.ps1"
    import_manual = Join-Path $RepoRoot "RUN\IMPORT_GPT54_MANUAL_RESPONSE.ps1"
    import_ready = Join-Path $RepoRoot "RUN\IMPORT_GPT54_READY_RESPONSE.ps1"
    validate_ready = Join-Path $RepoRoot "RUN\VALIDATE_GPT54_READY_RESPONSE.ps1"
    create_shortcut = Join-Path $RepoRoot "RUN\CREATE_GPT54_PRO_BRIDGE_SHORTCUT.ps1"
    status = Join-Path $RepoRoot "RUN\GET_ORCHESTRATOR_STATUS.ps1"
    notes = Join-Path $RepoRoot "RUN\GET_ORCHESTRATOR_NOTES.ps1"
    brigades = Join-Path $RepoRoot "RUN\GET_ORCHESTRATOR_BRIGADES.ps1"
    taskboard = Join-Path $RepoRoot "RUN\GET_ORCHESTRATOR_TASKBOARD.ps1"
    brigade_state = Join-Path $RepoRoot "RUN\SET_ORCHESTRATOR_BRIGADE_STATE.ps1"
    brigade_autostart = Join-Path $RepoRoot "RUN\START_ORCHESTRATOR_BRIGADE_AUTOSTART.ps1"
}

foreach ($item in $ScriptMap.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $item.Value)) {
        throw "Missing bridge script: $($item.Value)"
    }
}

function Get-ShellPath {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -ne $pwsh -and -not [string]::IsNullOrWhiteSpace($pwsh.Source)) {
        return $pwsh.Source
    }
    return "powershell.exe"
}

$ShellPath = Get-ShellPath

if ($SelfTest) {
    [pscustomobject]@{
        repo_root = $RepoRoot
        shell_path = $ShellPath
        mailbox_dir = $MailboxDir
        chat_url = $ChatUrl
        panel_script = $PSCommandPath
        script_count = @($ScriptMap.Keys).Count
    } | Format-List
    return
}

function Invoke-BridgeScript {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    $output = & $ShellPath -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw ($output.Trim())
    }
    return $output.Trim()
}

function Start-BridgeScriptDetached {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    Start-Process -FilePath $ShellPath -ArgumentList (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath) + $Arguments) -WorkingDirectory $RepoRoot -WindowStyle Hidden | Out-Null
}

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "GPT-5.4 Pro Bridge Panel"
$Form.Size = New-Object System.Drawing.Size(1180, 1120)
$Form.StartPosition = "CenterScreen"
$Form.MinimumSize = New-Object System.Drawing.Size(1040, 980)

$TitleLabel = New-Object System.Windows.Forms.Label
$TitleLabel.Text = "Jedno miejsce do mostu GPT-5.4 Pro i warstwy komunikacji"
$TitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
$TitleLabel.AutoSize = $true
$TitleLabel.Location = New-Object System.Drawing.Point(20, 16)
$Form.Controls.Add($TitleLabel)

$HintLabel = New-Object System.Windows.Forms.Label
$HintLabel.Text = "Zaczynasz od przycisku startu mostu. Z tego samego panelu mozesz wyslac tresc, zbudowac request z raportu, sprawdzic gotowa odpowiedz, zwalidowac ja i zarchiwizowac bez terminala. Panel umie tez pokazac status brygad oraz ustawic pauze lub wznowienie wybranego lane'u."
$HintLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$HintLabel.Size = New-Object System.Drawing.Size(1110, 58)
$HintLabel.Location = New-Object System.Drawing.Point(20, 52)
$Form.Controls.Add($HintLabel)

$MetaLabel = New-Object System.Windows.Forms.Label
$MetaLabel.Text = "Mailbox: $MailboxDir`r`nWatek GPT-5.4 Pro: $ChatUrl"
$MetaLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$MetaLabel.Size = New-Object System.Drawing.Size(1110, 40)
$MetaLabel.Location = New-Object System.Drawing.Point(20, 108)
$Form.Controls.Add($MetaLabel)

$RequestTitleLabel = New-Object System.Windows.Forms.Label
$RequestTitleLabel.Text = "Tytul requestu"
$RequestTitleLabel.AutoSize = $true
$RequestTitleLabel.Location = New-Object System.Drawing.Point(20, 158)
$Form.Controls.Add($RequestTitleLabel)

$RequestTitleBox = New-Object System.Windows.Forms.TextBox
$RequestTitleBox.Location = New-Object System.Drawing.Point(20, 181)
$RequestTitleBox.Size = New-Object System.Drawing.Size(470, 28)
$RequestTitleBox.Text = "Analiza GPT-5.4 Pro"
$Form.Controls.Add($RequestTitleBox)

$PhaseLabel = New-Object System.Windows.Forms.Label
$PhaseLabel.Text = "Faza raportu"
$PhaseLabel.AutoSize = $true
$PhaseLabel.Location = New-Object System.Drawing.Point(520, 158)
$Form.Controls.Add($PhaseLabel)

$PhaseBox = New-Object System.Windows.Forms.ComboBox
$PhaseBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$PhaseBox.Location = New-Object System.Drawing.Point(520, 181)
$PhaseBox.Size = New-Object System.Drawing.Size(170, 28)
[void]$PhaseBox.Items.AddRange(@("analysis", "review", "implementation", "validation", "rollback", "concept"))
$PhaseBox.SelectedItem = "analysis"
$Form.Controls.Add($PhaseBox)

$StatusSummaryLabel = New-Object System.Windows.Forms.Label
$StatusSummaryLabel.Text = "Status: jeszcze nie odswiezono"
$StatusSummaryLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$StatusSummaryLabel.Size = New-Object System.Drawing.Size(420, 28)
$StatusSummaryLabel.Location = New-Object System.Drawing.Point(720, 181)
$Form.Controls.Add($StatusSummaryLabel)

$BrigadeLabel = New-Object System.Windows.Forms.Label
$BrigadeLabel.Text = "Wybrana brygada"
$BrigadeLabel.AutoSize = $true
$BrigadeLabel.Location = New-Object System.Drawing.Point(20, 226)
$Form.Controls.Add($BrigadeLabel)

$BrigadeBox = New-Object System.Windows.Forms.ComboBox
$BrigadeBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$BrigadeBox.Location = New-Object System.Drawing.Point(20, 249)
$BrigadeBox.Size = New-Object System.Drawing.Size(470, 28)
$BrigadeBox.DisplayMember = "display_name"
foreach ($brigadeRow in $BrigadeRows) {
    [void]$BrigadeBox.Items.Add($brigadeRow)
}
if ($BrigadeBox.Items.Count -gt 0) {
    $BrigadeBox.SelectedIndex = 0
}
$Form.Controls.Add($BrigadeBox)

$BrigadeMetaLabel = New-Object System.Windows.Forms.Label
$BrigadeMetaLabel.Text = "Actor: brak | Chat: brak"
$BrigadeMetaLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$BrigadeMetaLabel.Size = New-Object System.Drawing.Size(620, 36)
$BrigadeMetaLabel.Location = New-Object System.Drawing.Point(510, 246)
$Form.Controls.Add($BrigadeMetaLabel)

$BrigadeActionsPanel = New-Object System.Windows.Forms.TableLayoutPanel
$BrigadeActionsPanel.Location = New-Object System.Drawing.Point(20, 292)
$BrigadeActionsPanel.Size = New-Object System.Drawing.Size(1110, 64)
$BrigadeActionsPanel.ColumnCount = 5
$BrigadeActionsPanel.RowCount = 1
$BrigadeActionsPanel.CellBorderStyle = [System.Windows.Forms.TableLayoutPanelCellBorderStyle]::Single
$BrigadeActionsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 20)))
$BrigadeActionsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 20)))
$BrigadeActionsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 20)))
$BrigadeActionsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 20)))
$BrigadeActionsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 20)))
$BrigadeActionsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$Form.Controls.Add($BrigadeActionsPanel)

$ActionsPanel = New-Object System.Windows.Forms.TableLayoutPanel
$ActionsPanel.Location = New-Object System.Drawing.Point(20, 375)
$ActionsPanel.Size = New-Object System.Drawing.Size(1110, 390)
$ActionsPanel.ColumnCount = 3
$ActionsPanel.RowCount = 5
$ActionsPanel.CellBorderStyle = [System.Windows.Forms.TableLayoutPanelCellBorderStyle]::Single
$ActionsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.33)))
$ActionsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.33)))
$ActionsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.34)))
$ActionsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 20)))
$ActionsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 20)))
$ActionsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 20)))
$ActionsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 20)))
$ActionsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 20)))
$Form.Controls.Add($ActionsPanel)

function New-BridgeButton {
    param([string]$Text)

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Dock = [System.Windows.Forms.DockStyle]::Fill
    $button.Margin = New-Object System.Windows.Forms.Padding(8)
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    return $button
}

$OutputBox = New-Object System.Windows.Forms.TextBox
$OutputBox.Location = New-Object System.Drawing.Point(20, 790)
$OutputBox.Size = New-Object System.Drawing.Size(1110, 270)
$OutputBox.Multiline = $true
$OutputBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$OutputBox.ReadOnly = $true
$OutputBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$Form.Controls.Add($OutputBox)

function Get-SelectedBrigade {
    if ($null -eq $BrigadeBox.SelectedItem) {
        return $null
    }

    return $BrigadeBox.SelectedItem
}

function Update-BrigadeMeta {
    $selectedBrigade = Get-SelectedBrigade
    if ($null -eq $selectedBrigade) {
        $BrigadeMetaLabel.Text = "Actor: brak | Chat: brak"
        return
    }

    $BrigadeMetaLabel.Text = "Actor: {0} | Chat: {1}" -f [string]$selectedBrigade.actor_id, [string]$selectedBrigade.chat_name
}

function Write-PanelLog {
    param([string]$Text)

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $OutputBox.AppendText("[$stamp] $Text`r`n")
}

function Append-CommandOutput {
    param([string]$Text)

    if (-not [string]::IsNullOrWhiteSpace($Text)) {
        $OutputBox.AppendText($Text + "`r`n")
    }
}

function Get-RequestTitle {
    $title = $RequestTitleBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($title)) {
        return "Analiza GPT-5.4 Pro"
    }
    return $title
}

function Get-SelectedPhase {
    if ($null -eq $PhaseBox.SelectedItem) {
        return "analysis"
    }
    return [string]$PhaseBox.SelectedItem
}

function Update-StatusSummary {
    param([string]$StatusText)

    $pending = "?"
    $ready = "?"
    $notes = "?"
    $pendingTasks = "?"
    $activeTasks = "?"
    if ($StatusText -match 'pending_requests\s*:\s*(\d+)') {
        $pending = $Matches[1]
    }
    if ($StatusText -match 'ready_responses\s*:\s*(\d+)') {
        $ready = $Matches[1]
    }
    if ($StatusText -match 'inbox_notes\s*:\s*(\d+)') {
        $notes = $Matches[1]
    }
    if ($StatusText -match 'pending_parallel_tasks\s*:\s*(\d+)') {
        $pendingTasks = $Matches[1]
    }
    if ($StatusText -match 'active_parallel_tasks\s*:\s*(\d+)') {
        $activeTasks = $Matches[1]
    }
    $StatusSummaryLabel.Text = "Status: pending=$pending | ready=$ready | notes=$notes | tasks=$pendingTasks/$activeTasks"
}

function Refresh-BridgeStatus {
    try {
        $statusText = Invoke-BridgeScript -ScriptPath $ScriptMap.status -Arguments @("-MailboxDir", $MailboxDir)
        Update-StatusSummary -StatusText $statusText
        Write-PanelLog "Status mostu odswiezony."
        Append-CommandOutput -Text $statusText
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad statusu", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad odswiezenia statusu: $($_.Exception.Message)"
    }
}

$ButtonStartBridge = New-BridgeButton -Text "1. Start most i otworz GPT-5.4 Pro"
$ButtonOpenThread = New-BridgeButton -Text "2. Otworz sam watek GPT-5.4 Pro"
$ButtonQueueClipboard = New-BridgeButton -Text "3. Wyslij schowek do warstwy komunikacji"
$ButtonQueueFile = New-BridgeButton -Text "4. Wyslij plik do warstwy komunikacji"
$ButtonBuildFromReport = New-BridgeButton -Text "5. Zbuduj request z raportu"
$ButtonShowReady = New-BridgeButton -Text "6. Pokaz najnowsza gotowa odpowiedz"
$ButtonValidateReady = New-BridgeButton -Text "7. Waliduj najnowsza gotowa odpowiedz"
$ButtonArchiveReady = New-BridgeButton -Text "8. Archiwizuj najnowsza gotowa odpowiedz"
$ButtonImportClipboard = New-BridgeButton -Text "9. Importuj odpowiedz ze schowka"
$ButtonImportFile = New-BridgeButton -Text "10. Importuj odpowiedz z pliku"
$ButtonStatus = New-BridgeButton -Text "11. Pokaz status mostu"
$ButtonNotes = New-BridgeButton -Text "12. Pokaz wspolne notatki"
$ButtonCreateShortcut = New-BridgeButton -Text "13. Utworz skrot na pulpicie"
$ButtonOpenMailbox = New-BridgeButton -Text "14. Otworz folder mailboxa"
$ButtonBrigadeStatus = New-BridgeButton -Text "15. Szczegoly brygady"
$ButtonBrigadeTaskboard = New-BridgeButton -Text "16. Taskboard brygad"
$ButtonPauseBrigade = New-BridgeButton -Text "17. Pauza brygady"
$ButtonResumeBrigade = New-BridgeButton -Text "18. Wznow brygade"
$ButtonAutostartBrigades = New-BridgeButton -Text "19. Autostart brygad"

$BrigadeActionsPanel.Controls.Add($ButtonBrigadeStatus, 0, 0)
$BrigadeActionsPanel.Controls.Add($ButtonBrigadeTaskboard, 1, 0)
$BrigadeActionsPanel.Controls.Add($ButtonPauseBrigade, 2, 0)
$BrigadeActionsPanel.Controls.Add($ButtonResumeBrigade, 3, 0)
$BrigadeActionsPanel.Controls.Add($ButtonAutostartBrigades, 4, 0)

$ActionsPanel.Controls.Add($ButtonStartBridge, 0, 0)
$ActionsPanel.Controls.Add($ButtonOpenThread, 1, 0)
$ActionsPanel.Controls.Add($ButtonQueueClipboard, 2, 0)
$ActionsPanel.Controls.Add($ButtonQueueFile, 0, 1)
$ActionsPanel.Controls.Add($ButtonBuildFromReport, 1, 1)
$ActionsPanel.Controls.Add($ButtonShowReady, 2, 1)
$ActionsPanel.Controls.Add($ButtonValidateReady, 0, 2)
$ActionsPanel.Controls.Add($ButtonArchiveReady, 1, 2)
$ActionsPanel.Controls.Add($ButtonImportClipboard, 2, 2)
$ActionsPanel.Controls.Add($ButtonImportFile, 0, 3)
$ActionsPanel.Controls.Add($ButtonStatus, 1, 3)
$ActionsPanel.Controls.Add($ButtonNotes, 2, 3)
$ActionsPanel.Controls.Add($ButtonCreateShortcut, 0, 4)
$ActionsPanel.Controls.Add($ButtonOpenMailbox, 1, 4)

$BrigadeBox.Add_SelectedIndexChanged({
    Update-BrigadeMeta
})

$ButtonStartBridge.Add_Click({
    try {
        Start-BridgeScriptDetached -ScriptPath $ScriptMap.start_autoflow -Arguments @("-RepoRoot", $RepoRoot)
        Write-PanelLog "Uruchomiono autoflow mostu w tle."
        Start-Sleep -Seconds 2
        Refresh-BridgeStatus
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad startu mostu", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad startu mostu: $($_.Exception.Message)"
    }
})

$ButtonOpenThread.Add_Click({
    try {
        Start-BridgeScriptDetached -ScriptPath $ScriptMap.start_orchestrator -Arguments @("-Mode", "open-chat")
        Write-PanelLog "Otwarto dedykowany watek GPT-5.4 Pro."
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad otwarcia watku", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad otwarcia watku: $($_.Exception.Message)"
    }
})

$ButtonQueueClipboard.Add_Click({
    try {
        if (-not [System.Windows.Forms.Clipboard]::ContainsText()) {
            throw "Schowek nie zawiera tekstu."
        }
        $title = Get-RequestTitle
        $result = Invoke-BridgeScript -ScriptPath $ScriptMap.queue_text -Arguments @("-MailboxDir", $MailboxDir, "-FromClipboard", "-Title", $title)
        Write-PanelLog "Schowek zostal wyslany do warstwy komunikacji."
        Append-CommandOutput -Text $result
        Refresh-BridgeStatus
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad wysylki ze schowka", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad wysylki ze schowka: $($_.Exception.Message)"
    }
})

$ButtonQueueFile.Add_Click({
    try {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.InitialDirectory = $RepoRoot
        $dialog.Filter = "Markdown and text|*.md;*.txt;*.json;*.ps1;*.py;*.mq5|All files|*.*"
        $dialog.Title = "Wybierz plik do wyslania do GPT-5.4 Pro"
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        $title = Get-RequestTitle
        $result = Invoke-BridgeScript -ScriptPath $ScriptMap.queue_file -Arguments @("-MailboxDir", $MailboxDir, "-SourcePath", $dialog.FileName, "-Title", $title)
        Write-PanelLog ("Plik wyslany do warstwy komunikacji: {0}" -f $dialog.FileName)
        Append-CommandOutput -Text $result
        Refresh-BridgeStatus
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad wysylki pliku", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad wysylki pliku: $($_.Exception.Message)"
    }
})

$ButtonBuildFromReport.Add_Click({
    try {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.InitialDirectory = $RepoRoot
        $dialog.Filter = "Reports|*.md;*.txt|All files|*.*"
        $dialog.Title = "Wybierz raport do zbudowania requestu"
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        $title = Get-RequestTitle
        $phase = Get-SelectedPhase
        $result = Invoke-BridgeScript -ScriptPath $ScriptMap.build_from_report -Arguments @("-MailboxDir", $MailboxDir, "-ReportPath", $dialog.FileName, "-Title", $title, "-Phase", $phase, "-RepoRoot", $RepoRoot)
        Write-PanelLog ("Zbudowano request z raportu: {0}" -f $dialog.FileName)
        Append-CommandOutput -Text $result
        Refresh-BridgeStatus
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad budowy requestu z raportu", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad budowy requestu z raportu: $($_.Exception.Message)"
    }
})

$ButtonShowReady.Add_Click({
    try {
        $result = Invoke-BridgeScript -ScriptPath $ScriptMap.import_ready -Arguments @("-MailboxDir", $MailboxDir, "-ShowContent")
        Write-PanelLog "Pokazano najnowsza gotowa odpowiedz."
        Append-CommandOutput -Text $result
        Refresh-BridgeStatus
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad odczytu gotowej odpowiedzi", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad odczytu gotowej odpowiedzi: $($_.Exception.Message)"
    }
})

$ButtonValidateReady.Add_Click({
    try {
        $result = Invoke-BridgeScript -ScriptPath $ScriptMap.validate_ready -Arguments @("-MailboxDir", $MailboxDir)
        Write-PanelLog "Zweryfikowano najnowsza gotowa odpowiedz."
        Append-CommandOutput -Text $result
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad walidacji odpowiedzi", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad walidacji odpowiedzi: $($_.Exception.Message)"
    }
})

$ButtonArchiveReady.Add_Click({
    try {
        $result = Invoke-BridgeScript -ScriptPath $ScriptMap.import_ready -Arguments @("-MailboxDir", $MailboxDir, "-MarkConsumed")
        Write-PanelLog "Najnowsza gotowa odpowiedz zostala zarchiwizowana do consumed."
        Append-CommandOutput -Text $result
        Refresh-BridgeStatus
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad archiwizacji odpowiedzi", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad archiwizacji odpowiedzi: $($_.Exception.Message)"
    }
})

$ButtonImportClipboard.Add_Click({
    try {
        if (-not [System.Windows.Forms.Clipboard]::ContainsText()) {
            throw "Schowek nie zawiera tekstu odpowiedzi."
        }
        $result = Invoke-BridgeScript -ScriptPath $ScriptMap.import_manual -Arguments @("-MailboxDir", $MailboxDir, "-FromClipboard")
        Write-PanelLog "Odpowiedz ze schowka zaimportowana do mostu."
        Append-CommandOutput -Text $result
        Refresh-BridgeStatus
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad importu ze schowka", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad importu ze schowka: $($_.Exception.Message)"
    }
})

$ButtonImportFile.Add_Click({
    try {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.InitialDirectory = $RepoRoot
        $dialog.Filter = "Markdown and text|*.md;*.txt|All files|*.*"
        $dialog.Title = "Wybierz plik z odpowiedzia GPT-5.4 Pro"
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        $result = Invoke-BridgeScript -ScriptPath $ScriptMap.import_manual -Arguments @("-MailboxDir", $MailboxDir, "-ResponsePath", $dialog.FileName)
        Write-PanelLog ("Zaimportowano odpowiedz z pliku: {0}" -f $dialog.FileName)
        Append-CommandOutput -Text $result
        Refresh-BridgeStatus
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad importu z pliku", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad importu z pliku: $($_.Exception.Message)"
    }
})

$ButtonStatus.Add_Click({
    Refresh-BridgeStatus
})

$ButtonNotes.Add_Click({
    try {
        $notesText = Invoke-BridgeScript -ScriptPath $ScriptMap.notes -Arguments @("-MailboxDir", $MailboxDir, "-Limit", "10")
        Write-PanelLog "Odczytano wspolne notatki."
        Append-CommandOutput -Text $notesText
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad odczytu notatek", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad odczytu notatek: $($_.Exception.Message)"
    }
})

$ButtonCreateShortcut.Add_Click({
    try {
        $result = Invoke-BridgeScript -ScriptPath $ScriptMap.create_shortcut -Arguments @("-RepoRoot", $RepoRoot)
        Write-PanelLog "Utworzono lub odswiezono skrot pulpitu dla mostu."
        Append-CommandOutput -Text $result
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad tworzenia skrotu", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad tworzenia skrotu: $($_.Exception.Message)"
    }
})

$ButtonOpenMailbox.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $MailboxDir)) {
            New-Item -ItemType Directory -Force -Path $MailboxDir | Out-Null
        }
        Start-Process -FilePath "explorer.exe" -ArgumentList $MailboxDir | Out-Null
        Write-PanelLog "Otwarto folder mailboxa."
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad otwarcia mailboxa", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad otwarcia mailboxa: $($_.Exception.Message)"
    }
})

$ButtonBrigadeStatus.Add_Click({
    try {
        $selectedBrigade = Get-SelectedBrigade
        if ($null -eq $selectedBrigade) {
            throw "Wybierz brygade."
        }
        $result = Invoke-BridgeScript -ScriptPath $ScriptMap.brigades -Arguments @("-BrigadeId", [string]$selectedBrigade.brigade_id)
        Write-PanelLog ("Pokazano szczegoly brygady: {0}" -f [string]$selectedBrigade.brigade_id)
        Append-CommandOutput -Text $result
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad odczytu brygady", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad odczytu brygady: $($_.Exception.Message)"
    }
})

$ButtonBrigadeTaskboard.Add_Click({
    try {
        $result = Invoke-BridgeScript -ScriptPath $ScriptMap.taskboard -Arguments @("-MailboxDir", $MailboxDir, "-ByBrigade")
        Write-PanelLog "Pokazano taskboard brygad."
        Append-CommandOutput -Text $result
        Refresh-BridgeStatus
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad taskboardu brygad", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad taskboardu brygad: $($_.Exception.Message)"
    }
})

$ButtonPauseBrigade.Add_Click({
    try {
        $selectedBrigade = Get-SelectedBrigade
        if ($null -eq $selectedBrigade) {
            throw "Wybierz brygade."
        }
        $result = Invoke-BridgeScript -ScriptPath $ScriptMap.brigade_state -Arguments @("-MailboxDir", $MailboxDir, "-BrigadeId", [string]$selectedBrigade.brigade_id, "-DesiredState", "PAUSED", "-Reason", "Pauza operatorska z panelu")
        Write-PanelLog ("Wstrzymano brygade: {0}" -f [string]$selectedBrigade.brigade_id)
        Append-CommandOutput -Text $result
        Refresh-BridgeStatus
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad pauzy brygady", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad pauzy brygady: $($_.Exception.Message)"
    }
})

$ButtonResumeBrigade.Add_Click({
    try {
        $selectedBrigade = Get-SelectedBrigade
        if ($null -eq $selectedBrigade) {
            throw "Wybierz brygade."
        }
        $result = Invoke-BridgeScript -ScriptPath $ScriptMap.brigade_state -Arguments @("-MailboxDir", $MailboxDir, "-BrigadeId", [string]$selectedBrigade.brigade_id, "-DesiredState", "RUNNING")
        Write-PanelLog ("Wznowiono brygade: {0}" -f [string]$selectedBrigade.brigade_id)
        Append-CommandOutput -Text $result
        Refresh-BridgeStatus
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad wznowienia brygady", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad wznowienia brygady: $($_.Exception.Message)"
    }
})

$ButtonAutostartBrigades.Add_Click({
    try {
        $result = Invoke-BridgeScript -ScriptPath $ScriptMap.brigade_autostart -Arguments @("-MailboxDir", $MailboxDir, "-SourceActor", "panel_operator")
        Write-PanelLog "Uruchomiono autostart brygad z panelu."
        Append-CommandOutput -Text $result
        Refresh-BridgeStatus
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Blad autostartu brygad", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-PanelLog "Blad autostartu brygad: $($_.Exception.Message)"
    }
})

Update-BrigadeMeta
Write-PanelLog "Panel gotowy. Zacznij od przycisku: Start most i otworz GPT-5.4 Pro. Sterowanie brygadami jest dostepne w sekcji nad glownymi akcjami."
Refresh-BridgeStatus

[void]$Form.ShowDialog()