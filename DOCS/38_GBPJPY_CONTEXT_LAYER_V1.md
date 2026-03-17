# GBPJPY Context Layer V1

`GBPJPY` zostal przeniesiony na nowa sciezke paper/context learning zgodna z dojrzalym wzorcem `EURUSD`, ale jako bardziej agresywny i kosztowny cross JPY dostal mocniejsze filtry niz `EURJPY`.

Najwazniejsze zalozenia wdrozenia:

- zachowac genotyp `GBPJPY` jako szybkiego i zmiennego crossa
- nie kopiowac `EURUSD`
- ograniczyc kosztowny, chaotyczny breakout
- ostrozniej traktowac range w slabym srodowisku

## Wprowadzone strojenie

Najwazniejsze zmiany lokalne:

- breakout zostal przycisniety w:
  - `CHAOS`
  - `RANGE`
  - `BAD spread`
- range dostal dodatkowe kary przy:
  - `CHAOS`
  - `BAD spread`
  - slabym candle/renko
  - `renko_reversal_flag=true`
- `SETUP_TREND` dostaje premie tylko przy realnej zgodzie warstw

## Stan po wdrozeniu

Aktualny runtime po wdrozeniu i obserwacji:

- `runtime_mode=READY`
- `market_regime=CHAOS`
- `spread_regime=BAD`
- `execution_regime=GOOD`
- `last_setup_type=SETUP_RANGE`
- `signal_confidence=0.0474`
- `signal_risk_multiplier=0.6000`
- `learning_sample_count=26`
- `wins/losses=4/22`

## Obserwacja po wdrozeniu

To jest jedyna para z tej koncowej czworki, ktora w biezacym oknie realnie handlowala na paper po wdrozeniu:

- `PAPER_OPEN`
- `PAPER_CLOSE`
- `PRECHECK_OK`
- `PAPER_TIMEOUT`
- `PAPER_SL`

Najwazniejszy problem:

- spread pozostaje bardzo wysoki
- mimo strojenia bot wciaz potrafi wejsc w kosztowne i slabe paper transakcje

Najuczciwszy wniosek:

- wdrozenie jest technicznie poprawne
- genotyp zostal zachowany
- ale `GBPJPY` pozostaje najtrudniejszym przypadkiem z tej czworki i wymaga dalszej obserwacji przed kolejna ingerencja
