# AUDUSD Context Layer V1

`AUDUSD` zostal przeniesiony na nowa sciezke paper/context learning zgodna z dopracowanym wzorcem `EURUSD`, ale bez kopiowania jego genotypu 1:1.

Najwazniejsze potwierdzenia po wdrozeniu:

- `MicroBot_AUDUSD` laduje sie poprawnie w `MT5`
- runtime po wdrozeniu:
  - `trade_permissions_ok=true`
  - `paper_runtime_override_active=true`
  - `market_regime=TREND`
  - `last_setup_type=SETUP_RANGE`
- bot mial juz historyczne próbki paper, ale brakowalo mu indywidualnego strojenia pod nowy kontekst

## Strojenie indywidualne 2026-03-13

Po obserwacji wykonano pierwsze strojenie lokalne pod genotyp `AUDUSD`.

Najwazniejsze zmiany:

- przycieto `SETUP_RANGE`, gdy:
  - `candle_quality_grade=POOR`
  - `renko_quality_grade=UNKNOWN`
- mala premia dla range w `BREAKOUT` zostala pozostawiona tylko wtedy, gdy:
  - swiece nie sa slabe
  - `Renko` daje realny sygnal
- dodano defensywny cap, gdy:
  - `loss_streak >= 10`
  - albo `learning_bias <= -0.10`

Stan po strojeniu:

- `runtime_mode=CAUTION`
- `market_regime=TREND`
- `spread_regime=GOOD`
- `execution_regime=GOOD`
- `last_setup_type=SETUP_RANGE`
- `signal_confidence=0.2455`
- `signal_risk_multiplier=0.5500`
- `learning_sample_count=37`
- `wins/losses=4/33`

Najuczciwszy wniosek:

- `AUDUSD` nie zostal przerobiony na `EURUSD`
- zachowal lokalny nacisk na `SETUP_RANGE`
- ale zostal odciagniety od najgorszych przypadkow range w trendzie bez potwierdzenia z warstw pomocniczych
