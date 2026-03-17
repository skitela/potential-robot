# USDCHF Context Layer v1

## Cel
Wdrozenie `USDCHF` jako kolejnego mikro-bota po `EURUSD`, `GBPUSD` i `USDCAD`, z zachowaniem genotypu `FX_MAIN`, ale z nowa warstwa:
- kontekstu rynku,
- advisory swiec,
- advisory Renko,
- AUX fusion,
- uczenia `v2`,
- bucket summary.

## Zakres wdrozenia
- `MicroBot_USDCHF.mq5` dostal runtime zgodny z nowszym wzorcem paper i layered learning.
- `Strategy_USDCHF.mqh` korzysta z warstwy rodzinnej oraz z:
  - `MbContextPolicy`
  - `MbCandleAdvisory`
  - `MbRenkoAdvisory`
  - `MbAuxSignalFusion`
  - `MbLearningContext`

## Pierwszy potwierdzony cykl runtime
Po wdrozeniu i restarcie MT5 `USDCHF` przeszedl pelny cykl:
- `PAPER_OPEN`
- `PAPER_CLOSE`
- zapis `learning_observations_v2.csv`
- zapis `learning_bucket_summary_v1.csv`

Potwierdzony pierwszy rekord `v2`:
- `SETUP_BREAKOUT`
- `market_regime=CHAOS`
- `spread_regime=CAUTION`
- `execution_regime=GOOD`
- `confidence_bucket=LOW`
- `candle_bias=DOWN`
- `renko_bias=DOWN`
- `pnl=-0.43`
- `close_reason=PAPER_TIMEOUT`

## Stan po wdrozeniu
- runtime aktywny
- `trade_permissions_ok=true`
- `paper_runtime_override_active=true`
- `market_regime=CHAOS`
- `last_setup_type=SETUP_BREAKOUT`
- `learning_sample_count` wzrosl z `15` do `16`
- `adaptive_risk_scale` zareagowal na pierwszy wynik z nowej sciezki
- lokalna latencja pozostala bardzo niska:
  - avg `11 us`
  - max `13 us`

## Pierwszy bucket summary
Pierwszy bucket `USDCHF` po nowym wdrozeniu:
- `SETUP_BREAKOUT / CHAOS`
  - `samples=1`
  - `wins=0`
  - `losses=1`
  - `pnl_sum=-0.43`
  - `avg_pnl=-0.4300`

## Wniosek
`USDCHF` wszedl juz na nowa sciezke paper, kontekstu i uczenia. W odroznieniu od starego stanu nie konczy sie juz tylko na `WAIT_NEW_BAR` albo `ORDER_CHECK_FAIL`, ale zapisuje realne zamkniecia i bucketowe uczenie. Bot jest gotowy do dalszej spokojnej obserwacji i pozniejszego strojenia indywidualnego.

## 2026-03-13 - indywidualne strojenie pod nowy kontekst

`USDCHF` okazal sie najbardziej alarmowym przypadkiem z rodziny `FX_MAIN`: bardzo slabe buckety, dlugi ciag strat i jednoczesnie zbyt wysoka pewnosc sygnalu. To wymusilo najmocniejsza regulacje z calej trojki.

Wprowadzone regulacje:
- globalny hamulec dla `SETUP_BREAKOUT`
- dodatkowy podatek dla breakoutow przy `spread_regime=CAUTION`
- wyrazne przyciecie breakoutow w `CHAOS`, `TREND` i nawet w `BREAKOUT`
- mocniejsza kara dla `AUX_CONFLICT_CAUTION`
- nowa kara dla `AUX_INCONCLUSIVE`
- dodatkowa kara dla breakoutow bez wsparcia `AUX`
- limity confidence i risk przy serii strat:
  - od `loss_streak >= 5`
  - od `loss_streak >= 10`
- dodatkowy limit, gdy historia jest juz dostatecznie bogata i `learning_bias` jest mocno ujemny
- dodatkowy limit, gdy swiece sa `POOR` i nie ma silnego wsparcia `AUX`

Aktualny stan po wdrozeniu:
- `market_regime=BREAKOUT`
- `spread_regime=GOOD`
- `last_setup_type=SETUP_BREAKOUT`
- `signal_confidence=0.5200`
- `signal_risk_multiplier=0.7800`
- `learning_sample_count=28`
- `wins/losses=2/26`

Wniosek po strojeniu:
- najgrozniejszy problem zostal zlamany: runtime nie jest juz agresywnie pewny siebie przy bardzo slabym materialie historycznym
- `USDCHF` dalej wymaga spokojnej obserwacji, ale juz nie wyglada jak bot, ktory zbyt wysoko ufa zlym breakoutom
- ten instrument powinien byc dalej prowadzony bardzo konserwatywnie

## 2026-03-13 - stan po wdrozeniu i restarcie

Po wdrozeniu, kompilacji i restarcie `MT5`:
- `trade_permissions_ok=true`
- `paper_runtime_override_active=true`
- `runtime_mode=CAUTION`
- `market_regime=BREAKOUT`
- `spread_regime=CAUTION`
- `execution_regime=GOOD`
- `last_setup_type=SETUP_BREAKOUT`
- `signal_confidence=0.3800`
- `signal_risk_multiplier=0.6400`
- `learning_sample_count=32`
- `wins/losses=2/30`
- `loss_streak=5`

Wniosek:
- `USDCHF` zostal wyraznie schlodzony i nie ma juz tej samej nadmiernej pewnosci siebie co wczesniej
- nadal wymaga najbardziej konserwatycznej obserwacji z calej trojki
