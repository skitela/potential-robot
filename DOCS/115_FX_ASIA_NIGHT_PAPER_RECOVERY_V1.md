# FX ASIA Night Paper Recovery V1

## Cel

W nocnym oknie `FX_ASIA` problem nie leżał w hostingu MT5 ani w jakości połączenia, tylko głównie w wewnętrznej logice:
- `AUDUSD` i `USDJPY` dochodziły do `PAPER_SCORE_GATE`, a potem wpadały w `RISK_CONTRACT_BLOCK`
- `NZDUSD` pozostawał na `LOW_SAMPLE`
- dodatkowo rodzina `FX_ASIA` była objęta `FREEZE_FAMILY`, a flota `FREEZE_FLEET`

Ta runda ma odetkać `paper learning` w Azji bez rozwalania bezpieczeństwa.

## Zmiany

### 1. Delikatne poluzowanie progów trust dla `FX_ASIA`

W `MbTuningEpistemology.mqh` obniżono rodzinne progi:
- `min_conversion_ratio`: `0.07 -> 0.04`
- `min_conversion_candidates`: `8 -> 6`
- `max_dirty_ratio`: `0.45 -> 0.47`

To nie otwiera sygnałów samo z siebie. Zmniejsza tylko ryzyko trwałego zakleszczenia `PAPER_CONVERSION_BLOCKED` w rodzinie, która historycznie ma mniejszą i trudniejszą konwersję w nocy.

### 2. Wąski bypass `paper` dla `AUDUSD`

W `MicroBot_AUDUSD.mq5` dodano obejście tylko dla:
- `paper mode`
- `RISK_CONTRACT_BLOCK`
- `SETUP_BREAKOUT`
- `SELL`
- `abs(score) >= 0.98`
- `execution_regime == GOOD`
- `market_regime in {CHAOS, BREAKOUT}`
- `renko_quality_grade == GOOD`
- `candle_quality_grade != POOR`
- `spread_points <= 24`

Nowy reason code:
- `PAPER_IGNORE_RISK_BLOCK_ASIA_BREAKOUT_SELL`

### 3. Wąski recovery dla `USDJPY`

W `MicroBot_USDJPY.mq5` dodano dwa ruchy:

1. Delikatne obniżenie `paper gate` dla breakoutów w najwęższym przypadku:
- tylko `paper`
- tylko `CHAOS`
- tylko `LOW confidence`
- tylko `renko_quality_grade == GOOD`
- tylko `spread_points <= 24`
- `paper_gate_abs` może spaść do `0.70`

2. Wąski bypass `paper` dla `RISK_CONTRACT_BLOCK` na `SETUP_RANGE`:
- `abs(score) >= 0.52`
- `market_regime in {CHAOS, RANGE}`
- `execution_regime == GOOD`
- `renko_quality_grade != POOR`
- `candle_quality_grade != UNKNOWN`
- `spread_points <= 20`

Nowy reason code:
- `PAPER_IGNORE_RISK_BLOCK_ASIA_RANGE`

## Świadomie bez zmian

- `NZDUSD` nie dostał obejścia `RISK_CONTRACT_BLOCK`, bo jego problem wygląda głównie na `LOW_SAMPLE`, a nie na zbyt ciasny kontrakt
- nie ruszano `FREEZE_FAMILY` i `FREEZE_FLEET`, bo to osobna warstwa strojenia, nie główny powód braku nocnych wejść `paper`
- nie poluzowano globalnie strategii ani całej floty

## Oczekiwany efekt

- `AUDUSD` powinien przestać kończyć noc prawie wyłącznie na `PAPER_CONVERSION_BLOCKED_BY_RISK_CONTRACT`
- `USDJPY` powinien odzyskać część lekcji `paper` w zakresach i przy mocniejszych breakoutach z dobrym Renko
- `NZDUSD` pozostaje kandydatem do osobnej interwencji dopiero wtedy, gdy zacznie zostawiać sensowniejszy materiał

## Weryfikacja

- kompilacja floty: `17/17`
- `VALIDATE_PROJECT_LAYOUT.ps1`: `ok=true`
- `VALIDATE_TUNING_HIERARCHY.ps1`: `ok=true`
- `VALIDATE_SYMBOL_POLICY_CONSISTENCY.ps1`: `ok=true`
- `VALIDATE_MT5_SERVER_INSTALL.ps1`: `ok=true`

## Status wdrożenia

- zmiany są zainstalowane do lokalnego terminala MT5
- nie wykonano jeszcze nowego syncu na hosting MetaTrader VPS w tej rundzie
