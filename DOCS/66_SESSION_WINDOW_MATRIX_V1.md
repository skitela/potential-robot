# 66. Session Window Matrix V1

## Cel

Rozlozyc w jednym miejscu piec glownych rodzin / grup operacyjnych:
- `FX_ASIA`
- `FX_AM`
- `INDEX_EU`
- `METALS`
- `INDEX_US`

w czasie polskim, z uwzglednieniem:
- tego co bylo juz zakodowane i sprawdzone w `OANDA_MT5_SYSTEM`,
- tego co mowi dzisiejsza oficjalna oferta OANDA/TMS,
- tego ze jedna grupa moze miec wiecej niz jedno sensowne "gorne" okno,
- ale nie wszystko musi od razu dostac prawo do nowych wejsc.

## Najwazniejsze doprecyzowanie: FX_ASIA

Wczesniej zapis `09:00-16:00` dotyczyl czasu `Asia/Tokyo`, a nie czasu polskiego.

To znaczy:
- `09:00-16:00` Tokio
- to w Polsce daje mniej wiecej:
  - zima: `01:00-08:00`
  - lato: `02:00-09:00`

Czyli tak, `FX_ASIA` jest gleboko w naszej nocy i nad ranem. To sie zgadza z intuicja i z dawna logika systemu.

## ETF / EQUITY

To trzeba odroznic bardzo jasno:

### Co pozwala broker

Oficjalnie OANDA w UE oferuje:
- ETF-y inwestycyjne,
- ETF CFD,
- rachunek brokerage na akcje i ETF,
- oraz osobne strony ETF / brokerage.

Czyli to **nie jest zakaz brokera**.

### Co blokowal stary system

Stary `OANDA_MT5_SYSTEM` mial celowy bezpiecznik:
- blokade algorytmicznego otwierania na symbolach `ETF/ETN/EQUITY`

To byla decyzja architektoniczna bezpieczeństwa, a nie dowod, ze OANDA tego nie oferuje.

### Wniosek

Na teraz:
- nie budujemy rodziny `ETF`,
- nie dlatego, ze broker zabrania,
- tylko dlatego, ze nasz dawny system celowo nie dopuszczal tam automatycznego wejscia i nie mamy jeszcze dojrzalej architektury tej rodziny.

Najbardziej naturalna rodzina po metalach wyglada dzis raczej jako:
- `INDEX`
albo pozniej:
- `EQUITY_US`

## Macierz okien - czas polski

Poniżej rozdzielam:
- okna operacyjne teraz,
- dodatkowe gorki historyczne / rynkowe,
- i decyzje co wolno robic od razu, a co tylko obserwowac.

---

## 1. FX_ASIA

### Kotwica rynku

- `Asia/Tokyo`

### Glowny zakres rynku

- `09:00-16:00` Tokio
- czyli:
  - zima PL: `01:00-08:00`
  - lato PL: `02:00-09:00`

### Proponowany podzial wewnetrzny

- `FX_ASIA_CORE_1`
  - `01:00-05:00` PL zima
  - `02:00-06:00` PL lato
- `FX_ASIA_CORE_2`
  - `05:00-08:00` PL zima
  - `06:00-09:00` PL lato

### Ocena

To jest juz naturalnie "drugi raz na dobe" dla tej samej rodziny, ale wewnatrz jednej sesji azjatyckiej:
- pierwsza czesc bardziej nocna,
- druga czesc bardziej poranna i przejsciowa.

### Decyzja operacyjna

- handlowac mozna w calej aktywnej sesji `FX_ASIA`
- ale warto logowac te dwie podpory osobno
- bo agent strojenia moze potem stwierdzic, ze lepsza jest tylko jedna z nich

---

## 2. FX_AM

### Glowny sprawdzony slot

- `09:00-12:00` PL

### Co wiemy rynkowo

Dla forexu ogolnie jedna z najmocniejszych stref globalnych to nakladanie Londynu i Nowego Jorku.
Ale w naszym systemie ta czesc dnia jest juz obudowana metalami i indeksami, wiec nie warto na sile robic z tego drugiego aktywnego bloku `FX_MAIN` juz teraz.

### Decyzja operacyjna

- glowny trade window zostaje:
  - `09:00-12:00` PL
- mozna dodac:
  - `08:45-09:00` prewarm
- na razie nie otwieramy drugiego dziennego okna `FX_MAIN`, zeby nie mieszac rodzin i nie dublowac presji na budzet i kapital

---

## 3. INDEX_EU

### Co bylo operacyjnie

W dawnym systemie aktywne okno bylo:
- `12:00-14:00` PL

### Co pokazuje logika scheduler-a

W starym `scheduler.py` dla indeksow europejskich wagi byly mniej wiecej takie:
- `09:00-12:00` PL -> mocne
- `12:00-15:00` PL -> srednie
- `15:00-17:35` PL -> najsilniejsze

Czyli czysto rynkowo to nie bylo "najlepsze absolutne okno", tylko raczej **okno kompromisowe**, wstawione tak, zeby rodziny nie nakladaly sie zbyt agresywnie.

### Decyzja operacyjna

Na teraz:
- zostaje `12:00-14:00` PL jako okno operacyjne

Ale w dokumentacji trzeba juz jasno zapisac:
- `INDEX_EU` ma co najmniej dwie naturalne gorki:
  - `09:00-12:00`
  - `15:00-17:35`

To bedzie bardzo wazne, kiedy przyjdzie czas na osobne dojrzewanie indeksow.

---

## 4. METALS

### Co bylo operacyjnie

- `14:00-17:00` PL

### Co pokazal dawny skan historyczny

W starym systemie zapisano juz:
- metale (`GOLD/SILVER/COPPER`) najlepiej wygladaly zwykle w:
  - `15:00-19:00`
  - lub `16:00-19:00` PL

### Wniosek

Metale bardzo prawdopodobnie maja nie jedno, ale dwa sensowne obszary:
- wczesniejsze wejscie po starcie europejsko-amerykanskiego ruchu,
- oraz mocniejsza czesc pozniejsza, az do `19:00`.

### Decyzja operacyjna

Na teraz:
- `13:45-14:00` prewarm
- `14:00-17:00` core trade
- `17:00-19:00` extended shadow

I to jest bardzo wazne:
- nie zamieniamy od razu `17:00-19:00` na pelny trade,
- ale juz teraz zbieramy tam dane, bo to moze byc drugi bardzo wartosciowy szczyt tej rodziny.

---

## 5. INDEX_US

### Co bylo operacyjnie

- `17:00-20:00` PL

### Co wiemy o rynku

Dla amerykanskich indeksow naturalne gorki sa zwykle:
- przy otwarciu rynku USA,
- i w koncowce sesji USA.

To nie zawsze pokrywa sie idealnie z `17:00-20:00` PL, bo dochodzi DST i przesuniecia miedzy USA i Europa.

### Dlaczego mimo to zostawiamy `17:00-20:00`

Bo to jest:
- historycznie sprawdzone operacyjnie w dawnym systemie,
- czytelne dla operatora w czasie polskim,
- i nie rozwala nam ukladu rodzin w ciagu dnia.

### Co zapisac na przyszlosc

`INDEX_US` warto w przyszlosci rozdzielac na dwa mikro-okna:
- okolice amerykanskiego open,
- okolice koncowej godziny sesji,

ale nie trzeba tego wdrazac od razu, zanim nie zrobimy dla indeksow takiego samego researchu jak teraz dla metali.

---

## Rekomendowany uklad dnia - wersja operacyjna

### Noc / rano

- `FX_ASIA`
  - `01:00-08:00` PL zima
  - `02:00-09:00` PL lato

### Rano

- `FX_AM`
  - `09:00-12:00` PL

### Poludnie

- `INDEX_EU`
  - `12:00-14:00` PL

### Popoludnie

- `METALS`
  - `13:45-14:00` prewarm
  - `14:00-17:00` trade
  - `17:00-19:00` shadow

### Wieczor

- `INDEX_US`
  - `17:00-20:00` PL

## Gdzie juz teraz widac drugie gorki

Najbardziej czytelnie:

- `FX_ASIA`
  - naturalny podzial na dwie czesci nocy/poranka
- `METALS`
  - bardzo mocna szansa na druga gore po `17:00`
- `INDEX_EU`
  - dwa naturalne piki, ale na razie tylko jeden slot operacyjny
- `INDEX_US`
  - co najmniej dwa naturalne mikro-piki, ale jeszcze bez dedykowanego wdrozenia

Najmniej potrzebne teraz:

- drugi dzienny slot dla `FX_AM`

## Wniosek

Na dzisiaj nie potrzebujemy juz "jednego ciagu" dla wszystkich rodzin.
Potrzebujemy:
- jednego czytelnego rdzenia operacyjnego,
- oraz miejsc, w ktorych system moze juz obserwowac druga gore bez natychmiastowego prawa do nowych wejsc.

To daje nam najlepszy kompromis miedzy:
- zyskiem netto,
- ochrona kapitalu,
- porzadkiem rodzinnym,
- i dojrzewaniem agenta strojenia.

## Zrodla

Oficjalne OANDA:
- `https://www.oanda.com/eu-en/sites/default/files/document_files/sif-tms-connect-eng-20.10.2025.pdf`
- `https://www.oanda.com/eu-en/etf-funds-cfd`
- `https://www.oanda.com/eu-en/invest/brokerage-account`
- `https://www.oanda.com/eu-en/blog/oanda-introduces-etfs-to-its-offering-in-the-eu-0`

Lokalne:
- `C:\OANDA_MT5_SYSTEM\CONFIG\strategy.json`
- `C:\OANDA_MT5_SYSTEM\BIN\scheduler.py`
- `C:\OANDA_MT5_SYSTEM\BIN\safetybot.py`
- `C:\OANDA_MT5_SYSTEM\DOCS\SESSION_HANDOFF_2026-02-23_2348.md`
- `C:\MAKRO_I_MIKRO_BOT\DOCS\65_METALS_SESSION_AND_TIME_ARCHITECTURE_V1.md`
