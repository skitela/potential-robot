# Ostry Prompt Dla Codex: Nowy Podzial Makro I Mikro

## Cel Promptu

Ten prompt ma sluzyc jako twarda instrukcja robocza dla dalszej pracy nad projektem `C:\MAKRO_I_MIKRO_BOT`.

Ma wymuszac:

- maksymalna autonomie mikro-botow,
- minimalizacje czesci wspolnej,
- architekture `100% MQL5`,
- zgodnosc z `MT5-only server`,
- gotowosc do wdrozenia wielu botow w `OANDA MT5`,
- brak centralnego przejecia runtime przez makro-bota.

## Prompt

```text
Pracujesz nad nowym projektem C:\MAKRO_I_MIKRO_BOT.

To ma byc system 100% MQL5, gotowy do dzialania na serwerach obslugujacych wylacznie MetaTrader 5.

Masz korzystac z wiedzy architektonicznej i wzorcow z:
- c:\OANDA_MT5_SYSTEM
- C:\GLOBALNY HANDEL VER1\EURUSD

ale nie wolno Ci bezmyslnie kopiowac starej architektury ani przenosic balastu historycznego.

Najwazniejsza zasada:
mikro-boty maja pozostac maksymalnie autonomiczne.

To oznacza, ze bez bardzo mocnego uzasadnienia nie wolno wyciagac z mikro-botow do czesci wspolnej:
- runtime,
- kill-switch,
- local market cache,
- black swan,
- self-heal,
- local risk manager,
- execution flow,
- local position management,
- local entry/exit guards,
- local counters i limity sesyjne,
- local learning light,
- local telemetry runtime.

Czesc wspolna nie jest centralnym makro-botem.

Nie buduj systemu, w ktorym jeden makro-bot steruje wszystkimi mikro-botami.
Nie buduj systemu, w ktorym mikro-boty sa cienkimi klientami centralnego runtime.
Nie buduj systemu, w ktorym awaria jednego wspolnego procesu przewraca wszystkie pary.

Masz budowac:
- cienki Core jako biblioteke wspolnego kodu,
- MicroBots jako autonomiczne EA per symbol,
- Profiles jako konfiguracje i profile symbolowe,
- Strategies jako warstwe specyficzna dla danego symbolu,
- Tools jako warstwe generatorow, pakowania, deploy i walidacji.

Model techniczny w MT5 ma byc:
- 1 mikro-bot = 1 wykres = 1 para,
- osobny EA per symbol,
- osobny preset per symbol,
- osobny lokalny stan per symbol,
- osobny lokalny heartbeat, journaling i telemetryka per symbol.

Do czesci wspolnej mozesz wydzielac tylko to, co jest kodem wielokrotnego uzytku, a nie wspolna wladza:
- wspolne typy i enumy,
- wspolne helpery storage,
- wspolne helpery journalingu,
- wspolne helpery telemetryki,
- wspolne klasyfikatory retcode,
- wspolne helpery execution precheck,
- wspolne helpery config envelope,
- wspolne helpery status payload,
- wspolne narzedzia generowania nowych mikro-botow,
- wspolne narzedzia deploy i backup.

Kazdy proponowany ruch architektoniczny oceniaj pytaniem:
"czy to zabiera autonomie mikro-botowi?"

Jesli odpowiedz brzmi tak, to domyslnie tego nie rob.

Domyslny priorytet:
1. autonomia mikro-bota,
2. bezpieczenstwo lokalne,
3. zgodnosc kontraktow,
4. redukcja duplikacji,
5. wygoda centralnego zarzadzania.

Masz traktowac EURUSD jako wzorzec referencyjny, ale nie jako sztywny szablon do bezmyslnego kopiowania.
Najpierw zrekonstruuj co w EURUSD jest przewaga symbolowa, a co jest tylko wspolnym mechanizmem.
Tylko wspolne mechanizmy nadaja sie do Core.

Wszelkie decyzje o przeniesieniu modułu z mikro-bota do Core musza miec konkretne uzasadnienie:
- dlaczego nie powinno to zostac lokalne,
- jakie ryzyko usuwamy,
- jaka zgodnosc zyskujemy,
- dlaczego nie oslabiamy autonomii bota.

Projekt ma byc przenoszalny jako jeden katalog.
Ma zawierac wszystko, co potrzebne do:
- budowy,
- deployu,
- backupu,
- spakowania zipem,
- odtworzenia na innym serwerze MT5.

Jesli uznasz, ze potrzebny jest generator kodu MQL5, to ma on byc w tym samym katalogu projektu i ma generowac szkielety zgodne z nowa architektura.

Masz aktywnie korzystac z internetu przy decyzjach technicznych, jesli moze to poprawic trafnosc lub uniknac falszywych zalozen.
Priorytet maja zrodla oficjalne i pierwotne:
- dokumentacja MQL5 / MetaTrader 5,
- oficjalne materialy OANDA dotyczace MT5,
- referencje MetaQuotes,
- oficjalne opisy eventow, plikow, VPS, chart attachment i MQL5 Wizard.

Nie wolno utrwalac zalozen o MT5 lub OANDA "z pamieci", jesli mozna je szybko sprawdzic na oficjalnym zrodle.

Kazdy etap pracy ma prowadzic do tego rezultatu:
- cienki Core,
- grube, autonomiczne MicroBots,
- gotowosc do wdrozenia aktualnej aktywnej floty MT5 zgodnie z biezacym registry i parity runtime,
- mozliwosc dalszego rozszerzania o kolejne pary przez analogie.
```

## Jak Tego Promptu Uzywac

Stosuj ten prompt:

- przy projektowaniu struktury katalogow,
- przy wydzielaniu `Core`,
- przy migracji `EURUSD`,
- przy projektowaniu generatora,
- przy tworzeniu kolejnych botow,
- przy kazdym sporze o granice miedzy wspolnym a lokalnym.

## Kryterium PASS

Praca jest zgodna z celem tylko wtedy, gdy:

- mikro-bot nadal pozostaje pelna autonomiczna jednostka,
- `Core` jest biblioteka, a nie centralnym nadzorca handlu,
- wdrozenie `11` botow w `MT5` jest naturalne,
- projekt nie zalezy runtime od Pythona,
- projekt jest gotowy na serwer `MT5-only`.
