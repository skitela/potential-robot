# Model Wdrozenia Aktywnej Floty MT5

> Status 2026-04-01: nazwa pliku zostaje zachowana dla zgodnosci z eksportem `HANDOFF`, ale ten dokument opisuje juz aktywna flote `13` symboli. Wycofane symbole z historycznego modelu FX-only nie naleza do biezacego modelu wdrozenia.

## Cel

Ten dokument opisuje aktywny model wdrozenia mikro-botow w terminalu `MetaTrader 5` brokera `OANDA` dla projektu `MAKRO_I_MIKRO_BOT`.

Model zaklada:

- `1 mikro-bot = 1 wykres = 1 symbol`,
- brak centralnego `EA`, ktory steruje wszystkimi symbolami,
- wspolny kod jako biblioteka `Core`,
- kazdy bot jako oddzielna instancja na oddzielnym wykresie,
- wspolny `FILE_COMMON` z separacja stanu per symbol,
- bezpieczne presety domyslne i jawne generowanie presetow aktywnych.

## Aktywna Flota

### Pierwsza fala

1. `MicroBot_US500`
2. `MicroBot_EURJPY`
3. `MicroBot_AUDUSD`
4. `MicroBot_USDCAD`

### Kohorta globalnego nauczyciela

5. `MicroBot_DE30`
6. `MicroBot_GOLD`
7. `MicroBot_SILVER`
8. `MicroBot_USDJPY`
9. `MicroBot_USDCHF`
10. `MicroBot_COPPERUS`
11. `MicroBot_EURAUD`
12. `MicroBot_EURUSD`
13. `MicroBot_GBPUSD`

Kazdy bot jest osobnym `EA` i osobnym plikiem `.ex5`.

## Kanoniczna Macierz Nazw

| symbol_alias | broker_symbol | code_symbol | expert | preset | state_alias |
| --- | --- | --- | --- | --- | --- |
| EURUSD | EURUSD.pro | EURUSD | MicroBot_EURUSD | MicroBot_EURUSD_Live.set | EURUSD |
| AUDUSD | AUDUSD.pro | AUDUSD | MicroBot_AUDUSD | MicroBot_AUDUSD_Live.set | AUDUSD |
| GBPUSD | GBPUSD.pro | GBPUSD | MicroBot_GBPUSD | MicroBot_GBPUSD_Live.set | GBPUSD |
| USDJPY | USDJPY.pro | USDJPY | MicroBot_USDJPY | MicroBot_USDJPY_Live.set | USDJPY |
| USDCAD | USDCAD.pro | USDCAD | MicroBot_USDCAD | MicroBot_USDCAD_Live.set | USDCAD |
| USDCHF | USDCHF.pro | USDCHF | MicroBot_USDCHF | MicroBot_USDCHF_Live.set | USDCHF |
| EURJPY | EURJPY.pro | EURJPY | MicroBot_EURJPY | MicroBot_EURJPY_Live.set | EURJPY |
| EURAUD | EURAUD.pro | EURAUD | MicroBot_EURAUD | MicroBot_EURAUD_Live.set | EURAUD |
| GOLD | GOLD.pro | GOLD | MicroBot_GOLD | MicroBot_GOLD_Live.set | GOLD |
| SILVER | SILVER.pro | SILVER | MicroBot_SILVER | MicroBot_SILVER_Live.set | SILVER |
| COPPER-US | COPPER-US.pro | COPPERUS | MicroBot_COPPERUS | MicroBot_COPPERUS_Live.set | COPPER-US |
| DE30 | DE30.pro | DE30 | MicroBot_DE30 | MicroBot_DE30_Live.set | DE30 |
| US500 | US500.pro | US500 | MicroBot_US500 | MicroBot_US500_Live.set | US500 |

Reguly sa stale i nie powinny byc mieszane:

- `symbol_alias` jest kanoniczny dla repo, research, readiness i auditow
- `broker_symbol` jest dokladna nazwa wykresu oraz `Market Watch` u brokera
- `code_symbol` sluzy do nazw plikow `Profile_*`, `Strategy_*` i do rdzenia nazwy `MicroBot_*`
- `state_alias` powinien pozostawac rowny aliasowi kanonicznemu; helper runtime dopuszcza warianty broker/code tylko jako fallback
- `COPPER-US` jest aktywnym wyjatkiem, gdzie alias, broker symbol i code symbol roznia sie forma

## Podstawowa Zasada Techniczna

W `MT5` na jednym wykresie dziala jeden `EA`.

Dlatego:

- otwieramy jeden wykres per aktywny symbol,
- do kazdego wykresu przypinamy odpowiedni mikro-bot,
- kazdy mikro-bot handluje tylko symbolem swojego wykresu,
- `Core` pozostaje wspolnym kodem wkompilowanym w boty.

To jest model najbezpieczniejszy, najbardziej czytelny i najlatwiejszy do utrzymania.

## Przypisanie Do Wykresow

### Zasada

Bot nie wybiera sobie dowolnego symbolu i nie jest sterowany przez centralny nadrzedny bot.

Zamiast tego:

- `MicroBot_US500` przypinamy do `US500`,
- `MicroBot_EURJPY` przypinamy do `EURJPY`,
- `MicroBot_GOLD` przypinamy do `GOLD`,
- `MicroBot_EURUSD` przypinamy do `EURUSD`,
- itd.

Kazdy bot przy starcie powinien sprawdzic:

- czy `Symbol()` zgadza sie z jego profilem,
- czy wlaczono `Algo Trading`,
- czy dostepne sa wymagane pliki lokalne,
- czy `kill-switch` jest wazny,
- czy symbol ma poprawny tryb handlu.

Jesli nie:

- `INIT_FAILED`,
- brak polowicznego uruchomienia,
- brak handlu na zlym symbolu.

## Interwal Wykresu

Minimalna rekomendacja operacyjna:

- wszystkie aktywne mikro-boty uruchamiane na wykresach `M5`,
- dodatkowe interwaly pobierane wewnatrz kodu przez `CopyBuffer` / `CopyTime`.

To upraszcza operacje terminalowe i utrzymuje spojnosc planu chartow.

## Jak Wyglada Terminal

Na terminalu `MT5`:

- otwierasz `13` wykresow zgodnych z aktywna flota,
- kazdy wykres ma nazwe odpowiadajaca symbolowi,
- do kazdego przeciagasz odpowiedni `EA`,
- wczytujesz odpowiedni preset,
- sprawdzasz status `Algo Trading`,
- sprawdzasz, czy bot wszedl w `READY`, `OBSERVING` albo inny poprawny stan runtime.

## Organizacja Plikow Runtime

Kazdy mikro-bot ma w `FILE_COMMON` wlasny katalog, np.:

```text
MAKRO_I_MIKRO_BOT\state\EURUSD\
MAKRO_I_MIKRO_BOT\logs\EURUSD\
MAKRO_I_MIKRO_BOT\run\EURUSD\
```

Analogicznie dla kazdego aktywnego symbolu.

To daje:

- brak nadpisywania stanu miedzy symbolami,
- rozdzielone logi,
- prosty backup,
- prostsza diagnostyke,
- prostsza integracje z `SERVER_PROFILE`.

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
- lokalne snapshoty supervision i learning.

To nie moze byc wspolna instancja.

## Presety

Kazdy bot powinien miec osobny `.set`.

Domyslne `*_Live.set` pozostaja bezpieczne:

- `InpEnableLiveEntries=false`

To pozwala najpierw przypiac cala partie do wykresow bez natychmiastowego wejscia w live-send.

Jesli operator chce swiadomie wygenerowac presety aktywne, uzywa:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\GENERATE_ACTIVE_LIVE_PRESETS.ps1
```

Wynik trafia do:

- `MQL5\Presets\ActiveLive`
- oraz do pakietu `SERVER_PROFILE\PACKAGE\MQL5\Presets\ActiveLive`

## Wspolna Warstwa W MT5

`Core` nie jest osobnym `EA`.

W `MT5` operator widzi tylko mikro-boty.

Pod spodem korzystaja one z:

- `MQL5/Include/Core/...`
- `MQL5/Include/Profiles/...`
- `MQL5/Include/Strategies/...`

Czyli:

- w `Navigator` widzisz boty,
- `Core` jest wkompilowany w nie jako wspolny kod.

## Server Profile

Projekt ma jeden `SERVER_PROFILE`, ktory zawiera:

- `MQL5/Experts/MicroBots/*.mq5`,
- `MQL5/Include/Core/*.mqh`,
- `MQL5/Include/Profiles/*.mqh`,
- `MQL5/Include/Strategies/*.mqh`,
- `MQL5/Presets/*.set`,
- `COMMON/Files/MAKRO_I_MIKRO_BOT/...`

Nie powinno byc zaleznosci runtime od:

- starego repo `OANDA_MT5_SYSTEM`,
- wycofanych symboli,
- historycznych presetow pochodzacych z wycofanego modelu FX-only,
- zewnetrznego bridge poza kontraktami systemu.

## Operacyjna Procedura Wdrozenia

### Krok 1

Uruchomic wrapper preflight:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\PREPARE_MT5_ROLLOUT.ps1
```

Ten krok obejmuje:

- sync tokenow `kill-switch`,
- kompilacje aktywnej floty,
- walidacje ukladu projektu,
- walidacje gotowosci wdrozenia,
- regeneracje planu chartow,
- eksport paczki serwerowej,
- zapis backupu ZIP.

### Krok 2

Sprawdzic raporty:

- `EVIDENCE\prepare_mt5_rollout_report.json`
- `EVIDENCE\deployment_readiness_report.json`
- `EVIDENCE\mt5_microbots_profile_setup_report.json`

### Krok 3

Skopiowac paczke do katalogu `MT5`.

### Krok 4

Utworzyc lub odtworzyc `13` wykresow zgodnych z aktywna flota.

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
- poprawny tryb `READY` / `OBSERVING` / `LEARNING`,
- poprawnosc katalogow `FILE_COMMON`.

### Krok 9

Zapisac profil terminala z aktywna flota.

### Krok 10

Przy kolejnym starcie ladowac gotowy profil.

## Jak Ograniczyc Ryzyko Operacyjne

### Zasada 1

Kazdy bot ma unikalny `magic`.

Rekomendowany przydzial bierze sie z `CONFIG/microbots_registry.json` i to ten plik jest zrodlem prawdy.

### Zasada 2

Kazdy bot handluje tylko `Symbol()`.

### Zasada 3

Kazdy bot ma wlasne katalogi stanu.

### Zasada 4

Kazdy bot ma lokalny `kill-switch`.

### Zasada 5

Kazdy bot ma fail-fast przy zlej konfiguracji.

### Zasada 6

Kazdy bot ma lokalny `heartbeat` oraz snapshoty supervision.

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
- backup i restore.

## Rozszerzenie Makro / Mikro

Warstwa makro pozostaje cienka:

- obserwator,
- agregator raportow,
- generator rekomendacji offline,
- control-plane i supervision.

Nie jest to centralny bot wejsc.

## Konkluzja

Technicznie model wdrozenia aktywnej floty powinien byc:

- prosty,
- czytelny,
- zgodny z `MT5`,
- oparty o `1 bot = 1 chart = 1 symbol`,
- z mocna autonomia lokalna,
- z cienka warstwa wspolnego kodu,
- bez powrotu do wycofanych symboli i starego 11-botowego modelu FX-only.
