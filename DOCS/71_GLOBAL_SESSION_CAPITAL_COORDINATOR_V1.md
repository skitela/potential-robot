# 71. Global Session Capital Coordinator V1

## Cel

Ten etap wprowadza pierwsza realna warstwe ponad rodzinami i domenami:

- wspolny koordynator sesji,
- wspolny koordynator rytmu dnia,
- wspolny dyspozytor stanów domen:
  - `RUN`
  - `CLOSE_ONLY`
  - `HALT`

To nie jest jeszcze pelna inteligencja reentry i substytucji po stracie.
To jest pierwszy praktyczny szkielet, ktory:

- zna okna czasowe,
- zna domeny,
- zna priorytety domen,
- i potrafi narzucic domenie wspolny stan operacyjny.

## Architektura

Koordynator bierze dane z:

- `CONFIG\\session_window_matrix_v1.json`
- `CONFIG\\session_capital_coordinator_v1.json`
- `CONFIG\\microbots_registry.json`

I rozklada stan do `Common Files` w postaci:

- `state\\_global\\session_capital_coordinator.csv`
- `state\\_domains\\FX\\runtime_control.csv`
- `state\\_domains\\METALS\\runtime_control.csv`
- `state\\_domains\\INDICES\\runtime_control.csv`
- oraz odpowiadajacych im `session_capital_state.csv`

## Jak to dziala

Kazda domena dostaje stan wynikajacy z:

- czasu operatora w Polsce,
- aktualnego okna sesyjnego,
- trybu okna:
  - `TRADE`
  - `OBSERVATION_ONLY`
  - `FUTURE_RESEARCH`
- oraz manualnego override domeny.

Mapowanie v1:

- okno `TRADE` -> `RUN`
- `PREWARM` -> `CLOSE_ONLY`
- `OBSERVATION_ONLY` -> `CLOSE_ONLY`
- `FUTURE_RESEARCH` -> `CLOSE_ONLY`
- brak okna -> `CLOSE_ONLY`
- manual `HALT` -> `HALT`

Czyli v1 nie zmusza systemu do hazardowego działania poza jego naturalnym rytmem.

## Integracja z mikro-botami

Mikro-boty nie dostaly nowej ciezkiej logiki dziennej.

Zostaly jedynie nauczone czytac:

- lokalny `runtime_control`
- oraz domenowy `runtime_control`

i scalać te warstwy bez utraty lokalnych override'ow.

To jest zgodne z naszym celem:

- lekki hot-path,
- ciezsze myslenie poza tickiem.

## Budzety dnia

Koordynator ma juz pierwszy podzial rytmu dnia na grupy:

- `FX_ASIA = 0.18`
- `FX_AM = 0.27`
- `INDEX_EU = 0.15`
- `METALS = 0.20`
- `INDEX_US = 0.20`

W v1 sa to budzety organizacyjne i obserwacyjne dla koordynatora dnia.

Nie sa jeszcze pelnym egzekwowaniem strat okna w runtime.

## Rezerwy

V1 przygotowuje tez strukture rezerw:

- `FX_AM` moze wskazywac `INDICES`
- `METALS` moze wskazywac `INDICES`
- `INDEX_US` moze wskazywac `METALS`

Na tym etapie rezerwy sa juz zapisane w stanie domeny, ale nie maja jeszcze pelnej automatycznej rekonwalescencji `primary -> reserve -> reentry`.

To bedzie kolejny krok.

## Najwazniejszy efekt

Od teraz organizm zaczyna miec jeden wspolny zegar operacyjny.

Nie tylko symbole wiedza, kiedy handlowac.
Wie to tez cala domena.

I wlasnie to jest fundament pod dalsza logike:

- zejscia do `paper`,
- uruchamiania rezerwy,
- reentry po poprawie,
- i dziennej dyscypliny kapitalowej w skali calego organizmu.
