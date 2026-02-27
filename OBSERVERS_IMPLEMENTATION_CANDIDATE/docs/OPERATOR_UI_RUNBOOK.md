# OPERATOR_UI_RUNBOOK

## Cel
Zapewnic operatorowi prosty kanal komunikacji z warstwa observerow:
- konsola statusu na ekranie,
- popupy tylko dla alertow HIGH,
- brak ingerencji w decision loop.

## Start (zalecane)
```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\OBSERVERS_IMPLEMENTATION_CANDIDATE\tools\start_operator_console.ps1 -EnablePopups
```

Co robi skrypt:
1. Uruchamia `operator_runtime_service.py` w tle (jesli nie dziala).
2. Otwiera `operator_console.py` w oknie operatora.

## Stop
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

## Ograniczenia (P0)
- Brak importu SafetyBot/EA/bridge.
- Brak runtime queries do decision loop.
- Brak write do execution path.
- Tylko persisted data + outputs observerow.
