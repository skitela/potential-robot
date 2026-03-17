# NZDUSD Strategy Tester Sandbox V1

## Cel

Przygotowac jednego, najslabszego poznawczo agenta `NZDUSD` do bezpiecznego uruchamiania w `MetaTrader 5 Strategy Tester` bez mieszania:

- aktywnego `paper/shadow`,
- runtime z VPS,
- wspolnych plikow `FILE_COMMON`,
- polityk strojenia i logow calej floty.

## Dlaczego `NZDUSD`

Na dzien `2026-03-17` `NZDUSD` jest jednym z najslabszych kandydatow do nauki:

- `trust_state = LOW_SAMPLE`
- `learning_sample_count = 39`
- `learning_win_count = 0`
- `learning_loss_count = 39`
- praktycznie brak sensownych nowych lekcji `paper`

To czyni go dobrym kandydatem do pierwszego, izolowanego testu historycznego.

## Co zostalo zmienione

### 1. Wspolna warstwa storage

Dodano w [MbStoragePaths.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbStoragePaths.mqh):

- `MbSetRootPathOverride(...)`
- `MbClearRootPathOverride()`
- `MbIsStrategyTesterRuntime()`
- `MbEnableStrategyTesterSandbox(...)`
- `MbStoragePathSanitizeToken(...)`

To pozwala jednemu EA przelaczyc root `FILE_COMMON` na osobny sandbox bez naruszania reszty systemu.

### 2. Lokalny agent `NZDUSD`

W [MicroBot_NZDUSD.mq5](C:\MAKRO_I_MIKRO_BOT\MQL5\Experts\MicroBots\MicroBot_NZDUSD.mq5) dodano:

- `InpEnableStrategyTesterSandbox = true`
- `InpStrategyTesterSandboxTag = "NZDUSD_AGENT"`
- `ConfigureNZDUSDStrategyTesterSandbox()`

W `OnInit()` przy runtime testera:

- agent przelacza sie na osobny root:
  - `MAKRO_I_MIKRO_BOT_TESTER_NZDUSD_NZDUSD_AGENT`

W efekcie jego:

- `runtime_state.csv`
- `paper_position.csv`
- `tuning_policy.csv`
- `tuning_actions.csv`
- `tuning_deckhand.csv`
- `learning_observations_v2.csv`
- `decision_events.csv`

nie mieszaja sie z glownym `MAKRO_I_MIKRO_BOT`.

### 3. Reset sandboxu

Dodano narzedzie:

- [RESET_NZDUSD_STRATEGY_TESTER_SANDBOX.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\RESET_NZDUSD_STRATEGY_TESTER_SANDBOX.ps1)

Skrypt usuwa tylko katalog:

- `MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT_TESTER_NZDUSD_NZDUSD_AGENT`

czyli czyści testera bez ryzyka dla aktywnego runtime.

## Jak uzywac

1. Przed nowym testem uruchomic reset sandboxu.
2. W `Strategy Tester` wybrac `MicroBot_NZDUSD`.
3. Zostawic:
   - `InpEnableLiveEntries = false`
   - `InpPaperCollectMode = true`
   - `InpEnableStrategyTesterSandbox = true`
4. Uruchomic pojedynczy test, nie pelna optymalizacje floty.
5. Po tescie analizowac wyniki tylko w sandboxie testera.

## Ograniczenia

- To nie jest jeszcze tryb testerowy calej floty.
- To nie rozwiazuje jeszcze problemu wspoldzielonych rodzin i koordynatora dla wszystkich 17 botow naraz.
- To jest celowo pierwszy, waski krok dla jednego symbolu.

## Oczekiwany efekt

Zyskujemy bezpieczne laboratorium dla `NZDUSD`, ktore:

- nie zanieczyszcza produkcyjnego `paper`,
- pozwala historycznie sprawdzic genotyp i filtry,
- daje czystszy material do odpowiedzi: czy `NZDUSD` jest slaby strategicznie, czy tylko zbyt ubogi w biezacy runtime.
