# Free Windows Training Fit - 2026-03-15

## Cel

Ten dokument odpowiada na jedno konkretne pytanie:

- skoro nowa flota mikro-botow ma juz swoje glowne okna,
- to jakie instrumenty starego `OANDA_MT5_SYSTEM` warto dopasowac **tylko do wolnych okien doby**,
- tak zeby oba organizmy nie nachodzily na siebie.

To nie jest mapa dla calego dnia.
To jest mapa tylko dla pasm, ktore zostaja wolne po odjeciu:

- aktywnych okien `FX_ASIA`
- `FX_AM`
- `INDEX_EU`
- `METALS`
- `INDEX_US`
- oraz lokalnych prewarm / shadow, gdzie sa istotne operacyjnie

## Najwazniejsza zasada

Nie kazde wolne okno trzeba zapelniac.

Jesli okno jest wolne, ale:

- ma slaba plynnosc,
- jest blisko rollover,
- albo kosztowo robi sie zdradliwe,

to lepiej zostawic je jako:

- `EMPTY`
albo
- `SHADOW_ONLY`

zamiast wciskac tam trening live na sile.

## Wolne okna - zima, czas polski

### 1. `00:00-01:00`

#### Rekomendacja

- `PRIMARY`: brak dla normalnego live-treningu
- `SHADOW_ONLY`: `USDJPY.pro`
- `SHADOW_ONLY`: `AUDUSD.pro`

#### Dlaczego

- to jest jeszcze pas przed glownym azjatyckim rytmem
- rynek zaczyna sie dopiero rozpedzac
- okno jest za krotkie i za malo pewne, zeby robic z niego glowny slot starego systemu

#### Wniosek

Najlepiej:

- zostawic puste
albo
- uzywac tylko do lekkiej obserwacji `USDJPY.pro`

---

### 2. `08:00-08:45`

#### Rekomendacja

- `PRIMARY`: `DE30.pro`
- `SHADOW_ONLY`: brak

#### Dlaczego

- to jest jedyne poranne wolne okno miedzy zakonczeniem `FX_ASIA` a prewarmem `FX_AM`
- dla `DE30.pro` oficjalna specyfikacja OANDA podaje:
  - `08:00-09:00` CET: minimalny spread `2.6 pts`
  - `09:00-20:00` CET: minimalny spread `0.9 pts`
- czyli to nie jest najlepszy pas dnia dla `DE30.pro`, ale nadal jest to logiczny i czysty kandydat do krotkiego treningu bez konfliktu z nowa flota

#### Wniosek

Jesli chcemy wykorzystac to zimowe mini-okno, `DE30.pro` jest najlepszym wyborem.

---

### 3. `20:00-21:59`

#### Rekomendacja

- `PRIMARY`: `US500.pro`
- `SECONDARY`: `GOLD.pro`
- `SHADOW_ONLY`: `SILVER.pro`

#### Dlaczego

- po zakonczeniu okna `INDEX_US` nowej floty zostaje jeszcze kawalek amerykanskiego dnia
- `US500.pro` jest nadal najczystszym kandydatem indeksowym do treningu
- `GOLD.pro` pozostaje sensowny, bo metalowy handel trwa szeroko i nadal ma wartosc obserwacyjna po glownym pasmie dnia
- `SILVER.pro` jest bardziej nerwowy i w tym pozniejszym pasmie lepiej zostawic go jako obserwacje niz glowny slot

#### Wniosek

To jest najlepsze wieczorne wolne okno do realnego treningu starego systemu.

Jesli mamy wybrac tylko jeden instrument:

- `US500.pro`

Jesli dwa:

- `US500.pro`
- `GOLD.pro`

---

### 4. `22:00-24:00`

#### Rekomendacja

- `PRIMARY`: brak
- `SHADOW_ONLY`: brak
- stan zalecany: `EMPTY`

#### Dlaczego

- to jest pas blisko dziennego rollover i slabszej plynnosci
- OANDA wprost zaznacza, ze spready potrafia sie rozszerzac przy slabnacej plynnosci i wokol zamkniec
- nawet jesli czesc instrumentow technicznie jest jeszcze dostepna, to kosztowo nie jest to zdrowe miejsce na czysty trening

#### Wniosek

To okno najlepiej zostawic puste.

## Wolne okna - lato, czas polski

### 1. `00:00-02:00`

#### Rekomendacja

- `00:00-01:00`: `EMPTY`
- `01:00-02:00`: `SHADOW_ONLY` dla `USDJPY.pro`

#### Dlaczego

- dopiero druga czesc tego okna zaczyna zblizac sie do sensownego przygotowania pod Azje
- nadal nie jest to dojrzały, glowny slot treningowy

#### Wniosek

W lecie nie robilbym z tego glownego okna live-treningu.
Jesli juz, to tylko jako rozgrzewke obserwacyjna dla `USDJPY.pro`.

---

### 2. `20:00-21:59`

#### Rekomendacja

- `PRIMARY`: `US500.pro`
- `SECONDARY`: `GOLD.pro`
- `SHADOW_ONLY`: `SILVER.pro`

#### Wniosek

Tak samo jak zima, to jest najlepszy letni wolny pas do sensownego treningu starego systemu.

---

### 3. `22:00-24:00`

#### Rekomendacja

- `EMPTY`

#### Wniosek

Nie wciskac tam treningu na sile.

## Rekomendacja koncowa - stary system tylko w wolnych oknach

Jesli chcemy, zeby stary system wchodzil tylko tam, gdzie nowa flota nie pracuje, najlepszy praktyczny uklad jest taki:

### Zima

- `08:00-08:45` -> `DE30.pro`
- `20:00-21:59` -> `US500.pro`
- `20:00-21:59` -> dodatkowo `GOLD.pro` jako drugi kandydat

### Lato

- `20:00-21:59` -> `US500.pro`
- `20:00-21:59` -> dodatkowo `GOLD.pro`

### W obu sezonach

- nocne pasy przed Azja:
  - nie jako glowny live
  - najwyzej `USDJPY.pro` w `SHADOW_ONLY`
- `22:00-24:00`:
  - zostawic puste

## Najlepsza wersja minimalna

Jesli chcesz najczystszy wariant bez przepelniania:

- `DE30.pro` w zimowym `08:00-08:45`
- `US500.pro` codziennie w `20:00-21:59`
- `GOLD.pro` tylko jako drugi, lzejszy eksperyment wieczorny

To jest moim zdaniem najlepszy most miedzy:

- wolnymi oknami,
- sensownym kosztem,
- i brakiem konfliktu z nowa flota.

## Zrodla

Wewnetrzne:

- `DOCS/TRAINING_UNIVERSE_MT5_OANDA_2026-03-15.md`
- `DOCS/TRAINING_WINDOW_INSTRUMENT_FIT_2026-03-15.md`
- `DOCS/STRATEGY_PHILOSOPHY.md`
- `DOCS/SESSION_HANDOFF_2026-02-23_2348.md`
- `CONFIG/strategy.json`

Zewnetrzne:

- `https://www.oanda.com/eu-en/sites/default/files/document_files/sif-tms-connect-eng-20.10.2025.pdf`
- `https://www.oanda.com/eu-en/sites/default/files/media/file/2026-03/tms_time_change_usa_2026_eng.pdf`
- `https://help.oanda.com/eu/en/faqs/check-spreads-eu.htm`
- `https://www.oanda.com/uk-en/trading/historical-spreads/`
- `https://help.oanda.com/us/en/faqs/hours-of-operation.htm`
