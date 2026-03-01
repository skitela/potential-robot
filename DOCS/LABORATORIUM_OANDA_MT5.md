# LABORATORIUM OANDA MT5 - plan wykonawczy (offline)

## Zakres
- Warstwa uczenia i eksperymentow dziala w `LAB/`.
- Brak zmian w runtime execution path.
- Wyniki LAB to rekomendacje do review operatora.

## Pipeline
1. `TOOLS/shadow_policy_daily_report.py` - baza strict/explore.
2. `TOOLS/lab_daily_pipeline.py` - ranking i bramka LAB->SHADOW.
3. Raport:
   - `LAB/EVIDENCE/daily/lab_daily_report_latest.json`
   - `LAB/EVIDENCE/daily/lab_daily_report_latest.txt`

## Domyslna faza
- `PHASE_1_FX` (okna FX).

## Twarde guardy
- Brak automatycznej mutacji `CONFIG/strategy.json`.
- Brak modyfikacji ryzyka kapitalowego.
- Brak automatycznego wlaczania live execution.
