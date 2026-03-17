# Samonaprawa i Watchdog

## Cel

Nowy system `MAKRO_I_MIKRO_BOT` ma trzy poziomy obrony:

1. mikro-bot sam przechodzi w bezpieczniejszy tryb (`CAUTION`, `CLOSE_ONLY`, `HALT`)
2. watchdog runtime pilnuje, czy caly park nadal zyje i odswieza heartbeat
3. gdy stan jest zly, watchdog wykonuje kontrolowany restart `MT5`

## Zakres obecnej wersji

Skrypt:

- `TOOLS\RUN_RUNTIME_WATCHDOG_PL.ps1`

sprawdza:

- czy dziala `terminal64`
- czy wszystkie `11` par maja swiezy `heartbeat`
- czy istnieje `runtime_state.csv`
- czy istnieje `execution_summary.json`

Jesli wykryje problem:

- oznacza status `OSTRZEZENIE` albo `WYMAGA_NAPRAWY`
- a jesli moze, wykonuje restart przez:
  - `RUN\OPEN_OANDA_MT5_WITH_MICROBOTS.ps1`

## Raporty

Watchdog zapisuje:

- `EVIDENCE\runtime_watchdog_status.json`
- `EVIDENCE\runtime_watchdog_status.txt`
- `RUN\runtime_watchdog_state.json`

## Panel operatora

Panel:

- `RUN\PANEL_OPERATORA_PL.ps1`

pokazuje:

- glowny stan systemu
- stan warstwy naprawczej
- przycisk `Sprawdz i napraw teraz`

## Zasada bezpieczenstwa

Watchdog:

- nie zmienia logiki strategii
- nie rusza `Core`
- nie wlacza live handlu
- pilnuje tylko zycia runtime i zdolnosci systemu do zbierania danych
