# External Data Plan (Stage v1)

Status:
- MT5 local history ingest: ACTIVE (read-only, local terminal).
- OANDA REST: PLANNED/OFF.
- Manual CSV: PLANNED/OFF.

## Kolejnosc wdrozenia
1. MT5 history import z lokalnego terminala (wdrozone v1).
2. OANDA REST history import (tylko read-only, jawny mapping instrumentow).
3. CSV manual import do porownan i testow spojnosc.

## Warunki aktywacji
- Schemat danych i walidacja quality flags.
- Rozdzielenie storage LAB od runtime (`LAB_DATA_ROOT/data_raw`, `LAB_DATA_ROOT/data_curated`).
- Brak zapisow do execution path.

## Minimalne pola dla datasetow
- symbol, ts_utc, bid, ask, spread_points
- OHLC (M1/M5) + source_id + ingestion_ts_utc
- quality flags: missing, stale, out_of_order, jump

## Polityka
- Priorytet: dane kompatybilne z OANDA/MT5 execution constraints.
- Dane zewnetrzne nie moga nadpisywac persisted facts z runtime.
