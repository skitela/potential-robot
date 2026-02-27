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
- Panel operatorski:
  - `powershell -ExecutionPolicy Bypass -File TOOLS/START_OPERATOR_PANEL.ps1`
- Autostart panelu:
  - `powershell -ExecutionPolicy Bypass -File TOOLS/INSTALL_OPERATOR_PANEL_AUTOSTART.ps1 -Force`
- Runtime scheduler observerow (read-only, bez decision loop integration):
  - `python OBSERVERS_IMPLEMENTATION_CANDIDATE/tools/operator_runtime_service.py --popup-enabled`
- Start monitora bez otwierania konsoli:
  - `OBSERVERS_IMPLEMENTATION_CANDIDATE/tools/start_operator_runtime_service.ps1`
- Stop monitora:
  - `OBSERVERS_IMPLEMENTATION_CANDIDATE/tools/stop_operator_console.ps1`

Wyskakujace okienka sa generowane tylko dla alertow `severity=HIGH`.
Przycisk `NAPRAW SYSTEM` uruchamia runbook: `NAPRAW_SYSTEM.bat` -> `TOOLS/CODEX_REPAIR_RUNBOOK.ps1`.
Przycisk `Agent Informacyjny` pokazuje podsumowanie operacyjne i netto (bez surowego JSON):
stan systemu, wykonane zlecenia, wynik netto dzien poprzedni/biezacy, top zysk/strata symbolu, aktywnosc nocna.

## Polityka eskalacji do Codex
- Tylko `agent_straznik_spojnosci` moze tworzyc tickety do Codex.
- Pozostali agenci zapisuja raporty/alerty, bez bezposredniej eskalacji ticketowej.
