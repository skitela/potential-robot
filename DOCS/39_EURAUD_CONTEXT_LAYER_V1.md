# EURAUD Context Layer V1

`EURAUD` zostal przeniesiony na nowa sciezke paper/context learning zgodna z dojrzalym wzorcem `EURUSD`, ale z zachowaniem genotypu crossa AUD bardziej range-aware niz klasyczne `FX_MAIN`.

Najwazniejsze zalozenia wdrozenia:

- zachowac genotyp `EURAUD`
- nie kopiowac `EURUSD`
- mocniej dyscyplinowac breakout przy slabym spreadzie
- utrzymac range-aware nature bez wpuszczania zbyt wielu slabosci

## Wprowadzone strojenie

Najwazniejsze zmiany lokalne:

- breakout zostal przycisniety przy:
  - `CHAOS`
  - `RANGE`
  - `BAD spread`
  - slabym lub odwrotnym `Renko`
- `SETUP_RANGE` dostal:
  - premie w `RANGE`
  - kary w `TREND`
  - kary w `CHAOS`
  - kary przy slabszej jakosci swiec lub pustym `Renko`
- `SETUP_TREND` dostaje premie tylko przy realnej zgodzie warstw

## Stan po wdrozeniu

Aktualny runtime po wdrozeniu i obserwacji:

- `runtime_mode=READY`
- `market_regime=CHAOS`
- `spread_regime=BAD`
- `execution_regime=GOOD`
- `last_setup_type=SETUP_BREAKOUT`
- `signal_confidence=0.4545`
- `signal_risk_multiplier=0.5733`
- `learning_sample_count=18`
- `wins/losses=3/15`

## Obserwacja po wdrozeniu

W biezacym oknie `EURAUD`:

- warstwa pomocnicza potrafi dawac:
  - `AUX_ALIGNMENT_GOOD`
  - `AUX_ALIGNMENT_LIGHT`
- ale decyzja nadal konczy sie najczesciej na:
  - `CONTEXT_LOW_CONFIDENCE`
  - `WAIT_NEW_BAR`

Najuczciwszy wniosek:

- wdrozenie jest technicznie poprawne
- nowa warstwa nie gryzie sie z genotypem pary
- ale realna aktywnosc tradingowa jest nadal ograniczana przez:
  - zly spread
  - chaos
  - niski confidence
