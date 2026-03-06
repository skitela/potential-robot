# RUNBOOK LAB Scheduler

## Cel
Bezpieczne uruchamianie LAB 1x dziennie bez wplywu na runtime execution path.

## Start (manual)
```powershell
py -B TOOLS/lab_scheduler.py --root C:\OANDA_MT5_SYSTEM --lab-data-root <LAB_DATA_ROOT> --focus-group FX --lookback-days 180 --snapshot-retention-days 14
```

## Start przez wrapper PS1
```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\run_lab_scheduler.ps1 -Root C:\OANDA_MT5_SYSTEM -LabDataRoot <LAB_DATA_ROOT> -FocusGroup FX -LookbackDays 180 -SnapshotRetentionDays 14
```

## Rejestracja dziennego Task Schedulera (Windows)
```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\register_lab_scheduler_task.ps1 -Root C:\OANDA_MT5_SYSTEM -LabDataRoot <LAB_DATA_ROOT> -TaskName OANDA_MT5_LAB_DAILY -StartTime 03:30
```

## Rejestracja digestu informacyjnego co 3h
```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\register_lab_insights_task.ps1 -Root C:\OANDA_MT5_SYSTEM -LabDataRoot <LAB_DATA_ROOT> -TaskName OANDA_MT5_LAB_INSIGHTS_Q3H
```

## Rejestracja user-level (bez admin, fallback)
```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\register_lab_scheduler_task_user.ps1 -Root C:\OANDA_MT5_SYSTEM -LabDataRoot <LAB_DATA_ROOT> -TaskName OANDA_MT5_LAB_DAILY_USER -StartTime 03:30
```

## Usuniecie zadania
```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\unregister_lab_scheduler_task.ps1 -TaskName OANDA_MT5_LAB_DAILY
```

## Wylogika i sekwencja
1. MT5 ingest (read-only) -> `TOOLS/lab_mt5_history_ingest.py`
2. LAB daily pipeline -> `TOOLS/lab_daily_pipeline.py`
3. Snapshot retention -> `TOOLS/lab_snapshot_retention.py`

## Zabezpieczenia
- lock: `<LAB_DATA_ROOT>\run\lab_scheduler.lock`
- skip przy aktywnym oknie (`ACTIVE_WINDOW`) domyslnie
- resource governor (`CPU_HIGH`, `MEM_LOW`)
- timeout per step
- low-priority best-effort

## Status i evidence
- scheduler status: `<LAB_DATA_ROOT>\run\lab_scheduler_status.json`
- ingest pointer: `LAB/EVIDENCE/ingest/lab_mt5_ingest_latest.json`
- daily pointer: `LAB/EVIDENCE/daily/lab_daily_report_latest.json`
- retention pointer: `LAB/EVIDENCE/retention/lab_snapshot_retention_latest.json`

## Typowe skip reasons
- `LOCK_HELD`
- `ACTIVE_WINDOW`
- `CPU_HIGH`
- `MEM_LOW`

## Parametry operacyjne
- `--timeout-sec` domyslnie `1800`
- `--snapshot-retention-days` domyslnie `14`
- `--skip-snapshot-retention` gdy chcesz pominac retention w danym runie
- `priority_set`:
  - `OK_PSUTIL` lub `OK_WINAPI` = low-priority ustawione,
  - `FAILED_WINAPI:*` / `ERROR:*` = best-effort fail (niefatalne).
