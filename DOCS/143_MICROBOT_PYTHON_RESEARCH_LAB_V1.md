# 143 MicroBot Python Research Lab V1

## Cel
- dolozyc warstwe `Python offline` do badan i uczenia mikrobotow
- nie mieszac jej z runtime `MQL5`
- zautomatyzowac eksport danych z `MT5` i `Strategy Tester`

## Co zostalo zrobione
### 1. Osobne srodowisko Python
Utworzono osobny `venv`:
- [C:\TRADING_TOOLS\MicroBotResearchEnv](C:\TRADING_TOOLS\MicroBotResearchEnv)

To jest celowe oddzielenie od globalnego Pythona.

### 2. Zainstalowane pakiety badawcze
W srodowisku research zainstalowano:
- `MetaTrader5`
- `pandas`
- `numpy`
- `scikit-learn`
- `duckdb`
- `pyarrow`
- `matplotlib`
- `jupyterlab`
- `onnx`
- `onnxruntime`
- `skl2onnx`
- `polars`

Lista referencyjna:
- [requirements_microbot_research.txt](C:\MAKRO_I_MIKRO_BOT\TOOLS\requirements_microbot_research.txt)

### 3. Automatyczny eksport danych do research
Dodano skrypt:
- [EXPORT_MT5_RESEARCH_DATA.py](C:\MAKRO_I_MIKRO_BOT\TOOLS\EXPORT_MT5_RESEARCH_DATA.py)

Skrypt zbiera dane z:
- `Common Files\MAKRO_I_MIKRO_BOT\state`
- `Common Files\MAKRO_I_MIKRO_BOT\logs`
- `EVIDENCE\STRATEGY_TESTER`

I buduje:
- `csv`
- `parquet`
- jedna baze `duckdb`

### 4. Launcher odswiezania datasetu
Dodano:
- [REFRESH_MICROBOT_RESEARCH_DATA.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\REFRESH_MICROBOT_RESEARCH_DATA.ps1)

### 5. Launcher laboratorium badawczego
Dodano:
- [OPEN_MICROBOT_RESEARCH_LAB.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\OPEN_MICROBOT_RESEARCH_LAB.ps1)

### 6. Launcher pelnego startu research
Dodano:
- [START_MICROBOT_RESEARCH_WORKSPACE.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_MICROBOT_RESEARCH_WORKSPACE.ps1)

Ten launcher:
- najpierw odswieza dataset research
- potem otwiera `JupyterLab`

## Katalogi research
Glowny katalog:
- [C:\TRADING_DATA\RESEARCH](C:\TRADING_DATA\RESEARCH)

W nim:
- `datasets`
- `notebooks`
- `reports`
- `microbot_research.duckdb`

## Zasada architektoniczna
Python:
- nie steruje live execution
- nie siedzi na chartach
- nie jest czescia silnika `MQL5`

Python:
- uczy
- analizuje
- etykietuje
- przygotowuje modele offline

## Co mamy od razu po wdrozeniu
1. gotowy `venv`
2. gotowy `jupyterlab`
3. gotowy eksport do `parquet`
4. gotowy magazyn `duckdb`
5. gotowy punkt startowy pod `ONNX`

## Najbardziej sensowny nastepny ruch
1. odswiezyc dataset:
   - uruchomic [REFRESH_MICROBOT_RESEARCH_DATA.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\REFRESH_MICROBOT_RESEARCH_DATA.ps1)
2. otworzyc lab:
   - uruchomic [OPEN_MICROBOT_RESEARCH_LAB.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\OPEN_MICROBOT_RESEARCH_LAB.ps1)
3. albo uruchomic wszystko jednym krokiem:
   - [START_MICROBOT_RESEARCH_WORKSPACE.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_MICROBOT_RESEARCH_WORKSPACE.ps1)
4. zrobic pierwszy notebook:
   - analiza `candidate -> paper`
   - analiza `foreground dirty`
   - analiza `risk contract`
5. dopiero potem budowac pierwszy model pomocniczy do `ONNX`
