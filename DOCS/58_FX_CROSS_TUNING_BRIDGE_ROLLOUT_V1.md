# 58. FX_CROSS Tuning Bridge Rollout V1

## Cel

Rozszerzyc most `lokalny -> rodzina -> flota` na najtrudniejsza rodzine `FX_CROSS`, ale bez kopiowania `EURUSD` 1:1 i bez niszczenia genotypu crossow.

## Zakres

Rollout objal:

- `EURJPY`
- `GBPJPY`
- `EURAUD`

## Co wdrozono

### Mikro-boty

Kazdy z czterech mikro-botow dostal:

- lokalna polityke strojenia,
- polityke skuteczna budowana z lokalnego stanu, rodziny i koordynatora,
- serwis `OnTimer` do lokalnego strojenia,
- deckhanda technicznego,
- journal `candidate_signals.csv`,
- journal `tuning_deckhand.csv`,
- zapis `tuning_policy_effective.csv`.

### Strategie

Strategie rodziny `FX_CROSS` dostaly:

- setter polityki strojenia,
- most semantyczny dla crossowego genotypu:
  - `SETUP_PULLBACK` jest traktowany jako trend-like,
  - `SETUP_RANGE` jest traktowany jako mean-reversion-like,
- ograniczenia breakout/trend-like po polityce lokalnej,
- nowe filtry:
  - `require_non_poor_renko_for_breakout`
  - `require_non_poor_candle_for_trend`
- limity `confidence_cap` i `risk_cap`.

## Co potwierdzono

- `11/11` mikro-botow kompiluje sie poprawnie
- po restarcie `MT5` cala jedenastka laduje sie poprawnie
- cala czworka ma juz `candidate_signals.csv` w runtime

## Stan rodziny po wdrozeniu

### Symbole lokalne

- wszystkie cztery symbole pozostaja lokalnie w trybie `LOW_SAMPLE`
- to jest poprawne zachowanie: kapitanowie nie udaja wiedzy, gdy probka jest jeszcze za mala

### Rodzina

- warstwa rodzinna `FX_CROSS` jest juz aktywna i `TRUSTED`
- rodzina utrzymuje `FREEZE_FAMILY`
- rodzina dociska:
  - `dominant_confidence_cap = 0.82`
  - `dominant_risk_cap = 0.80`
  - `breakout_family_tax = 0.06`
  - `trend_family_tax = 0.05`

### Flota

- koordynator floty utrzymuje `FREEZE_FLEET`
- flota nie daje jeszcze prawa do agresywnego strojenia calego parku

## Uczciwy wniosek

`FX_CROSS` jest juz podpieta do tej samej architektury, ktora dziala dla `FX_MAIN` i `FX_ASIA`, ale ta rodzina jest najbardziej wymagajaca. W tej chwili jej najwazniejsza zaleta nie jest agresja, tylko uczciwosc: lokalni kapitanowie jeszcze nie stroja sie zbyt smialo, a rodzina i flota trzymaja dyscypline, dopoki nie pojawi sie swiezy material po otwarciu rynku.
