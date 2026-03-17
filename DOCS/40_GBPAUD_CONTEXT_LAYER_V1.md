# GBPAUD Context Layer V1

`GBPAUD` zostal przeniesiony na nowa sciezke paper/context learning zgodna z dojrzalym wzorcem `EURUSD`, ale jako najbardziej kosztowny i nośny cross AUD dostal najsilniejsze filtry defensywne z calej koncowej czworki.

Najwazniejsze zalozenia wdrozenia:

- zachowac genotyp `GBPAUD`
- nie kopiowac `EURUSD`
- ograniczyc najbardziej kosztowny breakout i range w zlym srodowisku
- nie psuc latencji

## Wprowadzone strojenie

Najwazniejsze zmiany lokalne:

- breakout zostal najmocniej przycisniety przy:
  - `BAD spread`
  - `CHAOS`
  - slabszym lub pustym `Renko`
- range dostal dodatkowe kary przy:
  - `BAD spread`
  - `TREND`
  - `CHAOS`
  - slabym candle
  - pustym `Renko`
- dodano twardy defensywny cap dla:
  - `BAD spread + CHAOS + breakout`

## Stan po wdrozeniu

Aktualny runtime po wdrozeniu i obserwacji:

- `runtime_mode=READY`
- `market_regime=CHAOS`
- `spread_regime=BAD`
- `execution_regime=GOOD`
- `last_setup_type=SETUP_BREAKOUT`
- `signal_confidence=0.4226`
- `signal_risk_multiplier=0.5500`
- `learning_sample_count=15`
- `wins/losses=2/13`

## Obserwacja po wdrozeniu

W biezacym oknie `GBPAUD`:

- nie pokazal jeszcze nowego sensownego paper wejscia
- najczesciej konczy na:
  - `PAPER_IGNORE_OUTSIDE_TRADE_WINDOW`
  - `WAIT_NEW_BAR`
  - `CONTEXT_LOW_CONFIDENCE`

Najuczciwszy wniosek:

- wdrozenie jest technicznie poprawne
- genotyp zostal zachowany
- ale para jest nadal bardzo trudna kosztowo i wymaga dluzszej obserwacji przed dalsza regulacja
