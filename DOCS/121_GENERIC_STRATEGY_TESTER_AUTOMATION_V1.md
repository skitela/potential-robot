# 121 Generic Strategy Tester Automation V1

## Cel

Zamienic jednorazowy tor `NZDUSD` w narzedzie, ktore da sie stosowac kolejno do wielu instrumentow bez brudzenia runtime floty.

## Co dodano

- `RESET_MICROBOT_STRATEGY_TESTER_SANDBOX.ps1`
  - resetuje sandbox wskazanego instrumentu
- `RUN_MICROBOT_STRATEGY_TESTER.ps1`
  - uruchamia test dla wskazanego instrumentu
  - resetuje sandbox
  - kompiluje experta
  - kopiuje logi
  - zapisuje `result json/txt`
  - zapisuje `summary json`
- `COMPARE_STRATEGY_TESTER_RUNS.ps1`
  - porownuje dwa przebiegi po `summary json`

## Zasada pracy

- automat robi przebiegi i raporty
- czlowiek interpretuje wyniki i zmienia kod
- aktywne `paper/shadow` pozostaje odseparowane

## Status

- narzedzia parsowane poprawnie przez PowerShell parser
- `NZDUSD` zachowalo zgodnosc przez wrapper
- `AUDUSD` zostal uruchomiony juz przez nowy tor generyczny
