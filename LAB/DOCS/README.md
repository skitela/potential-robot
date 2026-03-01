# OANDA MT5 LAB (Offline, odseparowany od runtime)

Ten katalog to warstwa kodu i dokumentacji LAB.
Cięższe artefakty i dane LAB domyślnie trafiają poza repo do `LAB_DATA_ROOT` (`C:/OANDA_MT5_LAB_DATA`).

## Cel
- Maksymalizacja wyniku netto po kosztach (`net after costs`) dla scalpingu.
- Iteracyjne badanie `DQ` (Decision Quality) oraz `DP` (Decision Path/latency).
- Zero ingerencji w execution path runtime.

## Twarde zasady
- LAB nie wysyła zleceń i nie mutuje `CONFIG/strategy.json`.
- LAB nie mutuje ryzyka kapitałowego.
- LAB nie zapisuje do katalogów runtime (`BIN`, `MQL5`, `RUN`, `LOGS`, `DB`, `META`, `CONFIG`).
- Wynik LAB to rekomendacje + evidence, nie automatyczna aktywacja.

## Start (manual, FX)
1. Jednorazowy run:
   - `python -B TOOLS/lab_daily_pipeline.py --root C:\OANDA_MT5_SYSTEM --lab-data-root C:\OANDA_MT5_LAB_DATA --focus-group FX --lookback-days 180 --daily-guard`
2. Odczyt:
   - szczegóły: `C:\OANDA_MT5_LAB_DATA\reports\daily\lab_daily_report_*.json`
   - wskaźnik dla operatora: `LAB/EVIDENCE/daily/lab_daily_report_latest.json`

## Snapshot-read policy
- Domyślnie: `PREFER_SNAPSHOT`.
- Pipeline tworzy snapshoty SQLite (`decision_events`, `m5_bars`) w `LAB_DATA_ROOT/snapshots/*`.
- Gdy snapshot się nie uda, fallback do runtime DB w trybie read-only.

## Scheduler (bezpieczny)
- Skrypt: `TOOLS/lab_scheduler.py`
- Zabezpieczenia: lock, skip przy `ACTIVE` oknie (domyślnie), timeout, low-priority.
- Runbook: `LAB/DOCS/RUNBOOK_LAB_SCHEDULER.md`

## Registry eksperymentów (MVP)
- SQLite: `LAB_DATA_ROOT/registry/lab_registry.sqlite`
- Tabele:
  - `experiment_runs`
  - `candidate_scores`

## Konfiguracja
- `LAB/CONFIG/lab_config.json`
  - cel i wagi rankingu,
  - progi promocji LAB->SHADOW,
  - safety,
  - domyślna polityka storage/scheduler.
