# Training Universe MT5 OANDA - 2026-03-15

## Cel

Ten dokument nie wybiera instrumentow do najszybszego scalpingu runtime.

On wybiera instrumenty do:

- krotkoterminowego treningu,
- budowy czystszej bazy etykiet,
- domykania petli `entry -> close -> outcome`,
- oraz uczenia starego `OANDA_MT5_SYSTEM`, ktory jest mocny logicznie, ale zbyt ciezki na agresywny micro-scalping.

## Punkt wyjscia ze starego systemu

Stary system juz sam podpowiada trzy glowne klasy aktywow:

- `FX`
- `METAL`
- `INDEX`

Potwierdzaja to:

- `CONFIG/strategy.json`
- `DOCS/STRATEGY_PHILOSOPHY.md`
- `DOCS/SESSION_HANDOFF_2026-02-23_2348.md`

W starym systemie zywe okna byly ustawione glownie tak:

- `FX_AM`: `09:00-12:00` PL
- `METAL_PM`: `14:00-17:00` PL
- `INDEX_EU`: `12:00-14:00` PL
- `INDEX_US`: `17:00-20:00` PL
- `FX_ASIA`: wg kotwicy `Asia/Tokyo`

## Zasada wyboru instrumentow do treningu

Do treningu wybieramy nie to, co jest tylko "ciekawe", ale to, co daje najlepszy kompromis:

- niski lub wzglednie niski koszt,
- szeroka i stabilna plynnosc,
- sensowny czas handlu,
- duzo danych historycznych w MT5,
- prostsza interpretacja wyniku przez learner offline.

To oznacza:

- preferuj majors i glowne indeksy,
- ogranicz liczbe instrumentow na starcie,
- odloz krzyze i drozsze metale/futures do fazy drugiej,
- nie mieszaj treningu z instrumentami egzotycznymi i kosztowo ciezkimi.

## Najlepszy koszyk treningowy - faza 1

### FX core

1. `EURUSD.pro`
2. `USDJPY.pro`
3. `GBPUSD.pro`
4. `AUDUSD.pro`

### Metals core

5. `GOLD.pro`
6. `SILVER.pro`

### Indices core

7. `DE30.pro`
8. `US500.pro`

## Dlaczego te 8

### 1. EURUSD.pro

- najczystszy kandydat FX do treningu
- bardzo szeroki czas handlu
- w specyfikacji OANDA ma niski dodatkowy markup dla low balance account: `0.00002`
- nadaje sie do treningu kierunku, dyscypliny kosztu i reakcji na regime change

### 2. USDJPY.pro

- nadal jeden z najczystszych i najtanszych majors
- wspiera sesje azjatycka, ktorej nie daja pary europejskie
- w specyfikacji OANDA ma niski dodatkowy markup: `0.002`

### 3. GBPUSD.pro

- bardzo plynny instrument londynski
- drozszy od `EURUSD`, ale nadal bardzo dobry do treningu porannego FX
- dobry do nauki, gdy ruch jest zywszy niz na `EURUSD`

### 4. AUDUSD.pro

- dobry most miedzy Azja i Europa
- oficjalnie nalezy do instrumentow, dla ktorych OANDA w modelu core wymienia bardzo niskie spready bazowe
- dobry trening dla systemu w godzinach slabszej europejskiej dominacji

### 5. GOLD.pro

- najczystszy metal do treningu
- stary system juz go uprzywilejowal w praktyce
- lokalny skan okien z 21 dni M1 wskazal, ze metale zwykle wygladaja najlepiej okolo `15:00-19:00` PL

### 6. SILVER.pro

- dobry drugi metal treningowy
- podobna logika czasowa co zloto
- pozwala uczyc system roznych "temperatur" metalu bez wchodzenia od razu w drozszy futures-like chaos

### 7. DE30.pro

- najlepszy kandydat indeksowy dla Europy
- oficjalna specyfikacja OANDA podaje dla niego wyjatkowo cenny detal:
  - minimalny spread:
    - `01:20-08:00` CET: `4.6 pts`
    - `08:00-09:00` CET: `2.6 pts`
    - `09:00-20:00` CET: `0.9 pts`
    - `20:00-22:00` CET: `2.6 pts`
- to czyni `DE30` najlepszym europejskim indeksem do treningu kosztowego i kierunkowego

### 8. US500.pro

- najczystszy indeks amerykanski do treningu
- szerokie godziny notowan
- bardziej "porzadny" do nauki ogolnego kierunku niz bardziej szarpany `US100`
- nadaje sie do uczenia wejsc na otwarcie USA i pierwsza faze sesji kasowej

## Faza 2 - instrumenty rezerwowe / shadow training

Nie wyrzucam ich calkiem, ale nie dalbym ich do pierwszego rdzenia treningowego:

- `USDCAD.pro`
- `USDCHF.pro`
- `COPPER-US.pro`

### USDCAD.pro

- wciaz sensowny FX major
- dobry jako rezerwa na sesje z silnym ruchem USD i Kanady
- ale do pierwszej czystej bazy wolalbym `AUDUSD` lub `GBPUSD`

### USDCHF.pro

- kosztowo akceptowalny
- ale czesto mniej wdzieczny kierunkowo niz `EURUSD` czy `USDJPY`

### COPPER-US.pro

- warto go trzymac w cieniu treningowym
- ale nie wrzucalbym do glownego koszyka na start
- powod:
  - w oficjalnej specyfikacji ma bardzo duzy dodatkowy markup (`15`)
  - stary system i nowy system oba traktuja go ostrozniej niz `GOLD` / `SILVER`

## Czego nie brac do fazy 1

- `EURJPY`, `GBPJPY`, `EURAUD`, `GBPAUD`
  - za drogie i zbyt zlozone jak na pierwsza czysta baze treningowa
- `PALLAD`
  - zbyt kosztowy i zdradliwy
- `US30`, `US100`
  - dobre do etapu drugiego, ale do uczenia rdzenia wolalbym najpierw `US500`
- ETF i krypto
  - nie sa potrzebne do pierwszego skutecznego treningu starego systemu

## Okna treningowe o najlepszym sensie kosztowym

Poniżej podaje okna w czasie polskim.

### FX - glowny trening dzienny

- `09:00-12:00` PL

To zostaje najlepszym glownym oknem treningowym dla:

- `EURUSD.pro`
- `GBPUSD.pro`
- `AUDUSD.pro`

### FX - trening azjatycki

- zima: `01:00-08:00` PL
- lato: `02:00-09:00` PL

Tu glownym bohaterem powinien byc:

- `USDJPY.pro`

Jesli nie chcesz trenowac w nocy, po prostu nie wlaczaj tego okna do pierwszej iteracji.

### Metale - najlepsze okno treningowe

- rdzen live/training:
  - `14:00-17:00` PL
- lepsze okno badawcze, wynikajace ze skanu starego systemu:
  - `15:00-19:00` PL
- najmocniejszy praktyczny kompromis:
  - `15:00-18:30` PL

To okno dotyczy glownie:

- `GOLD.pro`
- `SILVER.pro`

`COPPER-US.pro` tylko jako shadow.

### INDEX_EU - najlepsze okno treningowe

- kosztowo najlepszy pas dla `DE30.pro`:
  - `09:00-20:00` CET wedlug oficjalnej specyfikacji
- praktyczny rdzen treningu:
  - `09:00-12:00` PL
- okno zgodne ze stara architektura:
  - `12:00-14:00` PL

Wniosek:

- jesli chcesz trenowac skutecznosc, bierz `09:00-12:00`
- jesli chcesz zachowac zgodnosc ze starym rytmem systemu, zostaw `12:00-14:00`

### INDEX_US - najlepsze okno treningowe

- praktyczny rdzen:
  - `15:30-18:00` PL
- stary, spokojniejszy kompromis operacyjny:
  - `17:00-20:00` PL

Wniosek:

- do uczenia wejsc i reakcji na swieze otwarcie USA lepsze jest `15:30-18:00`
- do bardziej konserwatywnego treningu zgodnego ze starym schedulerem zostaw `17:00-20:00`

## Rekomendacja koncowa

### Jesli chcesz najczystszy, pierwszy koszyk treningowy

Podlacz:

- `EURUSD.pro`
- `USDJPY.pro`
- `GBPUSD.pro`
- `AUDUSD.pro`
- `GOLD.pro`
- `SILVER.pro`
- `DE30.pro`
- `US500.pro`

### Jesli chcesz jeszcze prostsza wersje "minimum viable training"

Podlacz tylko:

- `EURUSD.pro`
- `USDJPY.pro`
- `GOLD.pro`
- `DE30.pro`
- `US500.pro`

To jest moim zdaniem najlepszy rdzen:

- tani,
- plynny,
- mocno rozny charakterem,
- ale nieprzesadnie szeroki.

## Wazne rozroznienie

To jest koszyk do treningu starego systemu.

Nie oznacza to automatycznie:

- najlepszego koszyka do micro-scalpingu live,
- ani najlepszego koszyka do nowej floty mikro-botow.

Stary system ma byc tu nauczycielem i laboratorium:

- mniej instrumentow,
- czystsza baza,
- lepsze outcome labels,
- mniej kosztowego szumu.

## Zrodla zewnetrzne

- OANDA TMS MT5 user guide:
  - https://help.oanda.com/eu/pl/faqs/mt5-user-guide-eu.htm
- OANDA TMS instrument specification CFD:
  - https://www.oanda.com/eu-en/sites/default/files/document_files/sif-tms-connect-eng-20.10.2025.pdf
- OANDA historical spreads page:
  - https://www.oanda.com/uk-en/trading/historical-spreads/
- OANDA spread FAQ:
  - https://help.oanda.com/eu/en/faqs/check-spreads-eu.htm

## Zrodla wewnetrzne

- `DOCS/STRATEGY_PHILOSOPHY.md`
- `DOCS/SESSION_HANDOFF_2026-02-23_2348.md`
- `CONFIG/strategy.json`
