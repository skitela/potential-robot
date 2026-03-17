# 117 NZDUSD Tester Delta Range Chaos And Central Stale V1

## Cel
- odciac `CENTRAL_STATE_STALE` jako artefakt izolowanego Strategy Testera,
- mocniej ograniczyc `SETUP_RANGE` w `CHAOS` dla `NZDUSD`,
- sprawdzic efekt na tym samym oknie testowym co pierwszy udany bieg.

## Zmiany
- `MbTuningEpistemology.mqh`
  - `MbEvaluateCentralStateStaleness(...)` ignoruje centralna staleness w runtime testera.
- `Strategy_NZDUSD.mqh`
  - dodano silniejszy podatek dla `SETUP_RANGE` w `CHAOS`,
  - dodano waska blokade `NZDUSD_RANGE_CHAOS_BLOCK` dla slabych lub konfliktowych przypadkow.

## Weryfikacja
- kompilacja: `COMPILE_MicroBot_NZDUSD.log` -> `0 errors, 0 warnings`
- test:
  - symbol: `NZDUSD.pro`
  - TF: `M5`
  - zakres: `2026.03.01` -> `2026.03.16`
  - model: `real ticks`
  - wynik: `successfully_finished`

## Wynik po zmianie
- `CENTRAL_STATE_STALE` nie wystapilo jako finalny `trust_state`
- finalny `trust_state = FOREFIELD_DIRTY`
- finalny `trust_reason = FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_HYBRID`
- `NZDUSD_RANGE_CHAOS_BLOCK` pojawilo sie w `candidate_signals.csv`
- ogolny wynik testu pozostaje poznawczo uzyteczny, ale jeszcze bez dodatniej przewagi netto

## Wniosek
- poprawka epistemologiczna zadzialala od razu,
- poprawka strategiczna dla `RANGE/CHAOS` zadzialala wasko i bezpiecznie,
- nastepny krok to rozszerzyc to z kontrola na:
  - mocniejszy bypass breakout dla `NZDUSD`,
  - lepsze rozdzielenie `FOREFIELD_DIRTY` od zwyklego niskiego score,
  - raport per `setup x regime x conversion`.
