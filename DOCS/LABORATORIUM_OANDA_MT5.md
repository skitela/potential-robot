# LABORATORIUM OANDA MT5 - plan wykonawczy (offline)

## Zakres
- Warstwa uczenia i eksperymentow dziala w `LAB/`.
- Brak zmian w runtime execution path.
- Wyniki LAB to rekomendacje do review operatora.
- Dane LAB domyslnie poza repo: `LAB_DATA_ROOT`.

## Pipeline
1. `TOOLS/lab_separation_audit.py` - audyt separacji LAB/runtime.
2. `TOOLS/lab_daily_pipeline.py` - baza strict/explore + ranking + bramka LAB->SHADOW + zapis do registry.
3. `TOOLS/lab_dp_report.py` - raport MVP Decision Path (DP+L).
4. `TOOLS/lab_scheduler.py` - bezpieczny scheduler (lock/skip/timeout/low-priority).

## Artefakty operatora
- Pointer: `LAB/EVIDENCE/daily/lab_daily_report_latest.json`
- Szczegóły: `LAB_DATA_ROOT/reports/daily/*.json`
- Registry: `LAB_DATA_ROOT/registry/lab_registry.sqlite`
- Scheduler status: `LAB_DATA_ROOT/run/lab_scheduler_status.json`

## Domyslna faza
- `PHASE_1_FX` (okna FX), horyzont domyslny 180 dni.

## Twarde guardy
- Brak automatycznej mutacji `CONFIG/strategy.json`.
- Brak modyfikacji ryzyka kapitalowego.
- Brak automatycznego wlaczania live execution.
- Write boundary guard blokuje zapis do runtime dirs.
- Snapshot-read policy: `PREFER_SNAPSHOT` (fallback runtime read-only).
