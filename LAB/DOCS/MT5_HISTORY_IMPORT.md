# MT5 History Import v1 (Read-Only)

## Cel
Automatyczny i legalny pobor historii z lokalnego terminala MT5 (OANDA TMS) do LAB, bez zewnetrznych API.

## Wejscie
- Lokalny terminal MT5 uruchomiony i zalogowany.
- Skrypt: `TOOLS/lab_mt5_history_ingest.py`

## Wyjscie
- Curated DB:
  - `C:\OANDA_MT5_LAB_DATA\data_curated\mt5_history.sqlite`
- Raporty ingestu:
  - `C:\OANDA_MT5_LAB_DATA\reports\ingest\lab_mt5_ingest_*.json`
- Pointer operatora:
  - `LAB/EVIDENCE/ingest/lab_mt5_ingest_latest.json`

## Uruchomienie (manual)
```powershell
py -3.12 -B TOOLS/lab_mt5_history_ingest.py --root C:\OANDA_MT5_SYSTEM --lab-data-root C:\OANDA_MT5_LAB_DATA --focus-group FX --timeframes M1 --lookback-days 180
```

## Inkrementalnosc
- Watermark per `(source_type, symbol, timeframe)` w `ingest_watermarks`.
- Bezpieczny overlap (`--overlap-minutes`, domyslnie 30 min).
- Deduplikacja:
  - `PRIMARY KEY(symbol, timeframe, ts_utc)` + `INSERT OR IGNORE`.

## Mapowanie symboli brokerowych
- Ingest przyjmuje symbole kanoniczne (np. `EURUSD`) i rozwiązuje je do symbolu brokera (np. `EURUSD.a`) deterministycznie:
  - `EXACT` -> `PREFIX` -> `CONTAINS`.
- Raport zawiera dla kazdego wpisu:
  - `symbol` (kanoniczny),
  - `broker_symbol`,
  - `symbol_resolution_mode`.

## Metryki jakosci v1.1
- Raport ingestu zawiera:
  - `rows_fetched_total`,
  - `rows_inserted_total`,
  - `rows_deduped_total`,
  - `gap_events_total` (luki czasowe vs TF),
  - `symbols_resolved` / `symbols_unresolved`,
  - `invalid_ohlc_total`,
  - `negative_spread_total`,
  - `nonpositive_close_total`,
  - `quality_grade` (`OK` / `REVIEW_REQUIRED`).

## Registry
Tabela `job_runs` rejestruje kazdy run ingestu:
- `run_type=INGEST_MT5`
- `status=PASS/FAIL/SKIP`
- `reason`
- `dataset_hash`, `config_hash`
- `evidence_path`

## Uwaga operacyjna
Skrypt nie mutuje runtime strategy i nie pisze do katalogow runtime (`BIN/MQL5/RUN/LOGS/DB/META/CONFIG`).
