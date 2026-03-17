# AUDUSD Breakout Chaos Gate Rejected V1

## Cel

Zweryfikowac, czy szeroka bramka `paper` dla `SETUP_BREAKOUT` w reżimie `CHAOS`
poprawia jakosc materialu i wynik testera dla `AUDUSD`.

## Zmiana testowana

W `MicroBot_AUDUSD.mq5` dodano warunek blokujacy promocje `SCORE_BELOW_TRIGGER`
do `PAPER_SCORE_GATE`, gdy:

- `setup_type == SETUP_BREAKOUT`
- `market_regime == CHAOS`
- `confidence_bucket == LOW`
- swieca byla slaba lub renko nie bylo `GOOD`

Reason code eksperymentu:

- `AUDUSD_BREAKOUT_CHAOS_DIRTY_GATE_BLOCK`

## Biegi porownawcze

- baza po filtrze `dirty range`:
  - `audusd_strategy_tester_20260317_155513`
- gate wlaczony:
  - `audusd_strategy_tester_20260317_170935`
  - potwierdzony rerun:
  - `audusd_strategy_tester_20260317_172747`
- gate wylaczony kontrolnie:
  - `audusd_strategy_tester_20260317_175253`

## Wynik

Gate jest deterministyczny, ale szkodzi globalnie:

- `realized_pnl_lifetime`: `-4.67 -> -19.16`
- `learning_sample_count`: `250 -> 532`
- `paper_open_rows`: `255 -> 540`
- `paper_conversion_ratio`: `1.7347 -> 1.6119`

Jednoczesnie poprawia sam bucket `SETUP_BREAKOUT / CHAOS`, ale ta lokalna poprawa
jest okupiona duzo gorszym bilansem calego bota.

## Decyzja

Zmiany nie przyjmowac.

- usunieto bramke `AUDUSD_BREAKOUT_CHAOS_DIRTY_GATE_BLOCK`
- nie zostawiono martwego toggla w kodzie

## Wniosek

Problem `AUDUSD` nie lezy tu w szerokim odcinaniu `BREAKOUT / CHAOS` na warstwie
`paper gate`. To byla zbyt szeroka ingerencja, ktora przestawiala globalny przebieg
lekcji i psula wynik netto.
