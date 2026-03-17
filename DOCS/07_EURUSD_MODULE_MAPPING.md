# EURUSD Module Mapping To Core / Profile / Strategy

## Cel

Ten dokument rozpisuje, jak dojrzaly mikro-bot `EURUSD` z:

- `C:\GLOBALNY HANDEL VER1\EURUSD`

powinien byc analizowany i mapowany do nowego projektu:

- `C:\MAKRO_I_MIKRO_BOT`

## Zasada

Kazdy modul oceniamy pytaniem:

`czy to jest wspolny kod, czy lokalna inteligencja symbolu?`

Tylko wspolny kod moze trafic do `Core`.

## Mapa Modulow

### Zostaje Glownie W MicroBot / Strategy

#### `GH_EURUSD_MQL5_Only.mq5`

Powinno zostac rozciete ostroznie:

- lokalny lifecycle `EURUSD` pozostaje w `MicroBot_EURUSD`
- symbolowe decyzje wejscia pozostaja w `Strategy_EURUSD`
- lokalne zarzadzanie pozycja pozostaje w `Strategy_EURUSD`

Nie kopiowac 1:1 do `Core`.

Nowy stan:

- lokalny management pozycji i trailing zostaly juz czesciowo odtworzone dla `EURUSD`,
- pozostaly po stronie wzorca i nie trafily do `Core`,
- ta sama zasada zostala juz potwierdzona analogiami `GBPUSD`, `USDJPY`, `NZDUSD`, `USDCAD`, `USDCHF`, `AUDUSD`, `EURJPY`, `GBPJPY`, `EURAUD` i `GBPAUD`.

#### `EURUSD_Learning.mqh`

Status:

- glownie `Strategy / local runtime`

Powod:

- lokalne biasy,
- lokalny feedback po zamknietych transakcjach,
- lokalne granice adaptacji.

#### `scudfab02.mqh`

Status:

- glownie `Strategy`

Powod:

- tiebreak i werdykt sa czescia logiki symbolowej.

Nowy stan:

- `Strategy_EURUSD.mqh` dostala juz pierwszy lokalny scoring oparty o `EMA/ATR/RSI`,
- logika triggera nowego bara i lokalny setup ranking zostaly zachowane po stronie strategii,
- to nie trafilo do `Core`,
- analogicznie lokalne scoringi pozostaly juz w `Strategy_GBPUSD`, `Strategy_USDJPY`, `Strategy_NZDUSD`, `Strategy_USDCAD`, `Strategy_USDCHF`, `Strategy_AUDUSD`, `Strategy_EURJPY`, `Strategy_GBPJPY`, `Strategy_EURAUD` i `Strategy_GBPAUD`.

#### `black_swan_guard.mqh`

Status:

- glownie `MicroBot / Profile`

Powod:

- lokalna wrazliwosc pary,
- lokalne okna newsowe,
- lokalne reakcje na wydarzenia makro.

Do `Core` moga trafic tylko helpery kalendarza i wspolne struktury.

#### `risk_manager.mqh`

Status:

- glownie `MicroBot`

Powod:

- sizing i ochrona kapitalu musza pozostac lokalne dla bota.

Do `Core` moga trafic tylko bardzo niskopoziomowe helpery obliczeniowe.

Nowy stan:

- pierwszy lokalny sizing dla `EURUSD` zostal juz odtworzony po stronie `Strategy_EURUSD` i `MicroBot_EURUSD`,
- nie zostal wyniesiony do `Core`,
- `Core` dostarcza tylko wspolny precheck wykonania,
- ta sama zasada zostala juz utrzymana dla `GBPUSD`, `USDJPY`, `NZDUSD`, `USDCAD`, `USDCHF`, `AUDUSD`, `EURJPY`, `GBPJPY`, `EURAUD` i `GBPAUD`.

#### `EURUSD_Guards.mqh`

Status:

- podzial

Do `MicroBot`:

- logika okien,
- symbolowe caps,
- finalne veto wejscia.

Do `Core`:

- helpery ogolne typu trade permission checks,
- helpery stale tick / spread cap check.
- wspolne guardy cooldown / margin / loss caps / entry frequency.

#### `EURUSD_Execution.mqh`

Status:

- podzial

Do `MicroBot`:

- finalny execution flow,
- lokalna polityka wykonania.

Do `Core`:

- retcode naming,
- helpery `OrderCheck`,
- helpery margin precheck,
- helpery wolumenu i walidacji.

Nowy stan:

- `MbExecutionCommon.mqh` trzyma juz wspolne retcode / retry / filling helpery,
- `MbExecutionPrecheck.mqh` trzyma juz wspolny precheck `OrderCalcMargin + OrderCheck + quote tolerance + stop distance`,
- `MbExecutionSend.mqh` trzyma juz wspolny lokalny wrapper `send/retry`,
- `MbExecutionFeedback.mqh` trzyma juz wspolny lokalny update execution pressure / telemetry / incident note,
- finalne wyslanie zlecenia nadal pozostaje lokalne dla mikro-bota,
- finalny live-send zostal juz potwierdzony lokalnie w calej partii `11`: `EURUSD`, `GBPUSD`, `USDJPY`, `NZDUSD`, `USDCAD`, `USDCHF`, `AUDUSD`, `EURJPY`, `GBPJPY`, `EURAUD`, `GBPAUD`.

#### `OnTradeTransaction` flow z `GH_EURUSD_MQL5_Only.mq5`

Status:

- podzial

Do `Core`:

- lokalny journaling zdarzen transakcyjnych
- wspolny helper dopasowania zdarzenia do symbolu i `magic`

Do `MicroBot`:

- lokalna interpretacja co dane zdarzenie oznacza dla strategii
- lokalne uczenie po zamknieciach i lokalne aktualizacje PnL

Nowy stan:

- `MbTradeTransactionJournal.mqh` trzyma juz wspolny lokalny journaling `OnTradeTransaction`,
- `MbClosedDealTracker.mqh` trzyma juz wspolny lokalny update `realized_pnl_day/session`, `last_closed_deal_ticket` i `loss_streak`,
- strategia i learning symbolowy nadal pozostaja lokalne.

### Nadaje Sie Do Core

#### `EURUSD_Storage.mqh`

Status:

- w duzej czesci `Core`

Powod:

- sciezki `FILE_COMMON`,
- helpery tworzenia katalogow,
- zapis i odczyt stanu to wspolny wzorzec.

Uwaga:

- struktura konkretnego runtime state nadal zalezy od mikro-bota.

#### `decision_events.mqh`

Status:

- `Core`

Powod:

- to wspolny journaling decyzji.

#### `execution_telemetry.mqh`

Status:

- `Core`

Powod:

- to wspolny journaling telemetryki wykonania.

#### `incident_journal.mqh`

Status:

- `Core`

Powod:

- wspolna klasyfikacja retcode i zapis incydentow.

#### `config_integrity_plane.mqh`

Status:

- `Core`

Powod:

- atomic write,
- config envelope,
- wspolny kontrakt integralnosci.

#### `status_plane_common.mqh`

Status:

- `Core`

Powod:

- wspolny runtime status snapshot i helpery statusowe.

#### `runtime_control_plane.mqh`

Status:

- `Core`

Powod:

- lokalny odczyt `halt/close_only` to wspolny wzorzec.

#### `broker_rate_guard.mqh`

Status:

- `Core`

Powod:

- wspolne budzety requestow i zlecen.

#### `market_state_cache.mqh`

Status:

- `Core`

Powod:

- snapshot rynku i swiezosc ticka sa wspolne.

#### Nowy stan migracji

Po ostatnim etapie do `Core` trafily juz pierwsze dojrzalsze klocki guardowe:

- `MbMarketGuards.mqh`
- wspolne profile limitow spread / tick freshness / margin / loss caps
- odswiezanie dziennych i sesyjnych anchorow equity

To nadal nie centralizuje runtime. Kazdy mikro-bot uruchamia te guardy lokalnie we wlasnej instancji.

## Kolejnosc Migracji Z EURUSD

1. Najpierw helpery i struktury.
2. Potem status, storage, telemetry i incident journal.
3. Potem snapshot rynku i execution helpers.
4. Dopiero potem ostrozne mapowanie guardow i execution flow.
5. Na koncu ewentualne wspolne helpery learningu, ale bez przenoszenia lokalnej inteligencji symbolu.

## Anty-Wzor

Nie wolno zrobic tego bledu:

- przeniesc caly `GH_EURUSD_MQL5_Only.mq5` do `Core`,
- a potem zrobic z mikro-botow cienkie nakladki.

To byloby sprzeczne z celem projektu.

## Wniosek

`EURUSD` ma byc zrodlem wzorcow i dojrzalych idiomow, ale jego lokalna inteligencja ma pozostac lokalna.

Mapowanie ma byc:

- ostrozne,
- selektywne,
- autonomy-first.

## Pierwsza Potwierdzona Analogia

`GBPUSD` otrzymal juz pierwszy lokalny scoring oparty na analogii do `EURUSD`, ale bez kopiowania live execution i bez wynoszenia edge do `Core`.

Nowy stan:

- `GBPUSD` ma juz lokalnie takze sizing i `execution precheck`,
- ma juz tez kontrolowany live-send i lokalny trailing,
- co potwierdza, ze kolejne pary mozna rozwijac warstwowo: `signal -> size -> precheck -> send`.

## Pierwszy Potwierdzony Archetyp Azjatycki

`USDJPY` otrzymal juz:

- lokalny profil `FX_ASIA`,
- lokalny scoring dopasowany do okna azjatyckiego,
- lokalny sizing,
- lokalny `execution precheck`,
- kontrolowany live-send,
- lokalny trailing.

To potwierdza, ze architektura skaluje sie nie tylko na analogie instrumentu, ale tez na analogie sesji.

To potwierdza, ze dalsze pary mozna rozwijac:

- przez analogie wzorca,
- z zachowaniem lokalnych roznic,
- bez kolejnej przebudowy eksperta.

## Drugi Potwierdzony Archetyp Azjatycki

`NZDUSD` otrzymal juz:

- lokalny profil `FX_ASIA`,
- lokalny scoring dopasowany do okna azjatyckiego,
- lokalny sizing,
- lokalny `execution precheck`,
- kontrolowany live-send,
- lokalny trailing.

To potwierdza, ze wzorzec azjatycki daje sie powielac bez centralizacji runtime i bez przepisywania `Core`.

## Trzeci Potwierdzony Wzorzec Sesji Glownej

`USDCAD` otrzymal juz:

- lokalny profil `FX_MAIN`,
- lokalny scoring dopasowany do sesji glownej,
- lokalny sizing,
- lokalny `execution precheck`,
- kontrolowany live-send,
- lokalny trailing.

To potwierdza, ze dalsze pary glowne mozna podnosic ta sama warstwowa droga:

- `signal`
- `size`
- `precheck`
- `send`
- `manage position`

## Czwarty Potwierdzony Wzorzec Sesji Glownej

`USDCHF` otrzymal juz:

- lokalny profil `FX_MAIN`,
- lokalny scoring dopasowany do sesji glownej,
- lokalny sizing,
- lokalny `execution precheck`,
- kontrolowany live-send,
- lokalny trailing.

To wzmacnia wniosek, ze dalsze pary glowne mozna rozwijac przez analogie bez przenoszenia edge ani execution ownership do `Core`.

## Trzeci Potwierdzony Archetyp Azjatycko-Przejsciowy

`AUDUSD` otrzymal juz:

- lokalny profil `FX_ASIA`,
- lokalny scoring dopasowany do sesji azjatyckiej i przejsciowej,
- lokalny sizing,
- lokalny `execution precheck`,
- kontrolowany live-send,
- lokalny trailing.

To potwierdza, ze nawet para pomostowa miedzy profilami sesyjnymi nie wymaga nowego centralnego runtime ani dodatkowego makro-sterownika.

## Pierwszy Potwierdzony Wzorzec Crossowy

`EURJPY` otrzymal juz:

- lokalny profil `FX_CROSS`,
- lokalny scoring dopasowany do crossu europejsko-jenowego,
- lokalny sizing,
- lokalny `execution precheck`,
- kontrolowany live-send,
- lokalny trailing.

To potwierdza, ze architektura skaluje sie takze na crossy bez dorabiania centralnych wyjatkow w `Core`.

## Dalsze Potwierdzone Wzorce Crossowe

`GBPJPY`, `EURAUD` i `GBPAUD` otrzymaly juz:

- lokalne profile `FX_CROSS`,
- lokalne scoringi dopasowane do crossow,
- lokalny sizing,
- lokalny `execution precheck`,
- kontrolowany live-send,
- lokalny trailing.

To zamyka pierwszy pelny przebieg `11/11` i potwierdza, ze cala partia daje sie zbudowac bez pustych scaffoldow i bez centralizacji runtime.
