# USDJPY Context Layer V1

`USDJPY` zostal przeniesiony na nowa sciezke paper/context learning zgodna ze wzorcem `EURUSD`, ale z zachowaniem genotypu rodziny `FX_ASIA`.

Najwazniejsze potwierdzenia po wdrozeniu:

- `MicroBot_USDJPY` kompiluje sie poprawnie i laduje sie poprawnie w `MT5`
- po restarcie terminala potwierdzono poprawne zaladowanie eksperta
- runtime po wdrozeniu:
  - `trade_permissions_ok=true`
  - `paper_runtime_override_active=true`
  - `market_regime=TREND`
  - `spread_regime=GOOD`
  - `execution_regime=GOOD`
  - `last_setup_type=SETUP_BREAKOUT`

Po pierwszym pelnym cyklu:

- potwierdzono:
  - `PAPER_OPEN`
  - `PAPER_CLOSE`
  - zapis `learning_observations_v2.csv`
  - zapis `learning_bucket_summary_v1.csv`

Pierwszy rekord `v2`:

- `SETUP_BREAKOUT`
- `market_regime=TREND`
- `spread_regime=CAUTION`
- `execution_regime=GOOD`
- `confidence_bucket=LOW`
- `candle_bias=DOWN`
- `renko_bias=UP`
- `pnl=0.00`
- `close_reason=PAPER_TIMEOUT`

Pierwszy bucket summary:

- `SETUP_BREAKOUT / TREND`
- `samples=1`
- `wins=1`
- `losses=0`
- `pnl_sum=0.00`

Wazne:

- `USDJPY` nie dostal jeszcze dalszego, glebokiego strojenia indywidualnego
- celem etapu bylo doprowadzenie go do pelnej nowej sciezki paper, kontekstu i uczenia `v2`
- kolejne kroki powinny juz dotyczyc spokojnej obserwacji i dopiero potem dalszych regulacji lokalnych

## Strojenie indywidualne 2026-03-13

Po pierwszym okresie obserwacji wykonano ostrozne strojenie `USDJPY` bez naruszania genotypu rodziny `FX_ASIA`.

Najwazniejsze zmiany:

- przycieto `SETUP_BREAKOUT`, gdy:
  - `market_regime=CHAOS`
  - albo swiece i `Renko` sa w konflikcie
- dodano dodatkowy cap confidence i ryzyka, gdy:
  - `loss_streak >= 10`
  - albo `learning_bias <= -0.10`
- zachowano lokalny charakter `USDJPY`:
  - sesje azjatyckie
  - breakout jako istotny setup
  - brak kopiowania logiki `EURUSD` 1:1

Stan po strojeniu:

- `runtime_mode=CAUTION`
- `market_regime=TREND`
- `spread_regime=CAUTION`
- `execution_regime=GOOD`
- `last_setup_type=SETUP_BREAKOUT`
- `signal_confidence=0.4400`
- `signal_risk_multiplier=0.6164`
- `learning_sample_count=49`
- `wins/losses=6/43`

Najuczciwszy wniosek:

- `USDJPY` jest juz na nowej, inteligentniejszej sciezce
- breakout zostal przytemperowany w najgorszych warunkach
- po tym etapie potrzebna jest spokojna obserwacja, a nie dalsza natychmiastowa centralizacja zmian
