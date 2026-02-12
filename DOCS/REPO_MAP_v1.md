# REPO_MAP_v1

Repozytorium: C:\OANDA_MT5_SYSTEM

Każdy plik jest klasyfikowany według:
- rel_path
- group: {core_trading, guards, tooling, docs, tests, dyrygent, runtime, other}
- symbols: klasy/funkcje
- imports: lista importów
- entrypoint: true/false
- risk_flags: {may_contain_secrets, may_contain_price_like, may_contain_credentials_paths}
- notes

Repo map generowany automatycznie przez dyrygenta (patrz: EVIDENCE/repo_map.json)

Przykład:

| rel_path                | group      | symbols         | imports         | entrypoint | risk_flags                        | notes           |
|-------------------------|------------|-----------------|-----------------|------------|------------------------------------|-----------------|
| main.py                 | dyrygent   | SafetyBot, ...  | Path, ...       | true       | may_contain_price_like             | entrypoint      |
| BIN/safetybot.py        | guards     | SafetyBot, ...  | mt5, ...        | false      | may_contain_secrets, price_like    | core guard      |
| DYRYGENT_EXTERNAL.py    | dyrygent   | DyrygentExternal| threading, ...  | true       | may_contain_secrets                | orchestrator    |
| ...                     | ...        | ...             | ...             | ...        | ...                                | ...             |

Pełny JSON: EVIDENCE/repo_map.json

## trace.jsonl — Specyfikacja śladu operacji

Każda operacja dyrygenta może być logowana do pliku `trace.jsonl` (jeden rekord JSON na linię) dla pełnej audytowalności.

### Przykład wpisu
```json
{"ts": "2026-02-11T12:34:56", "event": "scan_repo", "rel_path": "BIN/oanda_limits_guard.py", "result": "ok"}
```

### Pola
- `ts`: znacznik czasu UTC
- `event`: typ zdarzenia (np. scan_repo, redact, package, error)
- ...dowolne dodatkowe pola kontekstowe

### Generowanie

```
python dyrygent_trace.py EVIDENCE/trace.jsonl scan_repo rel_path=BIN/oanda_limits_guard.py result=ok
```

## Zastosowanie
- Audyt pokrycia repozytorium
- Automatyczne testy i dry-run
- Repo hygiene, traceability, compliance
- Pełna ścieżka audytu operacji (trace.jsonl)
