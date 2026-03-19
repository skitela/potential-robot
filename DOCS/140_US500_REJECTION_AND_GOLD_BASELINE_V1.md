# 140 US500 Rejection And GOLD Baseline V1

## Cel
- przejsc z aktywnych runtime instrumentow na laboratorium testera
- sprawdzic, czy `US500` przyjmie mala delte bez rozwalania probki
- zbudowac pierwszy czysty baseline dla `GOLD`

## US500
### Co sprawdzono
Po baseline `us500_strategy_tester_20260319_093938` przetestowano waska hipoteze:
- skrocic `paper hold` dla slabszych `SETUP_RANGE`
- tylko po to, aby ograniczyc timeoutowy wyciek w `CHAOS` i `TREND`

### Wynik
Retest `us500_strategy_tester_20260319_101311` wyszedl gorzej:
- `realized_pnl_lifetime: -63.97 -> -74.30`
- `learning_sample_count: 1454 -> 1700`
- `paper_open_rows: 1464 -> 1712`
- `paper_score_gate_rows: 1109 -> 1353`
- `dirty_ratio: 0.6447 -> 0.6800`
- `trust_reason: FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_CANDLE -> FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_HYBRID`

### Werdykt
- zmiana zostala odrzucona
- kod strategii `US500` zostal cofnięty do stanu sprzed eksperymentu
- zostaje tylko sandbox testera w [MicroBot_US500.mq5](C:\MAKRO_I_MIKRO_BOT\MQL5\Experts\MicroBots\MicroBot_US500.mq5)

### Wniosek
`US500` jest obiecujacy, ale kolejny ruch nie powinien isc w slepe skracanie holda.
Tester sugeruje raczej:
- doczyszczanie foregroundu
- albo precyzyjniejsze odciecie toksycznych patternow `SETUP_RANGE`
- ale nie szeroka zmiane czasu trzymania pozycji

## GOLD
### Co wdrozono
Dodano pelny sandbox testera w [MicroBot_GOLD.mq5](C:\MAKRO_I_MIKRO_BOT\MQL5\Experts\MicroBots\MicroBot_GOLD.mq5), aby badac `GOLD` tym samym czystym torem co pary FX i `US500`.

### Baseline
Run:
- `gold_strategy_tester_20260319_110311`

Najwazniejsze liczby:
- `learning_sample_count = 485`
- `wins/losses = 224 / 261`
- `paper_open_rows = 485`
- `paper_score_gate_rows = 357`
- `realized_pnl_lifetime = -31.81`
- `trust_state = FOREFIELD_DIRTY`
- `trust_reason = FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_CANDLE`
- `cost_pressure_state = NON_REPRESENTATIVE`

Najgorsze bucket'y:
- `SETUP_REJECTION / RANGE`
- `SETUP_BREAKOUT / CHAOS`
- `SETUP_BREAKOUT / BREAKOUT`
- `SETUP_TREND / BREAKOUT`

### Werdykt
- baseline jest dobry poznawczo i zostaje
- nie przyjeto jeszcze zadnej zmiany strategii dla `GOLD`
- glowny korek to najpierw:
  - reprezentatywnosc kosztu
  - foreground
  - a dopiero potem sygnal

## Wniosek dla dnia
- `US500`: tester uczciwie odrzucil zla delte
- `GOLD`: tester dal pierwszy czysty baseline
- dla obu instrumentow zostaje w kodzie tylko infrastruktura sandboxu, bez niepotwierdzonych zmian strategii
