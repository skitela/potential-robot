# 141 OANDA MT5 Additional Testing Stack V1

## Cel
- zweryfikowac, jakie dodatkowe narzedzia poza samym `OANDA TMS MT5` maja realny sens dla:
  - runtime botow
  - testow i optymalizacji
  - badan historycznych
  - uczenia modeli offline
- oddzielic rzeczy przydatne od blyszczacych dodatkow, ktore tylko komplikuja architekture

## Werdykt ogolny
Najbardziej sensowny stos dla naszego projektu nie jest jednym programem.
To jest uklad warstwowy:

1. `OANDA TMS MT5 + MetaEditor + VPS`
   - wykonanie i runtime
2. `Strategy Tester + lokalne agenty + MetaTester + MQL5 Cloud Network`
   - testy i optymalizacja
3. `Python + magazyn danych + notatniki badawcze`
   - analiza danych, etykietowanie, trening modeli
4. `Custom Symbols + ONNX`
   - badanie na wyselekcjonowanych danych i przenoszenie modelu z powrotem do MT5
5. `TradingView`
   - analityka, alerty i warstwa operatorska, ale nie glowny silnik live-bota

## Co juz mamy lokalnie
### Zainstalowane
- [OANDA TMS MT5 Terminal](C:\Program Files\OANDA TMS MT5 Terminal)
- [MetaTrader 5 Strategy Tester / MetaTester64.exe](C:\Program Files\MetaTrader 5 Strategy Tester\MetaTester64.exe)
- Python 3.12
- pakiet Python `MetaTrader5`
- `pandas`

### Potwierdzone lokalne agenty testera
Na maszynie dzialaja lokalne agenty:
- `Agent-127.0.0.1-3000`
- `Agent-127.0.0.1-3001`
- `Agent-127.0.0.1-3002`
- `Agent-127.0.0.1-3003`
- `Agent-127.0.0.1-3004`
- `Agent-127.0.0.1-3005`

To oznacza, ze mamy juz bazowy lokalny farm testera i nie startujemy od zera.

### Brakuje dzisiaj
Nie wykryto:
- `polars`
- `scikit-learn`
- `onnx`
- `onnxruntime`
- `duckdb`
- `pyarrow`
- `matplotlib`
- `jupyterlab`

## Co z odpowiedzi GPT-5.4 jest trafne
Najmocniejsze, poprawne elementy:
- `MT5 Strategy Tester` powinien zostac glownym laboratorium testowym
- warto korzystac z lokalnych agentow i `MetaTester`
- `MQL5 Cloud Network` ma sens do ciezkich optymalizacji
- `Python + MetaTrader5` to najlepsza warstwa offline do badan i etykietowania
- `ONNX` jest sensownym mostem z modelu ML do MQL5
- `Custom Symbols` sa bardzo wazne do pracy na wybranych historycznych danych
- `TradingView` jest lepszy jako radar/analityka/alerty niz jako glowny silnik live-execution

## Co trzeba doprecyzowac
### 1. Nie wszystko powinno trafic do runtime
Najwiekszy blad architektoniczny bylby taki:
- zrobic z Pythona albo TradingView glowny silnik egzekucji live

Dla naszego projektu poprawny podzial jest taki:
- `MT5` wykonuje i testuje
- `Python` uczy, etykietuje i analizuje offline
- `ONNX` przenosi wybrane modele z powrotem do MQL5

### 2. Cloud Network ma ograniczenia
`MQL5 Cloud Network` jest swietny do optymalizacji, ale:
- nie wolno go uzywac do optymalizacji z `Custom Symbols`
- `Custom Symbols` wolno testowac na lokalnych i zdalnych agentach, ale nie w chmurze MQL5

To jest bardzo wazne, bo u nas wlasnie `Custom Symbols` sa dobrym kierunkiem do badan na wyselekcjonowanych danych.

### 3. TradingView nie powinien byc mozgiem live-bota
Mozna spiac `TradingView` z OANDA/TMS jako kanal dostepu i warstwe alertowa.
Ale nie warto robic z niego glównego egzekutora logiki bota.

Najlepsza rola `TradingView` u nas:
- analiza
- prototypowanie sygnalow
- alerty
- read-only / semi-manual operator workflow

## Co warto dolozyc od razu
### Priorytet A: warstwa badawcza offline
Do instalacji:
- `scikit-learn`
- `matplotlib`
- `duckdb`
- `pyarrow`
- `jupyterlab`

To da nam:
- trening klasycznych modeli
- wykresy i diagnostyke
- szybki lokalny magazyn danych
- zapis danych do `parquet`
- notatniki badawcze do eksperymentow

### Priorytet B: warstwa modelowa do MQL5
Do instalacji:
- `onnx`
- `onnxruntime`
- `skl2onnx` albo `onnxmltools`

To da nam:
- trening modelu offline
- eksport do `ONNX`
- walidacje modelu poza terminalem
- potem wdrozenie modelu w MQL5 i test w `Strategy Tester`

### Priorytet C: warstwa szybszego przetwarzania danych
Do instalacji opcjonalnie:
- `polars`

Sens:
- szybsza obrobka duzych tabel historycznych niz w samym `pandas`

## Co juz mamy sensownie wykorzystac lepiej
### 1. MetaTester / lokalne agenty
Poniewaz mamy juz:
- osobna instalacje `MetaTrader 5 Strategy Tester`
- lokalne agenty `3000-3005`

to najbardziej sensowny nastepny krok nie brzmi:
- kupowac nowy tester

tylko:
- lepiej wykorzystac istniejacy farm testera
- ustandaryzowac workerow
- zautomatyzowac repeatability i delta-reporty

### 2. Custom Symbols
To jest najwazniejsza funkcja, jesli chcemy badac:
- tylko sesje londynskie
- tylko sesje azjatyckie
- tylko dni newsowe
- tylko okna wysokiego spreadu
- tylko wybrane regime'y

Wlasnie tutaj `MT5` daje nam najwieksza wartosc badawcza bez potrzeby kupowania osobnego programu.

## Co warto rozwazac, ale nie wciskac od razu
### TradingView
Warto:
- do alertow
- do wizualnej kontroli rynku
- do prototypowania Pine

Nie warto:
- jako glowny silnik live-bota
- jako zrodlo bezposredniej egzekucji decyzji strategii

### Zewnetrzne frameworki backtestowe
Mozna rozwazac pozniej:
- `vectorbt`
- `backtrader`

ale tylko jako warstwe researchu offline.
Nie sa one naturalnym zamiennikiem `MT5 Strategy Tester` w naszym projekcie.

## Czego bym teraz nie dokladal
- kolejnych "gotowych EA" z marketu bez naszej kontroli
- zewnetrznego egzekutora live poza `MT5`
- DLL-heavy runtime integracji w sciezce decyzyjnej
- mostow, ktore mieszaja zewnetrzne feedy z wykonaniem live bez bardzo ostrej potrzeby

## Rekomendowany stos docelowy dla nas
### Warstwa 1. Runtime
- `OANDA TMS MT5`
- `MetaEditor`
- `MetaTrader VPS`

### Warstwa 2. Testy
- `MT5 Strategy Tester`
- lokalne agenty
- `MetaTester`
- opcjonalnie `MQL5 Cloud Network`

### Warstwa 3. Research offline
- Python
- `MetaTrader5`
- `pandas`
- `duckdb`
- `pyarrow`
- `matplotlib`
- `jupyterlab`

### Warstwa 4. ML deployment
- `scikit-learn`
- `onnx`
- `onnxruntime`
- `skl2onnx` albo `onnxmltools`

### Warstwa 5. Dane selektywne
- `Custom Symbols`
- wlasne zbiory okresow i regime'ow

## Najbardziej sensowny nastepny ruch
1. Doinstalowac pakiet badawczy:
   - `scikit-learn`
   - `matplotlib`
   - `duckdb`
   - `pyarrow`
   - `jupyterlab`
   - `onnx`
   - `onnxruntime`
   - `skl2onnx`
2. Dorobic eksport:
   - `MT5 -> parquet/csv -> Python`
3. Zbudowac pierwszy pipeline:
   - extract
   - clean
   - label
   - train
   - export `ONNX`
   - retest w `MT5 Strategy Tester`

## Zrodla oficjalne
- MetaTrader 5 Strategy Tester:
  - https://www.metatrader5.com/en/terminal/help/algotrading/testing
- Strategy Optimization:
  - https://www.metatrader5.com/en/terminal/help/algotrading/strategy_optimization
- MetaTester and Remote Agents:
  - https://www.metatrader5.com/en/terminal/help/algotrading/metatester
- MQL5 Cloud Network:
  - https://www.metatrader5.com/en/terminal/help/mql5cloud
  - https://www.metatrader5.com/en/terminal/help/mql5cloud/mql5cloud_use
- Python integration:
  - https://www.mql5.com/en/docs/python_metatrader5
- ONNX in MQL5:
  - https://www.mql5.com/en/docs/onnx
- Custom Symbols:
  - https://www.metatrader5.com/en/terminal/help/trading_advanced/custom_instruments
- OANDA + TradingView:
  - https://www.oanda.com/eu-en/tradingview
- TradingView webhooks:
  - https://www.tradingview.com/support/solutions/43000529348-how-to-configure-webhook-alerts/
- TradingView autotrading limitation:
  - https://www.tradingview.com/support/solutions/43000481026-how-to-autotrade-using-pine-script-strategies/
