# 138 GBPUSD Gate Accepted And EURUSD Baseline Reconfirmed V1

## Cel
- wykonac jedna mala, uczciwa delte dla `GBPUSD`
- sprawdzic, czy poprawa jest realna, a nie przypadkowa
- ponownie potwierdzic baseline `EURUSD` bez dokladania sztucznej zmiany

## GBPUSD
### Zmiana
W [MicroBot_GBPUSD.mq5](C:\MAKRO_I_MIKRO_BOT\MQL5\Experts\MicroBots\MicroBot_GBPUSD.mq5) dodano waska blokade:
- tylko dla `SETUP_REJECTION`
- tylko w `market_regime = CHAOS` albo `RANGE`
- tylko przy `poor candle`
- oraz gdy:
  - `confidence_bucket != HIGH`
  - albo `renko` jest slabe
  - albo spread jest `BAD`

Nowy reason:
- `GBPUSD_REJECTION_POOR_CANDLE_BLOCK`

To nie jest szeroka przebudowa strategii.
To jest lokalne odciecie najbardziej toksycznej czesci `rejection`, ktora w testerze psula wynik i dokladala foregroundowego brudu.

### Wynik po retest
Porownanie:
- baza: `gbpusd_strategy_tester_20260318_225542`
- nowy run: `gbpusd_strategy_tester_20260319_072156`

Efekt:
- `realized_pnl_lifetime: -15.89 -> -13.22`
- `learning_bias: -0.0916 -> -0.0734`
- `learning_sample_count: 243 -> 219`
- `wins/losses: 120/123 -> 111/108`
- `paper_open_rows: 243 -> 220`
- `paper_score_gate_rows: 107 -> 84`
- `candidate_dirty_rows: 70 -> 45`
- `dirty_ratio: 0.6542 -> 0.5357`

Nowy blok wszedl mocno do telemetryki:
- `GBPUSD_REJECTION_POOR_CANDLE_BLOCK = 41486`

Stan nadal:
- `trust_state = FOREFIELD_DIRTY`
- `trust_reason = FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_CANDLE`
- `cost_pressure_state = HIGH`

### Werdykt
- zmiana jest dodatnia
- poprawia wynik i jednoczesnie czyści foreground
- nie rozwala probki nadmiernie
- zostaje w kodzie

## EURUSD
### Co zrobiono
Uruchomiono swiezy retest bez nowej zmiany logiki:
- baza: `eurusd_strategy_tester_20260318_134654`
- nowy run: `eurusd_strategy_tester_20260319_073726`

### Wynik
Rerun wyszedl praktycznie identycznie:
- `learning_sample_count = 250`
- `wins/losses = 120 / 130`
- `paper_open_rows = 253`
- `paper_score_gate_rows = 158`
- `realized_pnl_lifetime = -7.75`
- `trust_state = FOREFIELD_DIRTY`
- `trust_reason = FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_CANDLE`
- `cost_pressure_state = NON_REPRESENTATIVE`

### Werdykt
- baseline jest stabilny i powtarzalny
- nie ma jeszcze uczciwego sygnalu, zeby ruszac sama strategie
- kolejny ruch dla `EURUSD` powinien isc bardziej w koszt/spread albo foreground, nie w kolejny podatek sygnalowy na slepo

## Wniosek dla dnia
- `GBPUSD` dostalo jedna mala, zaakceptowana poprawke
- `EURUSD` zostalo potwierdzone bez zmian
- system laboratoryjny zachowal sie prawidlowo: jedna para przyjela delte, druga uczciwie powiedziala `jeszcze nie`
