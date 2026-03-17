# 65. Metals Session And Time Architecture V1

## Cel

Zamknac w jednym miejscu trzy rzeczy:
- co juz bylo dobrze przemyslane w `OANDA_MT5_SYSTEM`,
- co potwierdza dzisiejsza oficjalna specyfikacja OANDA/TMS,
- jak to sensownie przeniesc do nowej architektury `MAKRO_I_MIKRO_BOT` bez mieszania rodzin i bez chaosu czasowego.

## Twardy wybor instrumentow

Do pierwszego rollout-u rodziny metali zostaja tylko cztery instrumenty:
- `GOLD.pro`
- `SILVER.pro`
- `PLATIN.pro`
- `COPPER-US.pro`

`PALLAD.pro` zostaje odrzucony na ten etap.

## Nazwa miedzi

Kanoniczna nazwa, ktora nalezy traktowac jako glowna pod OANDA/TMS MT5, to:
- `COPPER-US.pro`

To zgadza sie z:
- lokalnym mapowaniem starego systemu,
- lokalnymi spread capami starego systemu,
- aktualna specyfikacja OANDA/TMS.

W starszych materialach i pobocznych stronach mozna trafic warianty aliasowe, ale do nowej rodziny `METALS` jako glowna nazwe przyjmujemy `COPPER-US.pro`.

## Co oficjalnie potwierdza OANDA/TMS

Z punktu widzenia godzin handlu:

- `GOLD.pro`
  - pon-czw `00:05-22:59`
  - pt `00:05-21:59`
- `SILVER.pro`
  - pon-czw `00:05-22:59`
  - pt `00:05-21:59`
- `PLATIN.pro`
  - pon-czw `00:01-22:59`
  - pt `00:01-21:59`
- `COPPER-US.pro`
  - pon-czw `00:01-22:59`
  - pt `00:01-21:59`

To oznacza, ze brokerowo nie musimy zamykac sie tylko do `14:00-17:00` PL. Mozemy budowac madrzejsze okna lokalne, ale nie powinnismy rozlewac handlu po calym dniu bez wyraznej przewagi.

## Co juz bylo dobrze zrobione w OANDA_MT5_SYSTEM

Stary system nie byl przypadkowy. Mial juz kilka cennych zasad:

### 1. Twarde okna w czasie polskim

W `CONFIG/strategy.json` oraz `BIN/safetybot.py` aktywne byly:
- `FX_AM` = `09:00-12:00` Europe/Warsaw
- `METAL_PM` = `14:00-17:00` Europe/Warsaw
- `INDEX_EU` = `12:00-14:00` Europe/Warsaw
- `INDEX_US` = `17:00-20:00` Europe/Warsaw

Bylo tez okno:
- `FX_ASIA` = `09:00-18:00` `Asia/Tokyo`

Czyli system nie liczyl wszystkiego "na sztywno po UTC", tylko mial kotwice czasowe per rynek i umial poprawnie zyc z DST.

### 2. Rozgrzewka przed kolejnym oknem

System mial `trade_window_prefetch`:
- domyslny lead `15` minut,
- shortlist dla nastepnego okna,
- opcjonalne rozgrzewanie wskaznikow tylko z lokalnego store,
- bez nowych wejsc i bez agresywnego fetchowania.

To jest bardzo dobre rozwiazanie i warto je zachowac.

### 3. Krotki carryover po przelaczeniu

System mial tez `carryover`:
- domyslnie `3` minuty,
- telemetria / observation-first,
- bez wymuszania nowych wejsc.

To jest bezpieczniejszy sposob "wydluzenia oddechu" niz brutalne poszerzanie glownego okna.

### 4. Rzeczywiste historyczne skany

W `DOCS/SESSION_HANDOFF_2026-02-23_2348.md` zostal juz zapisany wynik skanu:
- metale (`GOLD/SILVER/COPPER`) najlepiej wygladaly zwykle w oknach `15:00-19:00` lub `16:00-19:00` czasu polskiego.

To jest bardzo wazne, bo pokazuje, ze operacyjne `14:00-17:00` bylo bezpiecznym oknem startowym, ale niekoniecznie jedynym albo najlepszym oknem docelowym.

## Co z tego wynika dla nowego systemu

Nie powinnismy od razu rozszerzac bazowego handlu metali na cale `13:30-18:00` albo `14:00-19:00` jako jednej plamy.

Rozsadniejszy model jest taki:

### Etap 1. Okno bazowe, sprawdzone operacyjnie

- `METALS_PM_CORE`
- `14:00-17:00` Europe/Warsaw
- normalne nowe wejscia dozwolone

### Etap 2. Rozgrzewka przed metalami

- `METALS_PM_PREWARM`
- `13:45-14:00` Europe/Warsaw
- observation-only
- shortlist, ocena spreadu, rozruch wskaznikow, ocena nastroju

### Etap 3. Wydluzony shadow po metalach

- `METALS_PM_EXT_SHADOW`
- `17:00-19:00` Europe/Warsaw
- na poczatku observation-only
- bez nowych wejsc dopoki nowy system nie potwierdzi, ze przewaga po `17:00` rzeczywiscie istnieje

To rozwiazuje dwa problemy naraz:
- nie zostawiamy systemu slepego po `17:00`,
- ale tez nie dajemy mu od razu prawa do niepotwierdzonego tradingu.

## Proponowany dzienny rytm rodzin w czasie polskim

Jesli chcemy unikac bezsensownych nakladek i jednoczesnie nie zostawiac dnia pustego, to najlepszy dzisiejszy szkic jest taki:

### FX_ASIA

Kotwica:
- `Asia/Tokyo`

Proponowane aktywne okno:
- `09:00-16:00` Tokio

To daje orientacyjnie:
- zima PL: okolo `01:00-08:00`
- lato PL: okolo `02:00-09:00`

To jest lepsze niz dawne `09:00-18:00` Tokio, bo nie wchodzi nam tak mocno na `FX_AM`.

### FX_MAIN

- `09:00-12:00` Europe/Warsaw

### INDEX_EU

- `12:00-14:00` Europe/Warsaw

### METALS

- `13:45-14:00` prewarm / observation-only
- `14:00-17:00` core trade
- `17:00-19:00` extended shadow

### INDEX_US

- `17:00-20:00` Europe/Warsaw

## Co z akcjami / ETF

W starym systemie realnie bardziej dojrzala byla rodzina `INDEX`, nie `ETF`.

`EQUITY` bylo przygotowane architektonicznie w schedulerze, ale:
- nie mialo aktywnych `trade_windows` w `CONFIG/strategy.json`,
- nie bylo aktywowane produkcyjnie,
- grupa byla traktowana bardziej jako przyszly kierunek niz dojrzala rodzina wdrozeniowa.

Jednoczesnie scheduler pokazuje juz sensowne amerykanskie okna dla `EQUITY`:
- `09:30-11:00` New York
- `15:00-16:00` New York

W czasie polskim daje to praktycznie przez caly rok:
- `15:30-17:00` PL
- `21:00-22:00` PL

Czyli przyszla rodzina bardziej przypomina:
- `INDICES_US_EU`
albo pozniej:
- `EQUITY_US`

niz klasyczne ETF-y gotowe do natychmiastowego rollout-u.

## Rodzina metali: jeden parasol, dwie podrodziny

Najbardziej sensowna architektura na start:

### Rodzina nadrzedna

- `METALS`

### Podrodzina 1

- `METALS_SPOT_PM`
- `GOLD.pro`
- `SILVER.pro`

### Podrodzina 2

- `METALS_FUTURES`
- `PLATIN.pro`
- `COPPER-US.pro`

To jest czystsze niz wrzucenie wszystkiego do jednego worka, bo:
- zloto i srebro sa bardziej klasycznymi metalami spot / precious metals,
- platyna i miedz sa bardziej kontraktowo-przemyslowe i beda mialy inny charakter spreadu, impulsu i sesji.

## Co warto przeniesc 1:1 ze starego systemu

Do nowego projektu warto przeniesc bez kombinowania:
- kotwice czasowe per okno,
- `Europe/Warsaw` jako jezyk operatora,
- `Asia/Tokyo` jako kotwice dla Azji,
- `trade_window_prefetch_lead_min = 15`,
- `trade_window_carryover_minutes = 3`,
- observation-first dla prewarm i extended window,
- brak nowych wejsc poza aktywnym oknem dopoki nie ma dowodu przewagi.

## Czego nie kopiowac bezmyslnie

Nie kopiowalbym na slepo:
- dawnego `FX_ASIA = 09:00-18:00` Tokio,
- rozszerzania glownego okna metali bez shadow i danych,
- wrzucania `INDEX` i `EQUITY` do jednej rodziny,
- traktowania `COPPER-US.pro` identycznie jak `GOLD.pro`.

## Wniosek operacyjny

Na dzis:
- miedz potwierdzamy jako `COPPER-US.pro`,
- rodzina metali ma startowac w czworke:
  - `GOLD.pro`
  - `SILVER.pro`
  - `PLATIN.pro`
  - `COPPER-US.pro`
- architektura ma byc:
  - jedna rodzina `METALS`
  - dwie podrodziny:
    - `METALS_SPOT_PM`
    - `METALS_FUTURES`
- glowne aktywne okno metali zostaje na start:
  - `14:00-17:00` PL
- ale od razu dokladamy:
  - `13:45-14:00` prewarm
  - `17:00-19:00` extended shadow

To daje nam porzadek, przewidywalnosc i miejsce na uczenie bez rozwalania dyscypliny godzinowej.

## Zrodla

Oficjalne:
- OANDA/TMS Financial Instruments Specification:
  - `https://www.oanda.com/eu-en/sites/default/files/document_files/sif-tms-connect-eng-20.10.2025.pdf`
- OANDA commodities CFD:
  - `https://www.oanda.com/eu-en/commodities-cfd`
- OANDA trading account:
  - `https://www.oanda.com/eu-en/invest/trading-account`

Lokalne:
- `C:\OANDA_MT5_SYSTEM\CONFIG\strategy.json`
- `C:\OANDA_MT5_SYSTEM\BIN\safetybot.py`
- `C:\OANDA_MT5_SYSTEM\BIN\scheduler.py`
- `C:\OANDA_MT5_SYSTEM\DOCS\TRADE_WINDOW_EXTENSIONS_V1.md`
- `C:\OANDA_MT5_SYSTEM\DOCS\SESSION_HANDOFF_2026-02-23_2348.md`
