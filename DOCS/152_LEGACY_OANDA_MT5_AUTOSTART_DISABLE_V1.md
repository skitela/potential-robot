# 152 Legacy OANDA MT5 Autostart Disable V1

## Cel

Odciac stary system `C:\OANDA_MT5_SYSTEM` od:

- autostartu po logowaniu,
- automatycznego otwierania operator panelu,
- cyklicznych zadan treningowo-audytowych,

tak zeby nie mieszal sie z biezacym labem `MAKRO_I_MIKRO_BOT`.

## Co bylo uruchamiane automatycznie

Zidentyfikowane zrodla autostartu:

- skrót `OANDA Operator Panel.lnk` w folderze `Startup`
- zadania Harmonogramu:
  - `OANDA_MT5_FX_NEXT_WINDOW_AUDIT_DAILY_USER`
  - `OANDA_MT5_LAB_DAILY`
  - `OANDA_MT5_LAB_INSIGHTS_Q3H`
  - `OANDA_MT5_LATENCY_AUDIT_DAILY_USER`
  - `OANDA_MT5_NIGHTLY_TESTBOOK_USER`
  - `OANDA_MT5_STAGE1_LEARNING_DAILY_USER`
  - `OANDA_MT5_STAGE1_SHADOW_PLUS_HOURLY_USER`
  - `OANDA_MT5_WEEKLY_BACKUP`

Nie znaleziono dodatkowych wpisow w:

- `HKCU/HKLM ...\\Run`
- uslugach systemowych

## Co zostalo zrobione

- skrót `OANDA Operator Panel.lnk` zostal wyniesiony do:
  - `C:\OANDA_MT5_SYSTEM\STATE\disabled_autostart\OANDA Operator Panel.lnk`
- wszystkie powyzsze zadania zostaly przelaczone do stanu `Disabled`
- przygotowany zostal powtarzalny skrypt:
  - [DISABLE_LEGACY_OANDA_MT5_AUTOSTART.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\DISABLE_LEGACY_OANDA_MT5_AUTOSTART.ps1)

## Potwierdzenie

Po wykonaniu:

- oryginalny skrót w folderze `Startup` nie istnieje
- kopia bezpieczna istnieje w `STATE\\disabled_autostart`
- wszystkie zadania `OANDA_MT5_*` maja `Enabled = False`

## Skutek operacyjny

Po kolejnym logowaniu:

- stary `OANDA_MT5_SYSTEM` nie powinien sam otwierac panelu,
- nie powinien sam uruchamiac cyklicznych audytow/labow,
- nie powinien mieszac portow, dashboardow i logow z biezacym torem roboczym.
