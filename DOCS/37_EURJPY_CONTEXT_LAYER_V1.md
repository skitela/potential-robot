# EURJPY Context Layer V1

`EURJPY` zostal przeniesiony na nowa sciezke paper/context learning zgodna z dojrzalym wzorcem `EURUSD`, ale z zachowaniem genotypu rodziny `FX_CROSS`.

Najwazniejsze zalozenia wdrozenia:

- zachowac crossowy charakter `EURJPY`
- nie kopiowac `EURUSD` 1:1
- przyciac breakout w najgorszych warunkach
- utrzymac bardzo niska latencje

## Wprowadzone strojenie

Najwazniejsze zmiany lokalne:

- breakout zostal przycisniety w:
  - `CHAOS`
  - `RANGE`
  - `BAD spread`
- dodano dodatkowe kary przy konflikcie swiec i `Renko`
- dodano premie dla:
  - `SETUP_PULLBACK` w `TREND`
  - `SETUP_RANGE` w `RANGE`
- dodano defensywne ograniczenie przy:
  - dlugiej serii strat
  - negatywnym `learning_bias`

## Stan po wdrozeniu

Aktualny runtime po wdrozeniu i obserwacji:

- `runtime_mode=READY`
- `market_regime=CHAOS`
- `spread_regime=BAD`
- `execution_regime=GOOD`
- `last_setup_type=SETUP_BREAKOUT`
- `signal_confidence=0.2300`
- `signal_risk_multiplier=0.5500`
- `learning_sample_count=20`
- `wins/losses=2/18`

## Obserwacja po wdrozeniu

W biezacym oknie `EURJPY`:

- zyje technicznie
- poprawnie odczytuje runtime control i permissions
- nadal zatrzymuje sie glownie na:
  - `PAPER_IGNORE_OUTSIDE_TRADE_WINDOW`
  - `WAIT_NEW_BAR`
  - `AUX_CONFLICT_CAUTION`
  - `CONTEXT_LOW_CONFIDENCE`

Najwazniejszy wniosek:

- wdrozenie jest technicznie poprawne
- genotyp crossa zostal zachowany
- bot nie pokazuje regresji architektonicznej
- ale jego obecny problem jest rynkowy, nie techniczny:
  - zly spread
  - chaos
  - niski confidence
