# Determinism / Incremental Gate Checklist

Cel: twardy gate PASS/FAIL przed aktywacja zmian runtime (bez zmiany strategii).

## A. Determinizm (PASS/FAIL)
- [ ] A1. Replay tego samego wejscia daje ten sam wynik decyzji.
- [ ] A2. Brak losowosci w hot path (`random`, niestabilne seedy, ukryte heurystyki).
- [ ] A3. Jawna semantyka czasu (`UTC`, `timestamp_semantics`, `timezone_basis`).
- [ ] A4. Jawna normalizacja symboli (raw/canonical), brak case-drift.
- [ ] A5. Jawne `reason_code` dla BLOCK/CAUTION/FAIL-SAFE.
- [ ] A6. Feature flag + rollback sa gotowe i przetestowane.

## B. Inkrementalnosc (PASS/FAIL)
- [ ] B1. Na ticku brak pelnego recompute historii.
- [ ] B2. Rolling metryki aktualizowane przyrostowo (spread/tick_rate/quality).
- [ ] B3. Ciezkie I/O i housekeeping poza hot path.
- [ ] B4. Kolejki/backpressure nie blokuja decyzji (`drop non-critical`).
- [ ] B5. Advisory nie blokuje rdzenia (timeout/TTL/fallback).

## C. Latency Gate (PASS/FAIL)
- [ ] C1. Raport sekcyjny P50/P95/P99 per: ingest, gates, decision, bridge_send/wait, io_log, execution.
- [ ] C2. Brak regresji P95/P99 vs baseline.
- [ ] C3. Brak wzrostu timeout_count/backpressure/crash.
- [ ] C4. Brak regresji stabilnosci (watchdog/heartbeat/queue health).

## D. Net-Cost / Safety Gate (PASS/FAIL)
- [ ] D1. Brak zmiany logiki strategii (NO_STRATEGY_DRIFT).
- [ ] D2. Cost/risk/session guards pozostaja aktywne.
- [ ] D3. Zmiana ma tryb SHADOW/ADVISORY przed enforce.
- [ ] D4. Wynik netto po kosztach nie pogarsza sie w oknie testowym.

## E. Decyzja
- PASS: wszystkie punkty krytyczne A1-A6, B1-B5, C1-C4, D1-D4 = PASS.
- REVIEW_REQUIRED: brak jednego z punktow krytycznych.
- FAIL: dowolny punkt krytyczny z naruszeniem bez mitigacji.

## Evidence minimalne
- `EVIDENCE/latency_stage1/*.json`
- `EVIDENCE/runtime_kpi/*.json`
- `EVIDENCE/no_live_drift*.json`
- `EVIDENCE/retention/*.json` (jesli zmiana dotyczy I/O/retencji)
