# DECISIONS.md

## D1 Boundary-first
Najpierw granice bezpieczenstwa (import/write), potem logika agentow.

## D2 Read-only data adapter
`ReadOnlyDataAdapter` czyta tylko persisted artifacts z kontrola statusu:
- `OK`
- `STALE_OR_INCOMPLETE`
- `MISSING`

## D3 Ticket policy
Kazdy ticket do Codexa wymusza:
- `requires_operator_approval = true`
- `codex_invocation_mode = MANUAL_BY_OPERATOR`

## D4 Safe-read persisted artifacts
Wprowadzono retry/backoff i tolerancje half-written/tail race.
Brak danych lub niepelny artefakt nie jest traktowany jako falszywy FAIL globalny.

## D5 Repo implantation without runtime integration
Kod zostal osadzony jako osobna warstwa w repo (`OBSERVERS_IMPLEMENTATION_CANDIDATE`) bez podpinania do decision loop.

## D6 Operator communication channel
Wdrozono dedykowany kanal operatorski:
- `operator_runtime_service.py` (scheduler read-only + status + high-alert popup),
- `operator_console.py` (widok stanu na ekranie),
- start/stop skrypty PowerShell.
Kanal nie dotyka SafetyBot/EA/bridge i nie wykonuje runtime queries do decision loop.

## D7 Guardian-only Codex escalation
Eskalacja do Codex zostala ograniczona do jednego agenta:
- dozwolone tickety: tylko `agent_straznik_spojnosci`,
- `agent_informacyjny`, `agent_rozwoju_scalpingu`, `agent_rekomendacyjny` nie tworza ticketow do Codex,
- pozostali agenci zapisuja tylko raporty/alerty z informacja o blokadzie eskalacji.

## D8 Operator panel + explicit repair runbook
Dodano panel operatorski uruchamiany lokalnie na Windows:
- `TOOLS/OANDA_OPERATOR_PANEL.py`,
- `TOOLS/START_OPERATOR_PANEL.ps1`,
- `TOOLS/INSTALL_OPERATOR_PANEL_AUTOSTART.ps1`.
Dodano tez jawny runbook naprawczy:
- `NAPRAW_SYSTEM.bat`,
- `TOOLS/CODEX_REPAIR_RUNBOOK.ps1`.
Runbook wykonuje sekwencje: stop -> fix autotrade -> full diagnostic -> start.

## OPEN_DECISIONS
1. Ktore snapshoty sa kanoniczne dla V1 (mapa nazwa->sciezka) i jakie TTL per artefakt?
2. Jaka polityka retencji dla `outputs/` (rotacja, limity)?
3. Czy dopuscic zewnetrzne walidatory schema w kolejnym etapie?
4. Jakie progi alertow uruchomic na starcie (LOW/MED/HIGH)?
5. Kiedy i jak przejsc z candidate do runtime integration po review Stefana + ChatGPT?
6. Czy przycisk `NAPRAW SYSTEM` ma automatycznie restartowac monitor agentow po runbooku?
