# Model Wdrozenia 11 Botow W OANDA MT5

## Cel

Ten dokument opisuje bardzo szczegolowy model wdrozenia `11` autonomicznych mikro-botow w terminalu `MetaTrader 5` brokera `OANDA`.

Model zaklada:

- `1 mikro-bot = 1 wykres = 1 para`,
- brak centralnego `EA`, ktory steruje wszystkimi parami,
- wspolny kod jako biblioteka `Core`,
- kazdy bot jako oddzielna instancja na oddzielnym wykresie,
- serwer `MT5-only`,
- pelna zgodnosc z naturalnym modelem pracy `MT5`.

## Podstawowa Zasada Techniczna

W `MT5` na jednym wykresie dziala jeden `EA`.

Dlatego:

- otwieramy `11` wykresow,
- do kazdego wykresu przypinamy odpowiedni mikro-bot,
- kazdy mikro-bot handluje tylko symbolem swojego wykresu.

To jest model najbezpieczniejszy, najbardziej czytelny i najlatwiejszy do utrzymania.

## Lista Instancji

Ponizej model przykładowy dla `11` par FX. Ostateczna lista moze zostac dostosowana do Twojej polityki symboli.

1. `MicroBot_EURUSD`
2. `MicroBot_GBPUSD`
3. `MicroBot_USDJPY`
4. `MicroBot_AUDUSD`
5. `MicroBot_USDCAD`
6. `MicroBot_USDCHF`
7. `MicroBot_NZDUSD`
8. `MicroBot_EURJPY`
9. `MicroBot_GBPJPY`
10. `MicroBot_EURAUD`
11. `MicroBot_GBPAUD`

Kazdy bot jest osobnym `EA` i osobnym plikiem `.ex5`.

## Przypisanie Do Wykresow

### Zasada

Bot nie wybiera sobie dowolnej pary.
Para nie jest tez obslugiwana przez centralny nadrzedny bot.

Zamiast tego:

- `MicroBot_EURUSD` przypinamy do wykresu `EURUSD`,
- `MicroBot_GBPUSD` przypinamy do wykresu `GBPUSD`,
- itd.

Kazdy bot powinien przy starcie sprawdzic:

- czy `Symbol()` zgadza sie z jego profilem,
- czy wlaczono `Algo Trading`,
- czy dostepne sa wymagane pliki lokalne,
- czy `kill-switch` jest wazny,
- czy symbol ma odpowiedni tryb handlu.

Jesli nie:

- `INIT_FAILED`,
- brak polowicznego uruchomienia,
- brak handlu na zlym symbolu.

## Interwal Wykresu

Kazdy bot powinien byc przypiety do takiego wykresu, jaki jest przewidziany przez jego profil referencyjny.

Przykladowo:

- wykres `M5` dla botow scalpingowych,
- dodatkowe wskazniki `M1` lub `M15` czytane wewnetrznie przez kod,
- ale glowny wykres powinien byc zgodny z zalozonym profilem glownym.

Minimalna rekomendacja operacyjna:

- wszystkie `11` botow uruchamiane na wykresach `M5`,
- a inne interwaly pobierane przez `CopyBuffer` / `CopyTime` wewnatrz kodu.

To upraszcza operacje terminalowe.

## Jak Bedzie Wygladal Terminal

Na terminalu `MT5`:

- otwierasz `11` wykresow,
- kazdy wykres ma nazwe odpowiadajaca parze,
- do kazdego przeciagasz odpowiedni `EA`,
- wczytujesz odpowiedni preset,
- sprawdzasz status `Algo Trading`,
- sprawdzasz, czy bot wszedl w `READY` albo `CAUTION`.

Przyklad:

- Chart 1: `EURUSD` -> `MicroBot_EURUSD`
- Chart 2: `GBPUSD` -> `MicroBot_GBPUSD`
- Chart 3: `USDJPY` -> `MicroBot_USDJPY`
- Chart 4: `AUDUSD` -> `MicroBot_AUDUSD`
- Chart 5: `USDCAD` -> `MicroBot_USDCAD`
- Chart 6: `USDCHF` -> `MicroBot_USDCHF`
- Chart 7: `NZDUSD` -> `MicroBot_NZDUSD`
- Chart 8: `EURJPY` -> `MicroBot_EURJPY`
- Chart 9: `GBPJPY` -> `MicroBot_GBPJPY`
- Chart 10: `EURAUD` -> `MicroBot_EURAUD`
- Chart 11: `GBPAUD` -> `MicroBot_GBPAUD`

## Organizacja Plikow Runtime

Kazdy mikro-bot powinien miec w `FILE_COMMON` wlasny katalog, np.:

```text
MAKRO_I_MIKRO_BOT\state\EURUSD\
MAKRO_I_MIKRO_BOT\logs\EURUSD\
MAKRO_I_MIKRO_BOT\run\EURUSD\
```

Analogicznie dla kazdej pary.

Dzieki temu:

- boty nie nadpisuja sobie stanu,
- logi sa rozdzielone,
- backup jest prosty,
- diagnostyka jest prosta,
- integracja z serwer profile jest prosta.

## Co Kazdy Bot Musi Miec Lokalnie

Kazdy bot musi miec lokalnie:

- `runtime_state`,
- `runtime_status`,
- `heartbeat`,
- `decision_journal`,
- `incident_journal`,
- `execution_telemetry`,
- `informational_policy`,
- `kill-switch token validation`,
- lokalne limity doby, godziny i sesji,
- lokalne liczniki requestow i order send,
- lokalny cache rynku,
- lokalny `black swan`.

To nie moze byc wspolna instancja.

## Presety

Kazdy bot powinien miec osobny `.set`.

Przyklad:

- `MicroBot_EURUSD_Live.set`
- `MicroBot_GBPUSD_Live.set`
- `MicroBot_USDJPY_Live.set`

Preset zawiera tylko:

- parametry symbolu,
- parametry okien handlu,
- progi spreadowe,
- parametry risk,
- progi uczenia,
- progi `black swan`.

Kod wspolny nie siedzi w presetach.
Kod wspolny siedzi w `Core`.

W aktualnym projekcie domyslne `*_Live.set` pozostaja bezpieczne:

- `InpEnableLiveEntries=false`

To pozwala najpierw przypiac cala partie do wykresow bez natychmiastowego wejscia w live-send.

Jesli operator chce swiadomie wygenerowac presety aktywne, uzywa:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\GENERATE_ACTIVE_LIVE_PRESETS.ps1
```

Wynik trafia do:

- `SERVER_PROFILE\PACKAGE\MQL5\Presets\ActiveLive`

## Sesje Dzienne I Azjatyckie

Nie dzielimy botow wedlug centralnego planera.

Kazdy bot sam ma wiedziec:

- czy jest botem dziennym,
- czy azjatyckim,
- czy hybrydowym,
- kiedy wolno mu otwierac pozycje,
- kiedy przechodzi w `close-only`,
- kiedy ma tylko pilnowac pozycji.

To powinno byc zapisane w jego profilu i presiecie.

## Limity Godzinowe, Dobowe, Seryjne

Kazdy bot sam trzyma swoje:

- `max_entries_per_hour`,
- `max_entries_per_day`,
- `max_entries_per_session`,
- `max_order_attempts_per_min`,
- `max_price_requests_per_min`,
- `cooldown_after_loss_streak`,
- `cooldown_after_execution_errors`.

Powod:

- mikro-bot ma byc autonomiczny,
- ma sam pilnowac swojej higieny,
- nie moze czekac na zewnetrzna decyzje.

## Wspolna Warstwa W MT5

`Core` nie bedzie przypinany jako osobny `EA`.

To jest kluczowe.

W `MT5` operator widzi tylko mikro-boty.

Pod spodem korzystaja one z:

- `MQL5/Include/Core/...`
- `MQL5/Include/Profiles/...`
- `MQL5/Include/Strategies/...`

Czyli:

- w `Navigator` widzisz boty,
- `Core` jest wkompilowany w nie jako wspolny kod.

## Server Profile

Projekt powinien miec jeden `SERVER_PROFILE`, ktory zawiera:

- `MQL5/Experts/MicroBots/*.mq5`,
- `MQL5/Include/Core/*.mqh`,
- `MQL5/Include/Profiles/*.mqh`,
- `MQL5/Include/Strategies/*.mqh`,
- `MQL5/Presets/*.set`,
- `COMMON/Files/MAKRO_I_MIKRO_BOT/...`

Nie powinno byc zaleznosci runtime od:

- starego repo OANDA,
- starego repo EURUSD,
- zewnetrznego Pythona,
- zewnetrznego bridge.

## Operacyjna Procedura Wdrozenia

### Krok 1

Uruchomic jeden wrapper preflight:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\PREPARE_MT5_ROLLOUT.ps1
```

Ten krok obejmuje:

- sync tokenow `kill-switch`,
- kompilacje calej partii,
- walidacje ukladu projektu,
- walidacje gotowosci wdrozenia,
- regeneracje planu przypiecia,
- eksport paczki serwerowej,
- zapis backupu ZIP.

### Krok 2

Sprawdzic raporty:

- `EVIDENCE\prepare_mt5_rollout_report.json`
- `EVIDENCE\deployment_readiness_report.json`

Oba raporty musza dawac `ok=true`.

### Krok 3

Skopiowac paczke do katalogu `MT5`.

### Krok 4

Utworzyc lub odtworzyc `11` wykresow.

### Krok 5

Przypiac wlasciwy `EA` do wlasciwego wykresu.

### Krok 6

Wczytac wlasciwy bezpieczny preset per symbol.

### Krok 7

Jesli wymagane, swiadomie uzyc presetow z:

- `SERVER_PROFILE\PACKAGE\MQL5\Presets\ActiveLive`

### Krok 8

Zweryfikowac:

- `Algo Trading = ON`,
- status `kill-switch`,
- status symbolu,
- poprawny tryb `READY` / `CAUTION`,
- poprawnosc katalogow `FILE_COMMON`.

### Krok 9

Zapisac profil terminala z `11` wykresami.

### Krok 10

Przy kolejnym starcie ladowac gotowy profil.

## Jak Ograniczyc Ryzyko Operacyjne

### Zasada 1

Kazdy bot ma unikalny `magic`.

Rekomendowany aktualny przydzial:

- `EURUSD` -> `910101`
- `GBPUSD` -> `910102`
- `USDJPY` -> `910103`
- `AUDUSD` -> `910104`
- `USDCAD` -> `910105`
- `USDCHF` -> `910106`
- `NZDUSD` -> `910107`
- `EURJPY` -> `910108`
- `GBPJPY` -> `910109`
- `EURAUD` -> `910110`
- `GBPAUD` -> `910111`

### Zasada 2

Kazdy bot handluje tylko `Symbol()`.

### Zasada 3

Kazdy bot ma wlasne katalogi stanu.

### Zasada 4

Kazdy bot ma lokalny `kill-switch`.

### Zasada 5

Kazdy bot ma fail-fast przy zlej konfiguracji.

### Zasada 6

Kazdy bot ma lokalny `heartbeat`.

### Zasada 7

Brak jednego centralnego punktu, ktory blokuje wszystkie boty.

## Minimalny Zestaw Narzedzi Projektu

Projekt `C:\MAKRO_I_MIKRO_BOT` powinien miec:

- generator nowego mikro-bota,
- generator presetow,
- generator presetow aktywnych `live=true`,
- eksport `server profile`,
- walidator kontraktow katalogu,
- walidator gotowosci rolloutowej,
- wrapper jednego preflightu rolloutowego,
- pakowanie `zip`,
- delta deploy,
- backup i restore.

## Potencjalne Rozszerzenie

Jesli kiedys powstanie warstwa makro, to tylko jako:

- obserwator,
- agregator raportow,
- generator rekomendacji offline,
- read-only supervisor.

Nie jako centralny bot decydujacy o wejsciu wszystkich par.

## Konkluzja

Technicznie model wdrozenia `11` botow w `OANDA MT5` powinien byc:

- prosty,
- czytelny,
- zgodny z `MT5`,
- oparty o `1 bot = 1 chart = 1 symbol`,
- z bardzo mocna autonomia lokalna,
- z cienka warstwa wspolnego kodu,
- bez centralnego przejmowania decyzji przez makro-bota.
