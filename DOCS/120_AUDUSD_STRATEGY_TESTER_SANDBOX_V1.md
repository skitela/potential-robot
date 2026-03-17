# 120 AUDUSD Strategy Tester Sandbox V1

## Cel

Przygotowac `AUDUSD` jako drugi instrument do bezpiecznej pracy w `MetaTrader 5 Strategy Tester`, bez mieszania z aktywnym `paper/shadow` i bez brudzenia floty.

## Co zrobiono

- `MicroBot_AUDUSD.mq5` dostal:
  - `InpEnableStrategyTesterSandbox`
  - `InpStrategyTesterSandboxTag`
  - `ConfigureAUDUSDStrategyTesterSandbox()`
- powstaly generyczne narzedzia:
  - `RESET_MICROBOT_STRATEGY_TESTER_SANDBOX.ps1`
  - `RUN_MICROBOT_STRATEGY_TESTER.ps1`
  - `COMPARE_STRATEGY_TESTER_RUNS.ps1`

## Efekt

- `AUDUSD` moze teraz byc testowany w osobnym sandboxie `FILE_COMMON`
- wyniki testera mozna porownywac miedzy przebiegami bez brudzenia aktywnego runtime

## Tryb pracy

- human-in-the-loop
- automat robi przebiegi i raporty
- zmiany w kodzie wdraza tylko inzynier
