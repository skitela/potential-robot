# USDJPY Strategy Tester First Success V1

## Cel
- uruchomić pierwszy pełny, izolowany bieg `USDJPY` w `MT5 Strategy Tester`
- nie mieszać danych testera z aktywnym `paper/shadow`
- zbudować pierwszy punkt odniesienia dla dalszych zmian delta

## Zakres
- instrument: `USDJPY.pro`
- ekspert: `MicroBot_USDJPY`
- interwał: `M5`
- zakres dat: `2026.03.01 -> 2026.03.16`
- model: `real ticks`
- sandbox: `MAKRO_I_MIKRO_BOT_TESTER_USDJPY_USDJPY_AGENT`

## Wynik bazowy
- status: `successfully_finished`
- final balance: `10000.00`
- czas testu: `0:23:06.871`
- `learning_sample_count = 267`
- `wins/losses = 129 / 138`
- `realized_pnl_lifetime = -9.01`
- `trust_state = PAPER_CONVERSION_BLOCKED`
- `trust_reason = PAPER_CONVERSION_BLOCKED_BY_LOW_RATIO`
- `execution_quality_state = GOOD`
- `cost_pressure_state = HIGH`

## Główne wnioski
- `USDJPY` w testerze nie jest martwy; daje dużą próbkę i sensowny materiał do dalszej pracy.
- Największy problem nie leży w wykonaniu, tylko w jakości lokalnych otwarć i bardzo niskiej konwersji `paper`.
- Najgorszy bucket bazowy to `SETUP_BREAKOUT / CHAOS`: `19` próbek, `avg_pnl = -0.2511`.
- Drugim ciężarem pozostaje `SETUP_RANGE / CHAOS`: `67` próbek, `avg_pnl = -0.0490`.

## Znaczenie architektoniczne
- tor testera dla `USDJPY` działa poprawnie
- sandbox nie brudzi aktywnego środowiska VPS
- wynik bazowy nadaje się do dalszych zmian `human-in-the-loop`
