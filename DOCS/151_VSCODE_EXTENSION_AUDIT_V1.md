# 151 VSCode Extension Audit V1

## Cel

Odchudzic `VS Code` pod nasz tor:

- PowerShell
- Python
- MQL5
- git
- lokalne narzedzia badawcze

bez trzymania obcych lub dublujacych dodatkow AI oraz dodatkow platformowych, ktorych nie uzywamy.

## Twarde slady z ostatnich 4 dni

Szybki przeglad logow `exthost` pokazal aktywacje:

- `github.copilot-chat`: `188` trafien
- `eamodio.gitlens`: `38`
- `openai.chatgpt`: `10`
- `continue.continue`: `10`
- `editorconfig.editorconfig`: `10`
- `usernamehw.errorlens`: `10`

Brak trafien w tej probce logow:

- `charliermarsh.ruff`
- `davidanson.vscode-markdownlint`
- `ms-python.python`
- `ms-vscode.powershell`
- `redhat.vscode-yaml`

Te dodatki mimo braku trafien zostaja, bo sa zgodne z naszym torem:

- `MQL5 + PowerShell`
- `Python research/ML`
- `yaml / config`
- lint i hygiene

## Co juz usunieto

- wszystkie dodatki `Gemini`
- `Claude Dev`

## Co kwalifikuje sie do bezpiecznego pruningu

Na podstawie logow z ostatnich 3 dni i zgodnosci z naszym torem pracy:

- `continue.continue`
- `github.codespaces`
- `github.remotehub`
- `ms-azuretools.vscode-containers`
- `ms-vscode.azure-repos`
- `ms-vscode.remote-repositories`
- `ms-vscode.vscode-copilot-vision`
- `ms-vscode.cmake-tools`
- `ms-vscode.cpp-devtools`
- `sixth.sixth-ai`

## Co zostaje

- `openai.chatgpt`
- `ms-vscode.powershell`
- `ms-python.*`
- `eamodio.gitlens`
- `editorconfig.editorconfig`
- `usernamehw.errorlens`
- `redhat.vscode-yaml`
- `charliermarsh.ruff`
- `davidanson.vscode-markdownlint`

## Co zostawiono na razie jako graniczne

- `github.copilot-chat`

`github.copilot-chat` byl aktywowany w logach z ostatnich dni i zostaje.
`continue.continue` zostal ostatecznie wyciety decyzja operatorska, mimo aktywnosci w logach.

## Dodatkowe porzadki techniczne

Skrypt pruningu usuwa tez:

- ukryte stare katalogi rozszerzen po aktualizacjach
- sieroty po wczesniej odinstalowanych dodatkach
- ukryte kopie bezpiecznie nieuzywanych rozszerzen platformowych
