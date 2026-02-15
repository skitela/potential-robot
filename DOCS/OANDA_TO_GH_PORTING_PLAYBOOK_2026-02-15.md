# OANDA -> GH Porting Playbook (2026-02-15)

## Cel
- Przeniesc warstwe ochronna i jakosciowa z OANDA_MT5_SYSTEM do GH (Forex bot) w sposob prosty, kontrolowany i odwracalny.
- Zachowac filozofie ryzyka GH i nadrzedna jurysdykcje dyrygenta zmian.

## Co przenosimy 1:1 (komponenty)
- `BIN/black_swan_guard.py`
- `BIN/self_heal_guard.py`
- `BIN/incident_guard.py`
- `BIN/canary_rollout_guard.py`
- `BIN/drift_guard.py`
- `TOOLS/prelive_go_nogo.py` (logika gate; w GH jako osobne narzedzie lub adapter)

## Co przenosimy jako integracje (nie 1:1)
- Logika w `BIN/safetybot.py`:
  - evaluacja self-heal / canary / drift w cyklu skanu
  - wymuszenie ECO przy sygnalach krytycznych
  - dynamiczne obnizanie limitu aktywnosci
  - zapis meta sygnalow do snapshot/status
- Logika w `BIN/scudfab02.py`:
  - uwzglednienie `qa_light` w werdykcie
- Logika w `BIN/learner_offline.py`:
  - `anti_overfit_light`
  - `qa_light` w `META/learner_advice.json`

## Kontrakty danych do zachowania w GH
1. `META/learner_advice.json`
   - wymagane pola: `ts_utc`, `ttl_sec`, `qa_light`
2. `LOGS/incident_journal.jsonl`
   - wymagane pola wpisu: `ts_utc`, `severity`, `kind`, `reason`
3. `DB/system_state`
   - klucz: `canary_rollout_promoted` (`0/1`)

## Minimalny plan wdrozenia do GH
1. Etap A (offline only)
   - dodac 5 guardow i testy jednostkowe
   - podpiac `qa_light` do werdyktu tradera GH-FX
2. Etap B (shadow mode)
   - guardy licza sygnaly, ale nie blokuja transakcji
   - dyrygent zbiera telemetrie i porownuje decyzje
3. Etap C (canary live small-cap)
   - wlaczyc blokady guardow tylko dla GH-FX
   - limity symboli i transakcji utrzymac minimalne
4. Etap D (rollout controlled)
   - po stabilizacji rozszerzac na kolejne boty GH
   - kazdy bot przechodzi ten sam pre-live gate

## Adapter do dyrygenta zmian (wymagane)
- Dyrygent musi widziec i logowac:
  - `self_heal.active`
  - `canary.active`, `canary.pause`, `canary.promoted`
  - `drift.active`, `drift.zscore`
  - `qa_light`
- Polityka nadrzedna:
  - jesli dyrygent daje STOP/ECO, bot GH nie moze nadpisac decyzji.

## Checklista walidacji dla GH
1. Testy komponentow guard:
   - black swan, self-heal, canary, drift, incident
2. Testy kontraktow:
   - `learner_advice` i `incident_journal`
3. Testy integracji:
   - `qa_light=RED` blokuje promocje decyzji agresywnych
   - incydenty i loss streak uruchamiaja pause/ECO
4. Audit offline GH:
   - czystosc repo, manifest, secrets scan
5. Prelive GH:
   - GO/NO-GO + ewentualny cold-start override (manualny)

## Rollback plan (obowiazkowy)
- Jeden przełącznik w GH:
  - `GUARDS_MODE=shadow|enforced|off`
- Przy problemach:
  1. `enforced -> shadow`
  2. analiza incydentow
  3. hotfix
  4. ponowny pre-live gate

## Co juz mamy gotowe do przeniesienia
- W OANDA wszystko przetestowane i audytowane:
  - testy: `107/107 OK`
  - audit offline: PASS
  - pre-live: wspiera `GO_COLD_START_CANARY` pod scislymi warunkami

## Jak zaczac kolejna sesje GH
- Komenda startowa dla operatora:
  - "Przenies Etap A z `DOCS/OANDA_TO_GH_PORTING_PLAYBOOK_2026-02-15.md` do GH-FX."
