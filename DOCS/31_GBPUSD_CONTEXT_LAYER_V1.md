# GBPUSD Context Layer v1

## Cel
Wdrozenie `GBPUSD` jako drugiego mikro-bota po `EURUSD`, z zachowaniem genotypu `FX_MAIN`, ale z nowa warstwa:
- kontekstu rynku,
- advisory swiec,
- advisory Renko,
- AUX fusion,
- uczenia `v2`,
- bucket summary.

## Zakres wdrozenia
- `MicroBot_GBPUSD.mq5` dostal runtime zgodny z nowszym wzorcem paper/layered learning.
- `Strategy_GBPUSD.mqh` korzysta z warstwy rodzinnej oraz z:
  - `MbContextPolicy`
  - `MbCandleAdvisory`
  - `MbRenkoAdvisory`
  - `MbAuxSignalFusion`
  - `MbLearningContext`

## Pierwszy potwierdzony cykl runtime
Po wdrozeniu i restarcie MT5 `GBPUSD` przeszedl pelny cykl:
- `PAPER_OPEN`
- `PAPER_CLOSE`
- zapis `learning_observations_v2.csv`
- zapis `learning_bucket_summary_v1.csv`

Potwierdzony rekord:
- `SETUP_TREND`
- `market_regime=BREAKOUT`
- `spread_regime=CAUTION`
- `execution_regime=GOOD`
- `confidence_bucket=HIGH`
- `pnl=-0.56`
- `close_reason=PAPER_TIMEOUT`

## Stan po wdrozeniu
- runtime aktywny
- `trade_permissions_ok=true`
- `paper_runtime_override_active=true`
- `learning_sample_count` wzrosl z `19` do `20`
- `adaptive_risk_scale` zareagowal na nowy wynik
- lokalna latencja pozostala bardzo niska

## Wniosek
`GBPUSD` jest gotowy do dalszej obserwacji i pozniejszego strojenia indywidualnego, ale bez rozlewania zmian na cala rodzine. Wdrozenie potwierdzilo, ze pakiet wspolnych usprawnien z `EURUSD` mozna przenosic bez niszczenia lokalnego charakteru mikro-bota.

## 2026-03-13 - indywidualne strojenie pod nowy kontekst

Po porownaniu bucketow uczenia i biezacego runtime wdrozono delikatne, lokalne strojenie `GBPUSD`, bez kopiowania logiki `EURUSD` 1:1.

Wprowadzone regulacje:
- globalny podatek na `spread_regime=CAUTION`
- mocniejsze filtrowanie `SETUP_TREND` w `RANGE`
- delikatne przyciecie `SETUP_TREND` nawet w `TREND`, jesli nie ma wystarczajacej jakosci warunkow
- premia dla `SETUP_REJECTION` w `RANGE` tylko przy realnym wsparciu warstwy pomocniczej `AUX`

Aktualny stan po wdrozeniu:
- `market_regime=CHAOS`
- `spread_regime=CAUTION`
- `last_setup_type=SETUP_TREND`
- `signal_confidence=0.1240`
- `signal_risk_multiplier=0.6000`
- `learning_sample_count=37`
- `wins/losses=5/32`

Wniosek po strojeniu:
- `GBPUSD` nie zostal pozbawiony wlasnego genotypu `FX_MAIN`
- zostal tylko wyrazniej przycisniety tam, gdzie jego bucketowy material pokazuje slabszy `TREND`
- kolejny etap to spokojna obserwacja, czy po tej regulacji zacznie rzadziej wpadać w slabe wejscia trendowe i range rejection bez wsparcia `AUX`

## 2026-03-13 - stan po wdrozeniu i restarcie

Po wdrozeniu, kompilacji i restarcie `MT5`:
- `trade_permissions_ok=true`
- `paper_runtime_override_active=true`
- `runtime_mode=CAUTION`
- `market_regime=RANGE`
- `spread_regime=CAUTION`
- `execution_regime=GOOD`
- `last_setup_type=SETUP_PULLBACK`
- `signal_confidence=0.0000`
- `signal_risk_multiplier=0.5500`
- `learning_sample_count=41`
- `wins/losses=5/36`

Wniosek:
- `GBPUSD` zostal skutecznie docisniety w slabym srodowisku `RANGE + CAUTION`
- po tej rundzie nie jest juz kandydatem do agresywnego wejscia, tylko do spokojnej dalszej obserwacji paper
