# 137 Cost Sample System Repair V1

## Cel

Domknac dwie warstwy, ktore najbardziej psuly wiarygodnosc strojenia:

- falszywe `NON_REPRESENTATIVE` w Strategy Testerze dla rodzin `FX_MAIN`, `FX_ASIA` i `FX_CROSS`,
- brak stabilnej sciezki testera dla instrumentow z aliasem innym niz nazwa katalogu storage, glownie `COPPER-US`.

## Zmiany

### 1. Kalibracja kosztu i reprezentatywnosci dla FX

Plik:
- `MQL5/Include/Core/MbTuningEpistemology.mqh`

Zmiany:
- dodano jawne progi `FX_MAIN` dla:
  - `min_conversion_ratio`
  - `min_conversion_candidates`
  - `max_dirty_ratio`
- dodano jawne benchmarki kosztu dla `FX_MAIN`
- w Strategy Testerze wprowadzono stabilizacje `spread_now` dla rodzin:
  - `FX_MAIN`
  - `FX_ASIA`
  - `FX_CROSS`
- prog `BAD spread -> NON_REPRESENTATIVE` zostal podniesiony dla calych rodzin FX do poziomu, ktory nie karze pojedynczego koncowego skoku spreadu jak calego przebiegu

Efekt:
- pary FX przestaly byc zbyt latwo klasyfikowane jako `NON_REPRESENTATIVE` tylko dlatego, ze tester konczyl run na skrajnej kwotacji

### 2. Tester sandbox dla `COPPER-US`

Plik:
- `MQL5/Experts/MicroBots/MicroBot_COPPERUS.mq5`

Zmiany:
- dodano:
  - `InpEnableStrategyTesterSandbox`
  - `InpStrategyTesterSandboxTag`
- dodano `ConfigureCOPPERUSStrategyTesterSandbox()`
- sandbox jest uruchamiany w `OnInit()`

Efekt:
- `COPPER-US` mozna teraz uruchamiac w izolowanym testerze bez brudzenia aktywnego runtime

### 3. Naprawa runnera testera dla aliasow storage

Plik:
- `TOOLS/RUN_MICROBOT_STRATEGY_TESTER.ps1`

Zmiany:
- runner rozroznia teraz:
  - `symbol_alias` do pracy operatorskiej,
  - `storage_alias` do sciezek sandboxu
- sandbox, reset i odczyt plikow runtime/logs dzialaja teraz po `storage_alias`
- eksport wiedzy dostaje poprawny alias storage

Efekt:
- instrumenty takie jak `COPPER-US` nie wysypuja juz summary/knowledge przez roznice miedzy aliasem a nazwa katalogu

## Wynik retestow

### Trójka kosztowa

- `GBPUSD`
  - `cost: NON_REPRESENTATIVE -> HIGH`
  - dalej: `FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_CANDLE`
- `USDCAD`
  - `cost: NON_REPRESENTATIVE -> HIGH`
  - dalej: `LOW_SAMPLE`
- `USDCHF`
  - `cost: NON_REPRESENTATIVE -> HIGH`
  - dalej: `FOREFIELD_DIRTY_BY_SPREAD_DISTORTION`

### Trójka sample-first

- `NZDUSD`
  - dluzsze okno podnioslo probe z malej runtimeowej bazy do `257` lekcji
  - `cost: NON_REPRESENTATIVE -> HIGH`
  - glowny korek: `FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_HYBRID`
- `GBPJPY`
  - dluzsze okno podnioslo probe do `297` lekcji
  - `cost: NON_REPRESENTATIVE -> HIGH`
  - glowny korek: `PAPER_CONVERSION_BLOCKED_BY_LOW_RATIO`
- `COPPER-US`
  - sandbox i runner sa juz sprawne
  - na krotkim oknie dalej wychodzi:
    - `LOW_SAMPLE`
    - `NON_REPRESENTATIVE_COST`
  - to wyglada bardziej na prawdziwy problem instrumentu niz na artefakt testera

## Wniosek

Najwazniejsza poprawka tej rundy nie dotyczyla samej strategii wejscia, tylko epistemologii laboratorium:

- tester przestal zawyzac koszt dla rodzin FX przez koncowy skok spreadu,
- sample-first przestal oznaczac "za malo danych na zawsze", bo dluzsze okno pokazalo juz prawdziwe kolejne korki,
- `COPPER-US` zostal wlaczony do tego samego, czystego toru badawczego.
