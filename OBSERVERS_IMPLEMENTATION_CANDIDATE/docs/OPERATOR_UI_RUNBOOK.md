# OPERATOR_UI_RUNBOOK

## Cel
Zapewnic operatorowi prosty kanal komunikacji z warstwa observerow:
- panel sterowania na pulpicie,
- popupy tylko dla alertow HIGH,
- brak ingerencji w decision loop.

## Panel operatorski (zalecane)
Start panelu:
```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\START_OPERATOR_PANEL.ps1
```

Panel zawiera przyciski:
- `WLACZ SYSTEM` (`start.bat`)
- `WYLACZ SYSTEM` (`stop.bat`)
- `NAPRAW SYSTEM` (`NAPRAW_SYSTEM.bat` -> `TOOLS/CODEX_REPAIR_RUNBOOK.ps1`)
- `START MONITORA AGENTOW`
- `STOP MONITORA AGENTOW`
- 4 przyciski agentow otwierajace ostatni raport JSON.

W widoku agenta (szczegolnie `Agent Informacyjny`) panel pokazuje juz podsumowanie tekstowe zamiast surowego kodu JSON:
- czy system jest aktywny,
- liczbe wykonanych zlecen i glowne skip reason,
- wynik netto za poprzedni i biezacy dzien (z `DB/decision_events.sqlite`, tabela `deals_log`),
- najwiekszy zysk i strate po symbolach,
- podsumowanie aktywnosci nocnej (okno Warsaw 20:00->08:00).

## Autostart panelu po starcie Windows
```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\INSTALL_OPERATOR_PANEL_AUTOSTART.ps1 -Force
```

## Start/stop monitora agentow bez panelu
Start runtime service:
```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\OBSERVERS_IMPLEMENTATION_CANDIDATE\tools\start_operator_runtime_service.ps1 -EnablePopups
```

Stop monitora:
```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\OBSERVERS_IMPLEMENTATION_CANDIDATE\tools\stop_operator_console.ps1
```

## Artefakty operatora
- Status uslugi:
  - `OBSERVERS_IMPLEMENTATION_CANDIDATE/outputs/operator/operator_runtime_status.json`
- Zdarzenia popup:
  - `OBSERVERS_IMPLEMENTATION_CANDIDATE/outputs/operator/operator_popup_events.jsonl`
- Raporty/alerty/tickety:
  - `OBSERVERS_IMPLEMENTATION_CANDIDATE/outputs/reports/`
  - `OBSERVERS_IMPLEMENTATION_CANDIDATE/outputs/alerts/`
  - `OBSERVERS_IMPLEMENTATION_CANDIDATE/outputs/tickets/`
- Raport naprawy:
  - `RUN/codex_repair_last.json`

## Polityka eskalacji do Codex
- Tylko `agent_straznik_spojnosci` moze utworzyc ticket do Codex.
- Pozostali agenci zapisują jedynie rekomendacje/alerty polityki i nie eskaluja ticketow.

## Ograniczenia (P0)
- Brak importu SafetyBot/EA/bridge.
- Brak runtime queries do decision loop.
- Brak write do execution path.
- Tylko persisted data + outputs observerow.
