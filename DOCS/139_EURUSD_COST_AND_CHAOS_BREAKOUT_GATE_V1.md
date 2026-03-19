# 139 EURUSD Cost And Chaos Breakout Gate V1

## Cel
- zdjac z `EURUSD` falszywy status `NON_REPRESENTATIVE`, jesli tester przesadnie karze koszt
- po odblokowaniu kosztu wykonac jedna mala delte w `paper gate`
- nie ruszac szeroko strategii bez twardego dowodu

## Etap 1. Kalibracja kosztu w testerze

Plik:
- `MQL5/Include/Core/MbTuningEpistemology.mqh`

Zmiana:
- dla rodzin FX w `Strategy Tester` koszt nie jest juz oznaczany jako `NON_REPRESENTATIVE`, jezeli:
  - spread jest `BAD`,
  - ale `spread_vs_typical_move < 0.95`

To jest waski bezpiecznik laboratoryjny:
- tylko w testerze
- tylko dla FX
- nie zmienia runtime VPS

### Wynik po retest
Porownanie:
- baza: `eurusd_strategy_tester_20260319_073726`
- retest: `eurusd_strategy_tester_20260319_084737`

Efekt:
- `cost_pressure_state: NON_REPRESENTATIVE -> HIGH`
- `tester_readiness: COST_SKEWED -> DIRTY_FOREGROUND`
- probka i wynik pozostaly bez zmian:
  - `learning_sample_count = 250`
  - `wins/losses = 120 / 130`
  - `realized_pnl_lifetime = -7.75`

Wniosek:
- koszt przestal zaslaniac prawdziwy problem
- glownym korkiem zostal foreground

## Etap 2. Waska blokada breakoutu w chaosie

Plik:
- `MQL5/Experts/MicroBots/MicroBot_EURUSD.mq5`

Zmiana:
- dodano nowa blokade `paper gate`:
  - tylko dla `SETUP_BREAKOUT`
  - tylko w `market_regime = CHAOS`
  - tylko przy `poor candle`
  - oraz gdy `renko` jest slabe lub `confidence_bucket = LOW`
- nowy reason:
  - `EURUSD_BREAKOUT_CHAOS_DIRTY_BLOCK`

To nie jest przebudowa breakoutu jako calej klasy.
To jest wyciecie najbardziej brudnego podzbioru, ktory w testerze byl slaby i podtrzymywal foregroundowy szum.

### Wynik po retest
Porownanie:
- baza: `eurusd_strategy_tester_20260319_084737`
- nowy run: `eurusd_strategy_tester_20260319_085657`

Efekt:
- `realized_pnl_lifetime: -7.75 -> -6.97`
- `learning_sample_count: 250 -> 238`
- `wins/losses: 120/130 -> 112/126`
- `paper_open_rows: 253 -> 240`
- `paper_score_gate_rows: 158 -> 145`
- `candidate_dirty_rows: 122 -> 107`
- `dirty_ratio: 0.7722 -> 0.7379`

Lokalnie:
- `SETUP_BREAKOUT / CHAOS`
  - `samples: 22 -> 6`
  - `avg_pnl: -0.1532 -> -0.1533`
- nowy blok wszedl do telemetryki:
  - `EURUSD_BREAKOUT_CHAOS_DIRTY_BLOCK = 18350`

### Werdykt
- zmiana jest dodatnia
- poprawia wynik bez szerokiego rozwalenia probki
- zostaje w kodzie

## Stan po tej rundzie
- `trust_state` nadal: `FOREFIELD_DIRTY`
- `trust_reason` nadal: `FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_CANDLE`
- `cost_pressure_state` juz uczciwie: `HIGH`

## Nastepny ruch
Kolejna poprawka dla `EURUSD` nie powinna juz isc w koszt.
Najbardziej sensowny nastepny cel to:
- `SETUP_REJECTION / RANGE`
- albo `SETUP_TREND / TREND` przy slabej warstwie pomocniczej

Ale dopiero jako kolejna mala delta, nie teraz hurtem.
