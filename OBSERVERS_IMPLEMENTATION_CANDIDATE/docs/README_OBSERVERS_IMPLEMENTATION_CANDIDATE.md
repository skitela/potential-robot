# README_OBSERVERS_IMPLEMENTATION_CANDIDATE

Warstwa `OBSERVERS_IMPLEMENTATION_CANDIDATE` jest odseparowana od execution path i sluzy tylko do obserwacji/analityki persisted data.

## Konstytucja (P0)
- NO TOUCH: brak zlecen, brak mutacji live config, brak zmian decision loop.
- NO ASK: brak runtime queries do SafetyBot/EA/bridge.
- READ PERSISTED ONLY: tylko odczyt zapisanych artefaktow i zapis raportow/alertow/ticketow do `outputs/`.
- MANUAL CODEX INVOCATION ONLY: ticket wymaga aprobaty operatora, bez auto-uruchamiania Codexa.

## Katalogi
- `common/` - kontrakty, adapter RO, walidatory, granice import/write, writer wynikow.
- `agent_informacyjny/` - monitoring operacyjny.
- `agent_rozwoju_scalpingu/` - analityka R&D netto po kosztach.
- `agent_rekomendacyjny/` - synteza rekomendacji.
- `agent_straznik_spojnosci/` - wykrywanie driftu i trigger audytu.
- `tests/` - testy granic read-only i kontraktow.
- `docs/` - decyzje architektoniczne i plan etapowy.
- `outputs/` - jedyne dozwolone miejsce zapisu.

## Czego celowo nie ma
- Brak integracji runtime trading.
- Brak instalacji jako service.
- Brak modyfikacji SafetyBot/EA/bridge.

## Komunikacja z operatorem (wdrozone)
- Konsola operatora (terminal refresh):
  - `python OBSERVERS_IMPLEMENTATION_CANDIDATE/tools/operator_console.py`
- Runtime scheduler observerow (read-only, bez decision loop integration):
  - `python OBSERVERS_IMPLEMENTATION_CANDIDATE/tools/operator_runtime_service.py --popup-enabled`
- Start/stop przez PowerShell:
  - `OBSERVERS_IMPLEMENTATION_CANDIDATE/tools/start_operator_console.ps1`
  - `OBSERVERS_IMPLEMENTATION_CANDIDATE/tools/stop_operator_console.ps1`

Wyskakujace okienka sa generowane tylko dla alertow `severity=HIGH` i nie uruchamiaja zadnych zmian w runtime trading.
