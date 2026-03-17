# AUDUSD Deckhand Dirty Accounting Relief V1

## Cel

Usunac falszywy brud danych dla `AUDUSD`, ktory wynikal z tego, ze deckhand
liczyl jako pelny `dirty candle` takze te range'owe kandydaty, ktore w testerze
okazywaly sie neutralne albo dodatnie.

## Dowod wejsciowy

Na bazie `audusd_strategy_tester_20260317_182049`:

- `trust_state = FOREFIELD_DIRTY`
- `trust_reason = FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_CANDLE`
- `candidate_dirty_rows = 111`
- `candidate_dirty_candle_rows = 51`
- `dirty_ratio = 0.7603`

Jednoczesnie w `SETUP_RANGE` byly klasy, ktore mocno pompowaly dirty candle,
ale nie wygladaly toksycznie:

- `CHAOS, POOR, GOOD` -> `19` lekcji, `avg_pnl = +0.02`
- `TREND, POOR, GOOD` -> `12` lekcji, `avg_pnl = -0.01`
- `BREAKOUT, POOR, FAIR` -> `7` lekcji, `avg_pnl = +0.27`
- `RANGE` jako calosc dla `SETUP_RANGE` byl dodatni

## Zmiana

W `MbTuningDeckhandScanCandidates()` dla `AUDUSD` dodano dwa lokalne wyjątki
ksiegowe:

1. `SETUP_RANGE` z `poor candle` i wspierajacym renko (`!poor_renko`) nie jest
   juz liczony jako quality-dirty, jesli spread nie jest `BAD`.
2. `SETUP_RANGE` w reżimie `RANGE` nie jest juz liczony jako quality-dirty,
   jesli spread nie jest `BAD`.

To nie zmienia sygnalu ani wejsc. To zmienia tylko ocene zaufania deckhanda.

## Bieg walidacyjny

- baza:
  - `audusd_strategy_tester_20260317_182049`
- po zmianie:
  - `audusd_strategy_tester_20260317_185018`

## Wynik

Zmiana zostaje przyjeta.

Najwazniejsze efekty:

- `trust_state: FOREFIELD_DIRTY -> TRUSTED`
- `trust_reason: FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_CANDLE -> TRUSTED`
- `candidate_dirty_rows: 111 -> 56`
- `candidate_dirty_candle_rows: 51 -> 11`
- `dirty_ratio: 0.7603 -> 0.3836`
- `realized_pnl_lifetime: -3.98 -> -3.30`

Przy tym nie rozwalilismy probki:

- `learning_sample_count: 249 -> 246`
- `paper_open_rows: 255 -> 252`
- `paper_score_gate_rows: 146 -> 146`

## Wniosek

`AUDUSD` byl czesciowo brudzony przez zbyt agresywna ksiegowosc deckhanda, a nie
tylko przez realnie toksyczny material. Ta poprawka przywraca bardziej uczciwa
ocene zaufania bez wpychania nowego szumu do strategii.
