# SILVER Timeout And Low Confidence Gate V1

## Cel
- domknac pierwszy uczciwy baseline dla `SILVER` na wtornym `MT5`
- wyciac najbardziej toksyczne bucket-y `LOW + POOR candle`
- utrzymac stabilna prace toru `90%` bez konfliktu wrapperow

## Co wykryl runtime i live logs
- `SILVER` jest aktywnym instrumentem live i nadal traci netto
- dominujace straty siedza w bucketach:
  - `SETUP_BREAKOUT / CHAOS`
  - `SETUP_BREAKOUT / TREND`
  - `SETUP_TREND / CHAOS`
  - `SETUP_TREND / TREND`
  - `SETUP_REJECTION / CHAOS`
- najczestsze otwarcia `PAPER_SCORE_GATE` sa skupione w:
  - `SETUP_TREND | CHAOS | LOW | POOR`
  - `SETUP_TREND | TREND | LOW | POOR`
  - `SETUP_REJECTION | CHAOS | LOW | POOR`

## Co poprawiono
- w [MicroBot_SILVER.mq5](C:\MAKRO_I_MIKRO_BOT\MQL5\Experts\MicroBots\MicroBot_SILVER.mq5) dodano waskie blokady:
  - `SILVER_TREND_CHAOS_POOR_CANDLE_BLOCK`
  - `SILVER_TREND_LOW_POOR_CANDLE_BLOCK`
  - `SILVER_REJECTION_CHAOS_POOR_CANDLE_BLOCK`
- w [RUN_AUTONOMOUS_90P_SUPERVISOR.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\RUN_AUTONOMOUS_90P_SUPERVISOR.ps1):
  - supervisor rozpoznaje wrapper `silver_baseline`
  - supervisor ponawia tuning priorytetow w kazdym cyklu
- w [BUILD_TUNING_PRIORITY_REPORT.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_TUNING_PRIORITY_REPORT.ps1):
  - puste `timed_out` summary z `0` proba nie sa juz traktowane jako prawdziwy wynik testera

## Co wyszlo z baseline
- baseline `SILVER` wystartowal poprawnie na wtornym `MT5`
- ale wrapper dostal `timed_out` po `20` minutach
- z logow terminala wynika, ze test nie zawiesil sie na starcie; po `20` minutach byl dopiero na okolo `19%`
- wniosek: dla `SILVER` dotychczasowy timeout byl za niski i zanieczyszczal evidence pustym summary

## Co uruchomiono dalej
- retest poprawionego `SILVER` z timeoutem `7200s`
- log retestu:
  - `C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\weakest_lab\logs\silver_fix_retest_20260319_200128.log`

## Stan etapu
- poprawka `SILVER` jest skompilowana
- tor `90%` dalej pracuje
- `QDM` i `ML` zostaly utrzymane w tle
- finalny werdykt dla `SILVER` zalezy juz od wyniku wydluzonego retestu
