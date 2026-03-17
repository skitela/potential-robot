# EURUSD Context Layer V1

## Cel

Dolozyc do `MicroBot_EURUSD` lekka warstwe oceny warunkow rynku inspirowana starym `SafetyBot`, ale bez mostu Pythonowego i bez ciezkiego narzutu w `OnTick`.

## Warstwy

### 1. Warstwa bazowa

Lokalna strategia `EURUSD` nadal generuje bazowy sygnal:
- `SETUP_TREND`
- `SETUP_PULLBACK`
- `SETUP_BREAKOUT`
- `SETUP_REJECTION`

Ta warstwa pozostaje lokalna dla `EURUSD`.

### 2. Warstwa oceny kontekstu

Dodana warstwa ocenia:
- `market_regime`
- `spread_regime`
- `execution_regime`
- `confidence_score`
- `confidence_bucket`
- `risk_multiplier`

Klasy rynku:
- `TREND`
- `BREAKOUT`
- `RANGE`
- `CHAOS`

Klasy spreadu:
- `GOOD`
- `CAUTION`
- `BAD`

Klasy execution:
- `GOOD`
- `CAUTION`
- `BAD`

### 3. Warstwa wykonawczo-ryzykowna

Nowa warstwa nie zmienia sygnalu bazowego, ale:
- moze odrzucic wejscie przy niskim zaufaniu,
- moze zmniejszyc lot przez `risk_multiplier`,
- zapisuje kontekst do dalszego uczenia.

## Nowe pliki

- `MQL5/Include/Core/MbContextPolicy.mqh`
- `MQL5/Include/Core/MbLearningContext.mqh`

## Zmiany wspolne

Rozszerzono:
- `MbRuntimeState`
- `MbSignalDecision`
- `runtime_state.csv`
- `informational_policy.json`
- `execution_summary.json`

Nowe pola runtime:
- `signal_confidence`
- `signal_risk_multiplier`
- `market_regime`
- `spread_regime`
- `execution_regime`
- `confidence_bucket`
- `last_setup_type`

## Zmiany w EURUSD

`Strategy_EURUSD.mqh`:
- klasyfikuje reżim rynku na bazie `EMA`, `ATR`, `RSI`
- liczy `confidence_score`
- przypisuje `risk_multiplier`
- moze zablokowac wejscie przy `CONTEXT_LOW_CONFIDENCE`

`MicroBot_EURUSD.mq5`:
- zapisuje ocene kontekstu do runtime
- skaluje lot przez `risk_multiplier`
- zapisuje paper/live zamkniecia z kontekstem do `learning_observations.csv`

## Cel propagacji

To jest wersja wzorcowa tylko dla `EURUSD`.

Jesli kierunek bedzie dobry, mozna potem:
- przeniesc wspolny `MbContextPolicy.mqh` do rodziny `FX_MAIN`
- zostawic lokalne setupy i progi w poszczegolnych parach
- nie centralizowac genetyki sygnalu

## Walidacja poranna 2026-03-13

Po porannej analizie i poprawkach:
- `TRADE_DISABLED` w `paper mode` nie blokuje juz slepo samego uczenia,
- `EURUSD` nie nadpisuje juz ostatniego poprawnego kontekstu pustym
  `UNKNOWN/NONE` przy `WAIT_NEW_BAR`,
- runtime utrzymuje juz sensowny ostatni kontekst, np.:
  - `market_regime=BREAKOUT`
  - `spread_regime=GOOD`
  - `execution_regime=GOOD`
  - `confidence_bucket=HIGH`
  - `last_setup_type=SETUP_TREND`
- koszt latencji pozostaje niski i nie wskazuje, ze ta warstwa psuje
  lekki charakter `EURUSD`.
