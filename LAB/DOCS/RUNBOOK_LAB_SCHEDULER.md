# RUNBOOK LAB Scheduler

## Cel
Bezpieczne uruchamianie pipeline LAB 1x dziennie bez wpływu na runtime.

## Start (manual)
```powershell
py -B TOOLS/lab_scheduler.py --root C:\OANDA_MT5_SYSTEM --lab-data-root C:\OANDA_MT5_LAB_DATA --focus-group FX --lookback-days 180
```

## Start przez wrapper PS1
```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\run_lab_scheduler.ps1 -Root C:\OANDA_MT5_SYSTEM -LabDataRoot C:\OANDA_MT5_LAB_DATA -FocusGroup FX -LookbackDays 180
```

## Wyłączenie
Scheduler jest uruchamiany jednorazowo (`run-once`). Nie ma procesu rezydentnego.
Jeśli job utknie:
1. Sprawdź lock: `C:\OANDA_MT5_LAB_DATA\run\lab_scheduler.lock`
2. Sprawdź status: `C:\OANDA_MT5_LAB_DATA\run\lab_scheduler_status.json`
3. Po potwierdzeniu braku aktywnego procesu usuń lock ręcznie.

## Status
- `C:\OANDA_MT5_LAB_DATA\run\lab_scheduler_status.json`
- `LAB/EVIDENCE/daily/lab_daily_report_latest.json` (pointer)

## Skip reasons
- `LOCK_HELD`
- `ACTIVE_WINDOW` (domyślnie scheduler nie odpala w aktywnym oknie)

## Timeout
- Domyślny timeout: 1800s (konfigurowalny `--timeout-sec`).
- Timeout kończy job bezpiecznie i zapisuje status `TIMEOUT`.

## Retencja/Cleanup
- Raporty: `C:\OANDA_MT5_LAB_DATA\reports\`
- Registry: `C:\OANDA_MT5_LAB_DATA\registry\lab_registry.sqlite`
- Snapshoty: `C:\OANDA_MT5_LAB_DATA\snapshots\`
- Zalecenie: retencja snapshotów 7-14 dni; raportów 30-90 dni.
