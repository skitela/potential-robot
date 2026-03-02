# OANDA MT5 LAB (Offline, odseparowany od runtime)

Ten katalog to warstwa kodu i dokumentacji LAB.
Ciezsze artefakty i dane LAB domyslnie trafiaja poza repo do `LAB_DATA_ROOT` (`C:/OANDA_MT5_LAB_DATA`).

## Cel
- Maksymalizacja wyniku netto po kosztach (`net after costs`) dla scalpingu.
- Iteracyjne badanie `DQ` (Decision Quality) oraz `DP` (Decision Path/latency).
- Zero ingerencji w execution path runtime.

## Twarde zasady
- LAB nie wysyla zlecen i nie mutuje `CONFIG/strategy.json`.
- LAB nie mutuje ryzyka kapitalowego.
- LAB nie zapisuje do katalogow runtime (`BIN`, `MQL5`, `RUN`, `LOGS`, `DB`, `META`, `CONFIG`).
- Wynik LAB to rekomendacje + evidence, nie automatyczna aktywacja.

## Start (manual, FX)
1. Jednorazowy run:
   - `python -B TOOLS/lab_daily_pipeline.py --root C:\OANDA_MT5_SYSTEM --lab-data-root C:\OANDA_MT5_LAB_DATA --focus-group FX --lookback-days 180 --daily-guard`
2. Odczyt:
   - szczegoly: `C:\OANDA_MT5_LAB_DATA\reports\daily\lab_daily_report_*.json`
   - wskaznik dla operatora: `LAB/EVIDENCE/daily/lab_daily_report_latest.json`

## Snapshot-read policy
- Domyslnie: `PREFER_SNAPSHOT`.
- Pipeline tworzy snapshoty SQLite (`decision_events`, `m5_bars`) w `LAB_DATA_ROOT/snapshots/*`.
- Gdy snapshot sie nie uda, fallback do runtime DB w trybie read-only.
- Retencja snapshotow: `TOOLS/lab_snapshot_retention.py` (domyslnie 14 dni).

## MT5 history ingest (read-only)
- Skrypt: `TOOLS/lab_mt5_history_ingest.py`
- Zrodlo: lokalny terminal MT5 (OANDA TMS), bez zewnetrznych API.
- Start manual:
  - `py -3.12 -B TOOLS/lab_mt5_history_ingest.py --root C:\OANDA_MT5_SYSTEM --lab-data-root C:\OANDA_MT5_LAB_DATA --focus-group FX --timeframes M1 --lookback-days 180`
- Wyniki:
  - curated DB: `C:\OANDA_MT5_LAB_DATA\data_curated\mt5_history.sqlite`
  - raport: `C:\OANDA_MT5_LAB_DATA\reports\ingest\lab_mt5_ingest_*.json`
  - pointer operatora: `LAB/EVIDENCE/ingest/lab_mt5_ingest_latest.json`

## Scheduler (bezpieczny)
- Skrypt: `TOOLS/lab_scheduler.py`
- Sekwencja: ingest MT5 -> pipeline -> retencja snapshotow.
- Zabezpieczenia: lock, skip przy `ACTIVE` oknie (domyslnie), resource governor, timeout, low-priority.
- Runbook: `LAB/DOCS/RUNBOOK_LAB_SCHEDULER.md`
- Rejestracja zadania dziennego:
  - `powershell -ExecutionPolicy Bypass -File TOOLS\register_lab_scheduler_task.ps1 -Root C:\OANDA_MT5_SYSTEM -LabDataRoot C:\OANDA_MT5_LAB_DATA -StartTime 03:30`
  - fallback bez admin: `powershell -ExecutionPolicy Bypass -File TOOLS\register_lab_scheduler_task_user.ps1 -Root C:\OANDA_MT5_SYSTEM -LabDataRoot C:\OANDA_MT5_LAB_DATA -StartTime 03:30`

## Registry eksperymentow (MVP)
- SQLite: `LAB_DATA_ROOT/registry/lab_registry.sqlite`
- Tabele:
  - `job_runs`
  - `ingest_watermarks`
  - `experiment_runs`
  - `candidate_scores`

## Konfiguracja
- `LAB/CONFIG/lab_config.json`
  - cel i wagi rankingu,
  - progi promocji LAB->SHADOW,
  - safety,
  - domyslna polityka storage/scheduler.
