# Architektura Makro I Mikro MQL5

## Cel

Ten dokument definiuje nowy projekt `C:\MAKRO_I_MIKRO_BOT` jako samowystarczalny system `100% MQL5`, rozwijany rownolegle do:

- `c:\OANDA_MT5_SYSTEM`
- `C:\GLOBALNY HANDEL VER1\EURUSD`

Nowy projekt ma:

- nie niszczyc istniejacych repozytoriow,
- nie dziedziczyc ich balastu,
- nie mieszac starej i nowej architektury,
- zachowac maksymalna autonomie mikro-botow,
- umozliwic przyszle wdrozenie wielu botow na serwerach `MT5-only`,
- pozostac przenoszalny jako jeden katalog.

## Zasada Nadrzedna

Nie budujemy centralnego makro-bota, ktory odbiera mikro-botom runtime i decyzje wejscia.

Budujemy:

- cienki wspolny `Core`,
- wiele autonomicznych `MicroBots`,
- zestaw profili symboli,
- narzedzia operacyjne i generator nowych botow.

`Core` jest wspolnym kodem.
`MicroBot` jest autonomiczna instancja handlujaca.

## Definicje

### Core

Wspolna biblioteka `MQL5`, bez prawa do centralnego sterowania transakcjami wielu par.

Rola:

- dostarczac wspolne typy,
- dostarczac wspolne helpery,
- dostarczac wspolne standardy runtime,
- upraszczac tworzenie nowych mikro-botow,
- zapewniac spojne kontrakty danych.

### MicroBot

Autonomiczny `EA` przypiety do jednego wykresu i jednej pary walutowej.

Rola:

- posiadac wlasny runtime,
- handlowac jedna para,
- prowadzic lokalna ochrone ryzyka,
- wykonywac lokalny learning,
- miec wlasny kill-switch,
- samodzielnie decydowac o wejsciu i wyjsciu.

### Profile

Opis wlasciwosci symbolu lub grupy symboli.

Rola:

- okna handlu,
- limity sesyjne,
- profile spreadu,
- progi caution,
- parametry `black swan`,
- podstawowe charakterystyki execution.

### Tools

Warstwa operacyjna projektu.

Rola:

- generator nowych mikro-botow,
- pakowanie,
- backup,
- deploy,
- synchronizacja tokenow `kill-switch`,
- walidacja gotowosci rolloutowej,
- jeden skrypt preflight przed attach do `MT5`,
- eksport server profile,
- walidacja struktury.

## Docelowa Struktura Katalogow

```text
C:\MAKRO_I_MIKRO_BOT
├── CONFIG
├── DOCS
├── MQL5
│   ├── Experts
│   │   └── MicroBots
│   ├── Include
│   │   ├── Core
│   │   ├── Profiles
│   │   └── Strategies
│   └── Presets
├── RUN
├── TOOLS
├── SERVER_PROFILE
├── STATE
├── LOGS
├── EVIDENCE
└── BACKUP
```

## Szczegolowy Podzial Odpowiedzialnosci

### To Zostaje W MicroBotach

Kazdy mikro-bot ma zachowac:

- wlasny `OnInit`,
- wlasny `OnTimer`,
- wlasny `OnTick`,
- wlasny `runtime state`,
- wlasny `market state cache`,
- wlasny `kill-switch`,
- wlasny `black swan`,
- wlasny `self-heal`,
- wlasne limity godzinowe, dobowe i sesyjne,
- wlasny `risk sizing`,
- wlasny `execution flow`,
- wlasny `position management`,
- wlasny trailing,
- wlasny `learning light`,
- wlasna retencje stanu,
- wlasny journaling lokalny,
- lokalna telemetrie,
- lokalny profil symbolu,
- lokalny scoring setupow,
- lokalne decyzje handlowe.

Powod:

- to sa elementy najblizej rynku,
- musza dzialac lokalnie,
- nie moga zalezec od zewnetrznej instancji,
- tworza przewage symbolowa,
- sa krytyczne dla autonomii.

### To Trafia Do Core

Do `Core` trafia tylko to, co jest wspolnym kodem i nie stanowi centralnej wladzy:

- wspolne enumy i struktury danych,
- wspolne helpery JSON i CSV,
- wspolne helpery `FILE_COMMON`,
- wspolne helpery journalingu,
- wspolne helpery telemetryki,
- wspolne klasyfikatory retcode,
- wspolne helpery execution precheck,
- wspolne helpery `OrderCheck` i `OrderCalcMargin`,
- wspolne helpery status payload,
- wspolne helpery `config envelope`,
- wspolne helpery `runtime control` odczytywanego lokalnie,
- wspolne helpery `heartbeat`,
- wspolne helpery eksportu `server profile`,
- wspolne helpery generatora nowych botow.

Powod:

- unikamy duplikacji kodu,
- zachowujemy spojnosc kontraktow,
- przyspieszamy tworzenie kolejnych botow,
- nie odbieramy mikro-botom decyzyjnosci.

### Co Jest Zabronione W Core

`Core` nie moze:

- podejmowac centralnych decyzji za wiele par naraz,
- zarzadzac wszystkimi wejściami z jednego miejsca,
- byc jednym globalnym runtime dla wszystkich mikro-botow,
- przejmowac symbolowej logiki sygnalu,
- przejmowac symbolowego `black swan`,
- przejmowac lokalnego `kill-switcha`,
- przejmowac lokalnego zarzadzania pozycja.

## Dlaczego Runtime Zostaje W MicroBotach

Kazdy mikro-bot ma swoj:

- rytm tickow,
- wlasny cache rynku,
- wlasne limity,
- wlasna sesje,
- wlasna reakcje na degradacje wykonania,
- wlasne stany przejsciowe.

Dlatego `runtime` nie powinien byc centralizowany.

Do `Core` moze trafic tylko:

- definicja struktury runtime,
- helpery do serializacji i raportowania,
- wspolne funkcje obliczeniowe.

Ale sama instancja runtime musi zostac lokalna w kazdym mikro-bocie.

## Dlaczego Kill-Switch Zostaje W MicroBotach

`Kill-switch` jest ostatnim bezpiecznikiem lokalnym.

Jesli bylby centralny:

- awaria centralnego procesu zabralaby bezposredni lokalny bezpiecznik,
- bot nie moglby natychmiast zareagowac sam,
- zwiekszylaby sie zaleznosc od zewnetrznej warstwy.

Do `Core` moze trafic tylko:

- wspolna implementacja biblioteczna `kill-switch guard`,
- standard pliku tokenu,
- standard walidacji i TTL.

Natomiast sam `kill-switch` ma byc wykonywany lokalnie przez kazdego mikro-bota.

## Dlaczego Black Swan Zostaje W MicroBotach

Kazda para:

- reaguje inaczej na wydarzenia,
- ma inna wrazliwosc spreadowa,
- ma inne sesje,
- ma inna mikrostrukture i inne zachowanie po publikacjach danych.

Dlatego `black swan` powinien byc lokalny.

Do `Core` moze wejsc tylko:

- wspolny interfejs,
- wspolne helpery kalendarza,
- wspolne helpery statusow.

Ale polityka i decyzja `black swan` powinny pozostac symbolowe.

## Poziomy Autonomii

### Poziom 1: Autonomia Runtime

Kazdy bot sam:

- startuje,
- zapisuje stan,
- flushuje telemetryke,
- pilnuje heartbeat,
- pracuje na swoim timerze.

### Poziom 2: Autonomia Ryzyka

Kazdy bot sam:

- pilnuje wlasnych caps,
- pilnuje cooldownu,
- pilnuje execution pressure,
- moze wejsc w `caution`, `close-only`, `blocked`.

### Poziom 3: Autonomia Strategii

Kazdy bot sam:

- liczy scoring,
- wybiera setup,
- decyduje o wejściu,
- zarzadza otwarta pozycja.

### Poziom 4: Autonomia Operacyjna

Kazdy bot ma:

- wlasne logi,
- wlasny state,
- wlasne pliki diagnostyczne,
- wlasny profil wdrozenia.

## Model Generowania Kolejnych Botow

Nowy projekt ma miec generator szkieletu mikro-bota.

Generator tworzy:

- nowy `EA` per symbol,
- profil symbolu,
- strategia symbolowa jako szablon,
- preset,
- katalogi `state`, `logs`, `run`,
- wpis do `server profile`,
- wpis do dokumentacji wdrozeniowej.

Generator nie ma tworzyc gotowej strategii.
Ma tworzyc bezpieczny szkielet zgodny z `Core`.

## Warstwa Operacyjna Rolloutu

Nowy projekt ma miec jawny workflow przed wdrozeniem na terminal `MT5`.

Minimalny ciag operacyjny:

- odswiezenie tokenow `kill-switch`,
- kompilacja calej partii,
- walidacja struktury projektu,
- walidacja gotowosci wdrozeniowej,
- regeneracja planu przypiecia do wykresow,
- eksport paczki serwerowej,
- zapis backupu ZIP.

Ten workflow jest realizowany przez:

- `TOOLS\SYNC_ALL_OANDAKEY_TOKENS.ps1`
- `TOOLS\VALIDATE_DEPLOYMENT_READINESS.ps1`
- `TOOLS\PREPARE_MT5_ROLLOUT.ps1`

Rollem tych skryptow nie jest sterowanie handlem.
Ich rola to tylko przygotowanie i sprawdzenie stanu przed wdrozeniem.

## Kill-Switch W Nowym Projekcie

Model `kill-switch` ma byc zgodny z dojrzalym wzorcem `EURUSD`:

- sekret lub klucz pozostaje poza runtime mikro-bota,
- runtime nie mieli stale sekretow i pendrive,
- lokalnie sprawdzany jest tylko swiezy token plikowy,
- kazdy mikro-bot wykonuje ten guard lokalnie,
- wspolny `Core` dostarcza tylko biblioteczna implementacje i standard TTL.

Szczegoly operacyjne i kontrakt tokenu opisuje:

- `DOCS\09_KILL_SWITCH_MODEL.md`

## Jak Korzystac Z EURUSD

`EURUSD` pozostaje wzorcem referencyjnym.

Nie kopiujemy go bezmyslnie.
Robimy z niego:

- zrodlo dobrych praktyk,
- zrodlo kontraktow,
- zrodlo idiomow runtime,
- zrodlo struktury mikro-bota.

Najpierw rozwija sie do konca jako wzorcowy mikro-bot.
Dopiero potem sluzy do analogii dla innych par.

## Etapy Pracy

### Etap 1

Utworzenie nowego projektu `C:\MAKRO_I_MIKRO_BOT`.

### Etap 2

Zbudowanie cienkiego `Core`.

### Etap 3

Dalszy rozwoj `EURUSD` jako wzorca mikro-bota.

### Etap 4

Integracja `EURUSD` z nowym `Core`.

### Etap 5

Budowa kolejnych mikro-botow przez analogie.

### Etap 6

Wdrozenie wielu botow na terminalu `OANDA MT5`.

## Konkluzja

Nowy system ma byc:

- `100% MQL5`,
- przenoszalny jako jeden katalog,
- oparty o wiele autonomicznych mikro-botow,
- z bardzo cienka warstwa wspolna,
- bez centralnego przejmowania runtime,
- zgodny z naturalnym modelem pracy `MetaTrader 5`.

To jest architektura, w ktorej:

- wilk jest syty, bo zachowujemy autonomie mikro-botow,
- owca cala, bo zachowujemy porzadek, wspolne standardy i brak redundancji kodowej.
