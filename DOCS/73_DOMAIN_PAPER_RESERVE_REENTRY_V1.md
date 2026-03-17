# 73. Domain Paper, Reserve and Reentry V1

## Cel

Ta warstwa spina wspolny zegar domen (`FX`, `METALS`, `INDICES`) z ochrona kapitalu i stanami pracy:

- `RUN`
- `CLOSE_ONLY`
- `PAPER_ONLY`
- `HALT`

Nie zmienia ona logiki strategii mikro-bota. Zmienia tylko to, czy dana domena ma prawo:

- handlowac live,
- tylko domykac,
- pracowac wyłącznie w paper,
- albo zostac calkowicie zatrzymana.

## Zasada nadrzedna

Po naruszeniu kapitalu system nie ma przestawac widziec rynku. Ma przestawac ryzykowac live.

Dlatego degradacja przebiega tak:

- naruszenie rodzinne lub flotowe nie zabija telemetryki,
- aktywna domena schodzi do `PAPER_ONLY`,
- agent strojenia dalej zbiera dane i obserwuje skutki,
- powrot do `RUN` wymaga lepszego dowodu niz samo zejscie do `PAPER_ONLY`.

## Gdzie to jest wpiete

### 1. Globalny koordynator sesji i kapitalu

Pliki:

- `CONFIG/session_capital_coordinator_v1.json`
- `TOOLS/APPLY_SESSION_CAPITAL_COORDINATOR.ps1`
- `TOOLS/VALIDATE_SESSION_CAPITAL_COORDINATOR.ps1`

Koordynator:

- czyta okna operatora w czasie polskim,
- czyta stany rodzin i floty z `Common Files`,
- decyduje o `requested_mode` dla domen,
- zapisuje domenowe `runtime_control.csv`,
- zapisuje `session_capital_state.csv` dla kazdej domeny.

### 2. Runtime control po stronie MQL5

Plik:

- `MQL5/Include/Core/MbRuntimeControl.mqh`

Warstwa runtime rozumie teraz:

- `HALT`
- `PAPER_ONLY`
- `CLOSE_ONLY`

Priorytet:

1. `HALT`
2. `PAPER_ONLY`
3. `CLOSE_ONLY`

### 3. Mikro-boty

Kazdy mikro-bot ma teraz lokalny helper:

- `IsLocalPaperModeActive()`

Helper zwraca `true`, gdy:

- operator wlaczyl `InpPaperCollectMode`,
- albo domena dostala z gory `PAPER_ONLY`.

To rozwiazuje dwa problemy:

- paper nie jest juz tylko lokalna opcja bota,
- powrot z `paper` nie jest lepkim stanem zapisanym w runtime, tylko wynika z biezacej decyzji koordynatora.

## Jak dziala decyzja domenowa

Kazda domena ma najpierw stan okna:

- `SLEEP`
- `PREWARM`
- `LIVE`
- `PAPER_SHADOW`
- `RESERVE_RESEARCH`

Potem ten stan jest filtrowany przez:

- `manual_override`,
- `active_runtime`,
- blokade rodzinna,
- blokade flotowa,
- gotowosc do reentry.

### Normalna mapa

- `SLEEP` -> `CLOSE_ONLY`
- `PREWARM` -> `CLOSE_ONLY`
- `LIVE` -> `RUN`
- `PAPER_SHADOW` -> `CLOSE_ONLY`
- `RESERVE_RESEARCH` -> `CLOSE_ONLY`

### Po blokadzie kapitalowej

Jesli domena jest w oknie innym niz `SLEEP` i zostanie zablokowana przez rodzine albo flote:

- przechodzi do `PAPER_ONLY`

Czyli:

- nie otwiera live,
- ale dalej pracuje papierowo,
- dalej zbiera kandydata, wejscia i wynik syntetyczny.

## Zrodla blokady

Koordynator czyta:

- `state/_families/<family>/tuning_family_policy.csv`
- `state/_coordinator/tuning_coordinator_state.csv`

Blokada rodzinna:

- `paper_mode_active = 1`
- albo `trust_reason = FAMILY_DAILY_LOSS_HARD`

Blokada flotowa:

- `paper_mode_active = 1`
- albo `trust_reason = FLEET_DAILY_LOSS_HARD`

## Reentry tego samego dnia

Powrot do `RUN` jest mozliwy tylko dla aktywnego okna `LIVE`.

W `v1` wymagamy:

- blokada byla rodzinna, nie flotowa,
- rodzina ma `trusted_data = 1`,
- flota ma `trusted_data = 1`,
- `family_daily_loss_pct` spadlo ponizej `60%` rodzinnego limitu live,
- `fleet_daily_loss_pct` spadlo ponizej `60%` flotowego limitu live.

To daje histereze:

- spasc do `PAPER_ONLY` mozna szybko,
- wracac do `RUN` trzeba wolniej i na mocniejszym dowodzie.

## Reserve domain

Koordynator zapisuje tez:

- `reserve_candidate`
- `reserve_activated`

W `v1` rezerwa jest bezpieczna i konserwatywna:

- nie budzimy domeny poza jej wlasnym zywym albo prewarm window,
- rezerwa moze zostac oznaczona jako aktywna tylko wtedy, gdy sama juz zyje w swoim sensownym czasie,
- nie wymuszamy jeszcze out-of-window live.

To jest celowe. Najpierw porzadkujemy stany kapitalowe, dopiero potem agresywniejsze przejmowanie okien.

## Dlaczego to nie psuje latencji

Ta warstwa:

- dziala poza hot-path,
- jest liczona timerowo w PowerShell,
- mikro-bot tylko czyta prosty wynik `runtime_control.csv`,
- nie musi na kazdym ticku analizowac calej floty.

Czyli:

- myslenie jest centralne i wolne,
- wykonanie pozostaje lokalne i szybkie.

## Ograniczenia V1

- `INDICES` nie sa jeszcze runtime deployed, wiec koordynator moze je logicznie widziec, ale trzyma je w `CLOSE_ONLY`.
- `reserve_activated` w `v1` jest glownie sygnalem operacyjnym; nie przenosi jeszcze live poza naturalne okno rezerwy.
- `reentry` jest domenowo-rodzinne; nie ma jeszcze oddzielnego arbitra probacyjnego per symbol.

## Stan po wdrozeniu

- wszystkie 15 mikro-botow rozumie `PAPER_ONLY`,
- koordynator sesji i kapitalu zapisuje blokady, reentry i rezerwy do `Common Files`,
- zachowany jest kontrakt kapitalu i oddzielenie `paper` od `live`.
