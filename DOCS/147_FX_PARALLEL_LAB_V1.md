# 147 FX Parallel Lab V1

## Cel
- domknac `FX` jako osobne okno robocze
- pracowac rownolegle bez konfliktu na jednym `MT5 TerminalDataDir`
- rozdzielic:
  - `MT5 Strategy Tester`
  - `QDM / custom data`
  - `ML offline`

## 3 okna FX
### Okno 1 - MT5 tester
- [RUN_FX_MT5_BATCH.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\RUN_FX_MT5_BATCH.ps1)
- [START_FX_MT5_BATCH_BACKGROUND.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_FX_MT5_BATCH_BACKGROUND.ps1)

Uruchamia tester `MT5/OANDA` dla:
- `EURUSD`
- `GBPUSD`
- `AUDUSD`
- `USDJPY`
- `USDCHF`
- `USDCAD`
- `NZDUSD`
- `EURJPY`
- `GBPJPY`
- `EURAUD`

### Okno 2 - FX data lane
- [qdm_fx_focus_pack.csv](C:\MAKRO_I_MIKRO_BOT\TOOLS\qdm_fx_focus_pack.csv)
- [RUN_FX_QDM_PIPELINE.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\RUN_FX_QDM_PIPELINE.ps1)
- [START_FX_QDM_PIPELINE_BACKGROUND.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_FX_QDM_PIPELINE_BACKGROUND.ps1)

To jest tor:
- `QDM sync`
- `QDM export`
- `MT5 custom symbols`

### Okno 3 - ML offline
- [TRAIN_MICROBOT_ML_STACK.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\TRAIN_MICROBOT_ML_STACK.ps1)
- [REFRESH_AND_TRAIN_MICROBOT_ML.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\REFRESH_AND_TRAIN_MICROBOT_ML.ps1)
- [START_REFRESH_AND_TRAIN_MICROBOT_ML_BACKGROUND.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_REFRESH_AND_TRAIN_MICROBOT_ML_BACKGROUND.ps1)

## Dlaczego nie 2 okna MT5 naraz
Na obecnym setupie:
- jeden `MT5` tester korzysta z jednego `TerminalDataDir`
- drugi rownolegly tester moglby nadpisywac logi, raporty i profil

Dlatego bez dodatkowego, osobnego `MT5 data dir` bezpieczny uklad jest taki:
- `1` okno online `MT5 tester`
- `1` okno `QDM`
- `1` okno `ML offline`

## Status
- [GET_FX_LAB_STATUS.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\GET_FX_LAB_STATUS.ps1)
- [START_FX_LAB_3_WINDOWS.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_FX_LAB_3_WINDOWS.ps1)

## Granice uczenia
- `MT5 tester` dalej jest glownym testerem strategii
- `QDM` dostarcza dane do badan i `Custom Symbols`
- `ML` jest offline i nie steruje live execution
- agenci strojenia i wewnetrzne uczenie dalej maja sens, ale tylko jako warstwa lokalna/runtime
- offline `ML` nie zapisuje nic sam do logiki botow
