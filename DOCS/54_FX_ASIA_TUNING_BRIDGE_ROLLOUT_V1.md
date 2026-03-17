# 54. FX_ASIA Tuning Bridge Rollout V1

## Cel

Rozszerzyc most `lokalny -> rodzina -> flota` na pierwsza rodzine poza `FX_MAIN`, bez naruszania azjatyckiego genotypu instrumentow.

## Zakres

Rollout objal:

- `USDJPY`
- `AUDUSD`
- `NZDUSD`

## Co wdrozono

### Mikro-boty

Kazdy z trzech mikro-botow dostal:

- lokalna polityke strojenia,
- polityke skuteczna budowana z lokalnego stanu, rodziny i koordynatora,
- serwis `OnTimer` do lokalnego strojenia,
- deckhanda technicznego,
- journale `tuning_actions.csv` i `tuning_deckhand.csv`,
- zapis `tuning_policy_effective.csv`.

### Strategie

Strategie rodziny `FX_ASIA` dostaly:

- setter polityki strojenia,
- ograniczenia breakout/trend po polityce lokalnej,
- nowe filtry:
  - `require_non_poor_renko_for_breakout`
  - `require_non_poor_candle_for_trend`
- limity `confidence_cap` i `risk_cap`.

## Co potwierdzono

- `11/11` mikro-botow kompiluje sie poprawnie
- po restarcie `MT5` cala jedenastka laduje sie poprawnie
- `USDJPY`, `AUDUSD` i `NZDUSD` zapisaly `tuning_policy_effective.csv`

## Stan rodziny po wdrozeniu

### USDJPY

- `trusted_data = 1`
- polityka skuteczna jest juz widoczna
- rodzina i flota dociskaja symbol przez breakout tax oraz wspolne capy

### AUDUSD

- `trusted_data = 1`
- polityka skuteczna jest juz widoczna
- symbol jest gotowy do obserwacji i dalszego lokalnego strojenia po otwarciu rynku

### NZDUSD

- `trusted_data = 0`
- `trust_reason = LOW_SAMPLE`
- most działa, ale lokalny agent nie ma jeszcze prawa do dojrzalych decyzji strojenia

## Uczciwy wniosek

`FX_ASIA` jest juz podlaczona do tej samej architektury, ktora dziala dla `FX_MAIN`, ale rodzina pozostaje bardziej surowa i bardziej defensywna. To jest zgodne z danymi: `NZDUSD` ma za malo probki, a `AUDUSD` i `USDJPY` potrzebuja jeszcze potwierdzenia po ponownym otwarciu rynku.
