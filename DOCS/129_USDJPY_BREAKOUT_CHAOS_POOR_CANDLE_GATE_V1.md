# USDJPY Breakout Chaos Poor Candle Gate V1

## Cel
- przyciąć najbardziej toksyczny podzbiór `USDJPY`
- nie robić szerokiej przebudowy breakoutów
- utrzymać próbkę, ale usunąć najbardziej oczywisty szum

## Zmiana
- plik: `MQL5/Experts/MicroBots/MicroBot_USDJPY.mq5`
- nowy blok paper gate:
  - tylko dla `SETUP_BREAKOUT`
  - tylko w `market_regime = CHAOS`
  - tylko przy `confidence_bucket = LOW`
  - tylko przy `poor candle`
  - oraz gdy `renko` nie jest `GOOD` lub spread jest `BAD`
- nowy reason code:
  - `USDJPY_BREAKOUT_CHAOS_POOR_CANDLE_BLOCK`

## Dlaczego ta zmiana
- bazowy bucket `SETUP_BREAKOUT / CHAOS` był wyraźnie toksyczny:
  - `19` próbek
  - `avg_pnl = -0.2511`
- większość tych przypadków miała:
  - `LOW`
  - `POOR candle`
  - słabe lub niepełne wsparcie warunków
- to był dobry kandydat na wąskie cięcie bez szerokiego psucia runu

## Wynik po retest
- run_id: `usdjpy_strategy_tester_20260317_211810`
- status: `successfully_finished`
- final balance: `10000.00`
- czas: `0:42:04.230`
- `learning_sample_count: 267 -> 257`
- `wins/losses: 129/138 -> 128/129`
- `paper_open_rows: 269 -> 260`
- `paper_score_gate_rows: 229608 -> 222991`
- `score_below_trigger_rows: 42714 -> 32453`
- `realized_pnl_lifetime: -9.01 -> -4.90`

## Efekt lokalny
- `SETUP_BREAKOUT / CHAOS`
  - `samples: 19 -> 10`
  - `avg_pnl: -0.2511 -> -0.0390`
- nowy reason code wszedł do top reasonów:
  - `USDJPY_BREAKOUT_CHAOS_POOR_CANDLE_BLOCK = 16878`

## Werdykt
- zmiana jest dodatnia
- poprawa jest realna i nie wynika z szerokiego rozwalenia próbki
- można ją zostawić w kodzie jako pierwszą zaakceptowaną poprawkę dla `USDJPY`
