# Training Window Instrument Fit - 2026-03-15

## Cel

Ten dokument dopasowuje najlepsze instrumenty treningowe do juz ustalonych okien doby.

To nie jest jeszcze plan montazu do terminala.
To jest mapa:

- ktore instrumenty powinny byc glowne w danym oknie,
- ktore moga byc drugie w kolejnosci,
- ktore warto trzymac tylko w cieniu,
- oraz gdzie lepiej niczego nie wciskac na sile.

## Zasada ogolna

Stary `OANDA_MT5_SYSTEM` ma byc laboratorium i nauczycielem, nie szeroka siecia wszystkiego naraz.

Dlatego do kazdego okna dobieramy:

- `PRIMARY`: instrument najczystszy do treningu w tym pasmie,
- `SECONDARY`: instrument dobry, ale niekonieczny,
- `SHADOW`: instrument tylko obserwacyjny / druga faza.

Na starcie lepiej trenowac:

- mniej instrumentow,
- ale w lepszym dopasowaniu do okna,
- niz szeroko i kosztowo chaotycznie.

## Okna zgodne z obecnym rytmem dnia

### 1. FX_ASIA

#### Czas polski

- zima: `01:00-08:00`
- lato: `02:00-09:00`

#### Najlepsze dopasowanie

- `PRIMARY`: `USDJPY.pro`
- `SECONDARY`: `AUDUSD.pro`
- `SHADOW`: brak w fazie 1

#### Dlaczego

- `USDJPY.pro` jest najczystszym treningowym instrumentem dla azjatyckiego pasma
- ma niski koszt wzgledem pozostalych kandydatow JPY
- dobrze uczy starego systemu sesji azjatyckiej bez wrzucania od razu w drozsze krzyze
- `AUDUSD.pro` moze byc dobrym drugim bohaterem, jesli chcemy lekki most miedzy Azja i pozniejsza Europa

#### Czego nie dawac na start

- `EURJPY`
- `AUDJPY`
- `NZDJPY`

Powod:

- sa cennym materialem do etapu drugiego,
- ale do pierwszego treningu sa bardziej kosztowe i mniej czyste niz `USDJPY.pro`

---

### 2. FX_AM

#### Czas polski

- `09:00-12:00`

#### Najlepsze dopasowanie

- `PRIMARY`: `EURUSD.pro`
- `SECONDARY`: `GBPUSD.pro`
- `SECONDARY`: `AUDUSD.pro`
- `SHADOW`: `USDCHF.pro`
- `SHADOW`: `USDCAD.pro`

#### Dlaczego

- `EURUSD.pro` jest najczystszym i najtanszym kandydatem do porannego treningu FX
- `GBPUSD.pro` daje zywszy ruch i dobrze uzupelnia `EURUSD.pro`
- `AUDUSD.pro` jest tanszy i czytelniejszy niz wiekszosc rezerwowych majors
- `USDCHF.pro` i `USDCAD.pro` maja sens, ale do glownej bazy treningowej sa mniej wdzieczne kierunkowo

#### Praktyczny wariant minimalny

Jesli chcesz bardzo czysty trening poranny:

- tylko `EURUSD.pro`
- plus `GBPUSD.pro` jako drugi

To juz daje bardzo dobra baze bez przepelniania okna.

---

### 3. INDEX_EU

#### Czas polski

- `12:00-14:00`

#### Najlepsze dopasowanie

- `PRIMARY`: `DE30.pro`
- `SHADOW`: brak w fazie 1

#### Dlaczego

- `DE30.pro` jest najlepszym europejskim kandydatem indeksowym do treningu
- ma oficjalnie bardzo korzystny kosztowy pas `09:00-20:00` CET
- w naszym rytmie dnia okno `12:00-14:00` jest kompromisem architektonicznym i nadal nadaje sie do treningu

#### Wazna uwaga

Jesli celem bylby tylko najlepszy koszt i ruch dla `DE30.pro`, lepsze byloby `09:00-12:00`.

Ale jesli chcemy zachowac obecny porzadek okien:

- `DE30.pro` zostaje samotnym i poprawnym bohaterem `INDEX_EU`

---

### 4. METALS

#### Czas polski

- okno operacyjne: `14:00-17:00`
- najlepszy praktyczny trening: `15:00-18:30`
- shadow po rdzeniu: `17:00-19:00`

#### Najlepsze dopasowanie

- `PRIMARY`: `GOLD.pro`
- `SECONDARY`: `SILVER.pro`
- `SHADOW`: `COPPER-US.pro`

#### Dlaczego

- `GOLD.pro` jest najczystszym metalem do treningu
- `SILVER.pro` dobrze uzupelnia zloto i daje druga temperature ruchu
- `COPPER-US.pro` jest cennym materialem obserwacyjnym, ale kosztowo jest zbyt ciezki na glowny rdzen pierwszej fazy

#### Praktyczny wariant minimalny

Jesli ma byc bardzo czysto:

- tylko `GOLD.pro`

Jesli ma byc nadal lekko, ale bogaciej:

- `GOLD.pro`
- `SILVER.pro`

---

### 5. INDEX_US

#### Czas polski

- zgodnie z obecnym rytmem: `17:00-20:00`

#### Najlepsze dopasowanie

- `PRIMARY`: `US500.pro`
- `SHADOW`: brak w fazie 1

#### Dlaczego

- `US500.pro` jest najczystszym amerykanskim indeksem do treningu
- lepiej nadaje sie do budowy stabilniejszej bazy niz bardziej nerwowy `US100`
- dobrze uczy starego systemu reakcji na amerykanska sesje bez przesadnej szarpaniny

#### Wazna uwaga

Jesli celem bylby tylko najlepszy trening reakcji na amerykanskie otwarcie, lepsze byloby:

- `15:30-18:00`

Ale przy obecnym porzadku dnia:

- `US500.pro` dobrze pasuje do `17:00-20:00`

## Wolne okna doby i co z nimi robic

### Zima

- `00:00-01:00`
- `08:00-08:45`
- `20:00-24:00`

### Lato

- `00:00-02:00`
- `20:00-24:00`

### Rekomendacja

Nie wciskac tam niczego na sile.

Jesli chcemy eksperymentow treningowych w wolnych pasach, to tylko jako:

- `SHADOW_ONLY`
- osobny eksperyment
- bez mieszania z rdzeniem dnia

Najzdrowsze instrumenty do takich eksperymentow:

- `USDJPY.pro` w nocnym pasie przed Azja
- `US500.pro` lub `GOLD.pro` w wieczornym cieniu tylko wtedy, gdy bedziemy chcieli osobnego programu badawczego

## Najlepszy praktyczny uklad startowy

Jesli chcemy najczystszy trening starego systemu, dopasowany do juz ustalonych okien, to:

- `FX_ASIA`: `USDJPY.pro`
- `FX_AM`: `EURUSD.pro`, `GBPUSD.pro`
- `INDEX_EU`: `DE30.pro`
- `METALS`: `GOLD.pro`, `SILVER.pro`
- `INDEX_US`: `US500.pro`

To daje lacznie `7` instrumentow i bardzo dobry kompromis miedzy:

- kosztem,
- roznorodnoscia rynku,
- czytelnoscia treningu,
- i ograniczeniem szumu.

## Wersja jeszcze czystsza

Jesli chcemy absolutne minimum skutecznego treningu:

- `USDJPY.pro`
- `EURUSD.pro`
- `DE30.pro`
- `GOLD.pro`
- `US500.pro`

To jest moim zdaniem najlepsza piatka szkoleniowa starego systemu.

## Zrodla

Wewnetrzne:

- `DOCS/TRAINING_UNIVERSE_MT5_OANDA_2026-03-15.md`
- `DOCS/STRATEGY_PHILOSOPHY.md`
- `DOCS/SESSION_HANDOFF_2026-02-23_2348.md`
- `CONFIG/strategy.json`

Zewnetrzne:

- `https://help.oanda.com/eu/pl/faqs/mt5-user-guide-eu.htm`
- `https://www.oanda.com/eu-en/sites/default/files/document_files/sif-tms-connect-eng-20.10.2025.pdf`
- `https://www.oanda.com/uk-en/trading/historical-spreads/`
- `https://help.oanda.com/eu/en/faqs/check-spreads-eu.htm`
