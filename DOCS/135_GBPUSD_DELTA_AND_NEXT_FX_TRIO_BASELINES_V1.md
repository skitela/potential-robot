# 135 GBPUSD DELTA AND NEXT FX TRIO BASELINES V1

## Cel
1. Wykonac jeszcze jedna celowana runde dla `GBPUSD`.
2. Przygotowac i uruchomic kolejne trzy pary walutowe w laboratorium MT5:
- `EURUSD`
- `EURJPY`
- `GBPJPY`

## GBPUSD
### Zmiana
W `MicroBot_GBPUSD.mq5` skrócono `paper hold` dla `SETUP_BREAKOUT`, gdy:
- `market_regime` jest `TREND` albo `BREAKOUT`
- `candle_quality_grade == POOR`
- `renko_quality_grade != POOR`

To jest mala delta typu:
- nie rusza bramki wejscia
- nie zmienia polityki kosztu
- nie rozwala probki
- tylko szybciej domyka breakouty, ktore mialy ujemny drift na timeoutach

### Wynik
Porownanie:
- baza: `gbpusd_strategy_tester_20260318_101348`
- nowy bieg: `gbpusd_strategy_tester_20260318_114601`

Efekt:
- `learning_sample_count`: `241 -> 241`
- `wins/losses`: `116/125 -> 119/122`
- `realized_pnl_lifetime`: `-18.07 -> -15.88`
- `pnl_per_sample`: `-0.075 -> -0.0659`
- repeatability pozostaje `STABLE`

Stan pozostaje:
- `trust_state = FOREFIELD_DIRTY`
- `trust_reason = FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_CANDLE`
- `cost_pressure_state = NON_REPRESENTATIVE`

Wniosek:
- zmiana jest dodatnia i bezpieczna
- zostaje w kodzie
- ale nastepny duzy ruch dla `GBPUSD` nadal powinien isc bardziej w koszt/spread niz w sygnal

## Nowe trzy pary
### EURUSD
- `samples = 250`
- `wins/losses = 120/130`
- `realized_pnl_lifetime = -7.75`
- `trust = FOREFIELD_DIRTY / FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_CANDLE`
- `cost = NON_REPRESENTATIVE`
- readiness: `COST_SKEWED`

Wniosek:
- para ma material i jest wartosciowa poznawczo
- ale najpierw koszt i spread, nie strategia

### EURJPY
- `samples = 268`
- `wins/losses = 114/154`
- `realized_pnl_lifetime = -32.22`
- `trust = PAPER_CONVERSION_BLOCKED / PAPER_CONVERSION_BLOCKED_BY_LOW_RATIO`
- `cost = HIGH`
- readiness: `CONVERSION_LIMITED`

Wniosek:
- glowny korek to konwersja `candidate -> paper`
- nie stroic jeszcze samego sygnalu

### GBPJPY
- `samples = 10`
- `wins/losses = 0/10`
- `realized_pnl_lifetime = -12.88`
- `trust = PAPER_CONVERSION_BLOCKED / PAPER_CONVERSION_BLOCKED_BY_LOW_RATIO`
- `cost = NON_REPRESENTATIVE`
- readiness: `INSUFFICIENT_SAMPLE`

Wniosek:
- to jeszcze nie jest para do strojenia logiki
- najpierw trzeba zbudowac probe albo zmienic okno testu

## Co wnosi ta runda dla calego systemu
- `GBPUSD` dostalo jedna mala, potwierdzona poprawke delta
- nowe trzy pary maja juz czyste sandboxy testera
- wiemy, ktora z nich jest pierwsza do dalszej pracy:
  - `EURUSD`
- wiemy, ktorych dwoch nie wolno teraz psuc strojeniem sygnalu:
  - `EURJPY`
  - `GBPJPY`

## Priorytet po tej rundzie
1. Jesli wracac do tej trojki, to najpierw `EURUSD`.
2. `EURJPY` wymaga pracy nad konwersja.
3. `GBPJPY` wymaga najpierw probki, nie delty strategii.
