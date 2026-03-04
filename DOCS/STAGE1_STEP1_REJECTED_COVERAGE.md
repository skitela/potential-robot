# Etap 1 / Krok 1 — Odrzucone setupy + pokrycie per instrument

## Co robi runtime

- Każdy `ENTRY_SKIP` z aktywnym kontekstem symbolu zapisuje rekord odrzucenia do lokalnej bazy.
- Rekord zawiera:
  - symbol,
  - grupę,
  - tryb,
  - `reason_code`,
  - klasę powodu (np. `COST_QUALITY`, `RISK_GUARD`, `DATA_READINESS`),
  - etap (`stage`),
  - kontekst sygnału/regime (jeśli dostępny).

To jest zapis tylko audytowo-treningowy. Nie zmienia logiki execution.

## Raport pokrycia

Uruchom:

```powershell
py -3.12 -B TOOLS/rejected_coverage_report.py --root C:\OANDA_MT5_SYSTEM --lookback-hours 24
```

Wyniki:

- `EVIDENCE/learning_coverage/rejected_coverage_<timestamp>.json`
- `EVIDENCE/learning_coverage/rejected_coverage_<timestamp>.txt`

Raport pokazuje:

- instrumenty bez danych (`MISSING_ALL_DATA`),
- instrumenty z odrzuceniami, ale bez próbek trade-path (`TRADE_PATH_STARVATION`),
- instrumenty z balansiem trade/no-trade (`OK_BALANCED`).

