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
Wdrożono dedykowany kanał operatorski:
- `operator_runtime_service.py` (scheduler read-only + status + high-alert popup),
- `operator_console.py` (widok stanu na ekranie),
- start/stop skrypty PowerShell.
Kanał nie dotyka SafetyBot/EA/bridge i nie wykonuje runtime queries do decision loop.

## OPEN_DECISIONS
1. Ktore snapshoty sa kanoniczne dla V1 (mapa nazwa->sciezka) i jakie TTL per artefakt?
2. Jaka polityka retencji dla `outputs/` (rotacja, limity)?
3. Czy dopuścić zewnetrzne walidatory schema w kolejnym etapie?
4. Jakie progi alertow uruchomic na starcie (LOW/MED/HIGH)?
5. Kiedy i jak przejsc z candidate do runtime integration po review Stefana + ChatGPT?
