# OBSERVERS_IMPLEMENTATION_CANDIDATE

Draftowa warstwa 4 agentów pomocniczych dla `OANDA_MT5_SYSTEM`.

## Cel
- Monitoring, analiza i rekomendacje na bazie danych już zapisanych.
- Zero ingerencji w execution path.
- Zero integracji runtime na etapie draftu.

## Konstytucja (P0)
1. `NO TOUCH` — brak wpływu na decision loop (SafetyBot / EA / bridge).
2. `NO ASK` — brak pytań do runtime (brak socket/API do procesów tradingowych).
3. `READ PERSISTED ONLY` — odczyt tylko zapisanych artefaktów.

## Co jest celowo wyłączone
- Brak instalacji jako usługa.
- Brak scheduler integration z runtime.
- Brak modyfikacji `BIN/`, `MQL5/`, `CONFIG/`.

## Katalog zapisu
Wszystkie wyjścia agentów trafiają do:
- `OBSERVERS_IMPLEMENTATION_CANDIDATE/outputs/reports`
- `OBSERVERS_IMPLEMENTATION_CANDIDATE/outputs/alerts`
- `OBSERVERS_IMPLEMENTATION_CANDIDATE/outputs/tickets`
- `OBSERVERS_IMPLEMENTATION_CANDIDATE/outputs/cache`

