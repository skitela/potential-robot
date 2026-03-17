# USDCAD Context Layer v1

## Cel
Wdrozenie `USDCAD` jako kolejnego mikro-bota po `EURUSD` i `GBPUSD`, z zachowaniem genotypu `FX_MAIN`, ale z nowa warstwa:
- kontekstu rynku,
- advisory swiec,
- advisory Renko,
- AUX fusion,
- uczenia `v2`,
- bucket summary.

## Zakres wdrozenia
- `MicroBot_USDCAD.mq5` dostal runtime zgodny z nowszym wzorcem paper i layered learning.
- `Strategy_USDCAD.mqh` korzysta z warstwy rodzinnej oraz z:
  - `MbContextPolicy`
  - `MbCandleAdvisory`
  - `MbRenkoAdvisory`
  - `MbAuxSignalFusion`
  - `MbLearningContext`

## Pierwszy potwierdzony cykl runtime
Po wdrozeniu i restarcie MT5 `USDCAD` przeszedl pelny cykl:
- `PAPER_OPEN`
- `PAPER_CLOSE`
- zapis `learning_observations_v2.csv`
- zapis `learning_bucket_summary_v1.csv`

Potwierdzone rekordy `v2`:
- `SETUP_BREAKOUT`
- `market_regime=BREAKOUT`
- `spread_regime=CAUTION`
- `execution_regime=GOOD`
- `confidence_bucket=HIGH`
- `pnl=-0.30`
- `close_reason=PAPER_TIMEOUT`

oraz kolejny:
- `SETUP_BREAKOUT`
- `market_regime=BREAKOUT`
- `spread_regime=CAUTION`
- `execution_regime=GOOD`
- `confidence_bucket=HIGH`
- `pnl=0.08`
- `close_reason=PAPER_TIMEOUT`

## Stan po wdrozeniu
- runtime aktywny
- `trade_permissions_ok=true`
- `paper_runtime_override_active=true`
- `market_regime=BREAKOUT`
- `last_setup_type=SETUP_BREAKOUT`
- `learning_sample_count` nadal rosnie juz na nowej sciezce paper
- `adaptive_risk_scale` pozostaje stabilny
- lokalna latencja pozostala bardzo niska:
  - avg `7 us`
  - max `15 us`

## Pierwszy bucket summary
Pierwszy bucket `USDCAD` po nowym wdrozeniu:
- `SETUP_BREAKOUT / BREAKOUT`
  - `samples=2`
  - `wins=1`
  - `losses=1`
  - `pnl_sum=-0.22`
  - `avg_pnl=-0.1100`

## Wniosek
`USDCAD` wszedl juz na nowa sciezke paper, kontekstu i uczenia. W odroznieniu od starszego stanu nie konczy sie juz tylko na `WAIT_NEW_BAR` albo `ORDER_CHECK_FAIL`, ale zapisuje realne zamkniecia i bucketowe uczenie. Bot jest gotowy do dalszej spokojnej obserwacji i pozniejszego strojenia indywidualnego.

## 2026-03-13 - indywidualne strojenie pod nowy kontekst

Po analizie bucketow i bieżącego runtime `USDCAD` potwierdzilo sie, ze glowny problem siedzi w zbyt czestym dopuszczaniu `SETUP_BREAKOUT`, niezaleznie od jakosci warunkow.

Wprowadzone regulacje:
- globalny hamulec dla `SETUP_BREAKOUT`
- dodatkowy podatek dla `SETUP_BREAKOUT` przy `spread_regime=CAUTION`
- wyrazniejsze przyciecie breakoutow w `CHAOS`
- delikatne oslabienie breakoutow nawet w `TREND`
- kara dla `AUX_CONFLICT_CAUTION` i `AUX_INCONCLUSIVE`
- lekka premia dla `SETUP_TREND` tylko wtedy, gdy `market_regime=TREND` i wsparcie `AUX` jest mocne
- dodatkowa kara dla breakoutow bez zadnego wsparcia warstwy pomocniczej

Aktualny stan po wdrozeniu:
- `market_regime=RANGE`
- `spread_regime=CAUTION`
- `last_setup_type=SETUP_BREAKOUT`
- `signal_confidence=0.0000`
- `signal_risk_multiplier=0.5500`
- `learning_sample_count=34`
- `wins/losses=7/27`

Wniosek po strojeniu:
- `USDCAD` zachowal swoj genotyp `FX_MAIN`, ale breakout przestal byc tak latwo dopuszczany
- bot zostal ustawiony bardziej defensywnie wobec chaosu i kosztu wejscia
- kolejna obserwacja ma potwierdzic, czy po tej zmianie zmniejszy sie udzial slabych breakoutow w bucketach

## 2026-03-13 - stan po wdrozeniu i restarcie

Po wdrozeniu, kompilacji i restarcie `MT5`:
- `trade_permissions_ok=true`
- `paper_runtime_override_active=true`
- `runtime_mode=CAUTION`
- `market_regime=TREND`
- `spread_regime=GOOD`
- `execution_regime=GOOD`
- `last_setup_type=SETUP_TREND`
- `signal_confidence=0.4706`
- `signal_risk_multiplier=0.6000`
- `learning_sample_count=38`
- `wins/losses=8/30`

Wniosek:
- `USDCAD` przestal byc tak silnie zdominowany przez breakout
- po tej rundzie wyglada jak dobry kandydat do dalszej obserwacji, czy `SETUP_TREND` zacznie przejmowac czesc zdrowych wejsc
