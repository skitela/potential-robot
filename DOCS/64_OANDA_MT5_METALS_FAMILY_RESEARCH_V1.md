# 64. OANDA MT5 Metals Family Research V1

## Cel

Ten dokument porzadkuje odpowiedz na pytanie:

- jakie metale sa aktualnie sensowne dla OANDA MT5,
- ktore cztery wybrac do pierwszej rodziny roboczej,
- czy powinny stanowic jedna rodzine,
- i jaki podzial wewnetrzny ma najwiecej sensu pod warunki brokera oraz nasze systemy.

## Oficjalnie dostepne metale na OANDA TMS / MT5

Na podstawie aktualnej specyfikacji instrumentow OANDA TMS Brokers dla CFD (waznej od `20 pazdziernika 2025`, opublikowanej i indeksowanej jeszcze w `2026`) w koszyku metali/commodities dla MT5 mamy co najmniej nastepujace instrumenty:

- `GOLD.pro`
- `SILVER.pro`
- `PLATIN.pro`
- `PALLAD.pro`
- `COPPER-US.pro` / `XCUUSD`

To jest najwazniejszy punkt startowy: brokerowo rodzina metali nie konczy sie na zlocie i srebrze. Mamy pelne prawo przygotowac rodzine czterech metali, a nawet piatki, ale nie wszystkie powinny wejsc od razu do pierwszego rolloutu.

## Aktualne warunki brokerowe OANDA

### GOLD.pro

- typ: `Spot`
- nominal 1 lota: `Price * 100 USD`
- tick size: `0.01`
- dodatkowy markup low-balance: `0.12`
- margin retail / experienced: `5% / 1.5%`
- margin professional: `1% / 2% / 6%`
- godziny:
  - `monday-thursday 00:05-22:59`
  - `friday 00:05-21:59`

### SILVER.pro

- typ: `Spot`
- nominal 1 lota: `Price * 5 000 USD`
- tick size: `0.001`
- dodatkowy markup low-balance: `0.005`
- margin retail / experienced: `10% / 10%`
- margin professional: `1% / 2% / 6%`
- godziny:
  - `monday-thursday 00:05-22:59`
  - `friday 00:05-21:59`

### PLATIN.pro

- typ: `Platinum Futures`
- nominal 1 lota: `Price * 50 USD`
- tick size: `0.1`
- dodatkowy markup low-balance: `0.5`
- margin retail / experienced: `10% / 10%`
- margin professional: `2% / 5% / 10%`
- godziny:
  - `monday-thursday 00:01-22:59`
  - `friday 00:01-21:59`

### PALLAD.pro

- typ: `Palladium Futures`
- nominal 1 lota: `Price * 100 USD`
- tick size: `0.1`
- dodatkowy markup low-balance: `0.7`
- margin retail / experienced: `10% / 10%`
- margin professional: `2% / 5% / 10%`
- godziny:
  - `monday-thursday 00:01-22:59`
  - `friday 00:01-21:59`

### COPPER-US.pro / XCUUSD

- typ: `Copper`
- nominal 1 lota: `Price * 1 USD`
- tick size: `0.00001`
- dodatkowy markup low-balance: `15`
- margin retail / experienced: `10% / 10%`
- margin professional: `2% / 5% / 10%`
- godziny:
  - `monday-thursday 00:01-22:59`
  - `friday 00:01-21:59`

## Wazna uwaga o nazwach symboli

Tu jest jeden istotny szczegol techniczny.

W naszym starszym systemie `OANDA_MT5_SYSTEM` funkcjonuje metalowa logika dla:

- `XAUUSD`
- `XAGUSD`
- `PLATIN`
- `PALLAD`
- `COPPER-US`

Zloto i srebro maja juz udowodnione aliasy:

- `XAUUSD -> GOLD.pro`
- `XAGUSD -> SILVER.pro`

To jest potwierdzone lokalnie w:

- [test_symbol_aliases_oanda_mt5_pl.py](C:\OANDA_MT5_SYSTEM\tests\test_symbol_aliases_oanda_mt5_pl.py)

Natomiast dla miedzi aktualna oficjalna specyfikacja OANDA pokazuje wariant:

- `COPPER-US.pro / XCUUSD`

czyli przed rolloutem trzeba bedzie zrobic szybki snapshot z realnego Market Watch i potwierdzic, czy na naszym serwerze MT5 symbol wystepuje jako:

- `COPPER-US.pro`
- czy `XCUUSD.pro`

To nie jest problem architektury, tylko rzecz do spokojnego potwierdzenia przed wdrozeniem.

## Co mowi nasz starszy system o metalach

To jest bardzo cenny punkt odniesienia.

W starym `OANDA_MT5_SYSTEM` grupa `METAL` juz istnieje i ma zaszyte konkretne heurystyki:

- metalowy scoring wejsc,
- metalowy budget pacing,
- osobne progi ATR,
- osobne progi jakości knota i impulsu,
- okno `METAL_PM`

W `CONFIG/strategy.json` i `BIN/safetybot.py` mamy juz lokalna wiedze dla:

- `XAUUSD`
- `XAGUSD`
- `PLATIN`
- `PALLAD`
- `COPPER-US`

Co jeszcze wazniejsze, lokalne per-symbol spread capy sa juz bardzo czytelne:

- `XAUUSD`: `90`
- `COPPER-US`: `120`
- `XAGUSD`: `130`
- `PLATIN`: `140`
- `PALLAD`: `170`

To daje nam praktyczny ranking trudnosci kosztowej:

1. `GOLD`
2. `COPPER`
3. `SILVER`
4. `PLATIN`
5. `PALLAD`

To nie jest jeszcze ranking „najlepszy do zarabiania”, ale jest to bardzo dobra wskazowka, ktore instrumenty najlatwiej wprowadzic bez od razu wysokiego kosztowego chaosu.

## Co mowi nasz starszy system o oknach czasowych

W `OANDA_MT5_SYSTEM` od dawna istnieje okno:

- `METAL_PM = 14:00-17:00 PL`

Do tego mamy lokalny skan okien z historycznego materialu, ktory pokazal:

- dla `GOLD`, `SILVER` i `COPPER` najlepsze okna zwykle `15:00-19:00` albo `16:00-19:00` czasu polskiego

To jest bardzo cenna wiedza, bo pokazuje, ze nie zaczynamy rodziny metali od zera. Mamy juz sensowny zalazek rytmu dnia.

## Czy to powinna byc jedna rodzina

### Odpowiedz krotka

Tak, ale nie plaska.

Najrozsadniejszy model to:

- jedna rodzina nadrzedna: `METALS`
- i wewnetrzny podzial na dwie podrodziny robocze

### Dlaczego nie jedna plaska rodzina

Bo warunki brokerowe nie sa idealnie jednorodne:

- `GOLD` i `SILVER` sa `Spot`,
- `PLATIN`, `PALLAD` i `COPPER` sa instrumentami futures-based,
- zloto ma duzo lzejszy margin retail niz reszta,
- godziny `GOLD/SILVER` sa minimalnie przesuniete wzgledem `PLATIN/PALLAD/COPPER`,
- miedz ma inny charakter rynkowy niz klasyczne precious metals.

Czyli:

- mozna je trzymac pod jedna flaga `METALS`,
- ale nie wolno im wciskac jednej, identycznej osobowosci.

## Proponowana architektura rodziny

### Rodzina nadrzedna

- `METALS`

### Podrodzina 1

- `METALS_SPOT_PM`

Instrumenty:

- `GOLD.pro`
- `SILVER.pro`

Charakter:

- precious metals,
- wspolne godziny `00:05-22:59`,
- logicznie najblizsze staremu modelowi `XAU/XAG`.

### Podrodzina 2

- `METALS_FUTURES`

Instrumenty:

- `PLATIN.pro`
- `COPPER-US.pro / XCUUSD`
- opcjonalnie pozniej `PALLAD.pro`

Charakter:

- wspolne godziny `00:01-22:59`,
- wspolny brokerowy model `10% / 10%` dla retail/experienced,
- instrumenty bardziej surowcowo-futuresowe niz czysto spotowe.

## Ktore cztery metale polecam na start

Moja rekomendacja na pierwsza rodzine czterech metali jest taka:

- `GOLD.pro`
- `SILVER.pro`
- `PLATIN.pro`
- `COPPER-US.pro / XCUUSD`

### Dlaczego akurat te cztery

#### 1. GOLD.pro

To jest absolutny rdzen rodziny.

- najlepsza lokalna kompatybilnosc,
- najdojrzalsze heurystyki w starym systemie,
- najnizszy lokalny spread cap,
- naturalny kandydat na wzorzec metalowy.

#### 2. SILVER.pro

To naturalny drugi metal.

- jest juz obslugiwany,
- ma gotowy alias,
- dobrze domyka precious-metals segment razem ze zlotem,
- ma ten sam rytm godzinowy co zloto.

#### 3. PLATIN.pro

To najlepszy trzeci metal, jesli chcemy rozszerzyc rodzine bez wejscia od razu w najbardziej agresywny instrument.

- jest metalem szlachetnym,
- ma wspolne futuresowe godziny z miedzia i palladem,
- jest spokojniejszy kosztowo niz pallad,
- daje nam pomost miedzy precious metals a metalami bardziej przemyslowymi.

#### 4. COPPER-US.pro / XCUUSD

To najlepszy czwarty metal do pierwszego rolloutu.

- stary system juz go skanuje i uwzglednia w oknach,
- historyczny skan lokalny pokazal sensowne okna dla `COPPER`,
- lokalny spread cap jest lepszy niz dla platyny i palladu,
- daje rodzinie ekspozycje na metal przemyslowy, a nie tylko na precious metals.

## Ktorego metalu nie polecam na start

Na pierwszy rollout nie polecam `PALLAD.pro`.

Nie dlatego, ze jest zly sam w sobie, tylko dlatego, ze:

- ma najwyzszy lokalny spread cap,
- ma najwyzszy local markup burden w starej konfiguracji,
- jest najbardziej agresywny kosztowo z calej piatki,
- najlatwiej bedzie nim popsuc pierwsza rodzine metalowa zanim zbudujemy jej dyscypline.

To bardzo dobry kandydat na:

- `phase 2`
- albo `METALS_HIGH_BETA`

ale nie na pierwsza, podstawowa czworke.

## Czy warunki OANDA sa wystarczajaco podobne, by trzymac to razem

Tak, pod warunkiem ze razem oznacza:

- jedna rodzina nadrzedna `METALS`
- wspolny brokerowy kontrakt kapitalowy,
- wspolny mechanizm kapitana i majtka,
- wspolna hierarchia rodzinna

ale nie:

- identyczne okna,
- identyczne spread capy,
- identyczne filtry wejscia,
- identyczny model zachowania.

Czyli wspolny szkielet tak, identyczna osobowosc nie.

## Co proponuje zrobic dalej

Jesli przejdziemy do wdrozenia, to kolejnosc powinna byc taka:

1. potwierdzic realne nazwy metalowych symboli w MT5 na naszym serwerze,
2. przygotowac nowa rodzine nadrzedna `METALS`,
3. zrobic podzial:
   - `METALS_SPOT_PM`
   - `METALS_FUTURES`
4. najpierw wdrozyc wzorzec `GOLD.pro`,
5. potem `SILVER.pro`,
6. potem `PLATIN.pro`,
7. potem `COPPER-US.pro / XCUUSD`,
8. `PALLAD.pro` zostawic jako etap drugi.

## Zrodla oficjalne

- OANDA Financial Instruments Specification CFDs, valid from `2025-10-20`:
  - https://www.oanda.com/eu-en/sites/default/files/document_files/sif-tms-connect-eng-20.10.2025.pdf
- OANDA Trading Account / MT5 / koszty finansowania:
  - https://www.oanda.com/eu-en/invest/trading-account
- OANDA commodities overview:
  - https://www.oanda.com/eu-en/commodities-cfd

## Zrodla lokalne

- [strategy.json](C:\OANDA_MT5_SYSTEM\CONFIG\strategy.json)
- [safetybot.py](C:\OANDA_MT5_SYSTEM\BIN\safetybot.py)
- [test_symbol_aliases_oanda_mt5_pl.py](C:\OANDA_MT5_SYSTEM\tests\test_symbol_aliases_oanda_mt5_pl.py)
- [SESSION_HANDOFF_2026-02-23_2348.md](C:\OANDA_MT5_SYSTEM\DOCS\SESSION_HANDOFF_2026-02-23_2348.md)

## Najkrotszy wniosek

Tak, mozemy i powinnismy budowac rodzine metali.

Najlepsza pierwsza czworka to:

- `GOLD.pro`
- `SILVER.pro`
- `PLATIN.pro`
- `COPPER-US.pro / XCUUSD`

z `PALLAD.pro` jako trudniejszym, kosztowym metalem na pozniejszy etap.

Najlepsza architektura nie jest plaska. To powinna byc:

- jedna rodzina `METALS`
- z dwoma podrodzinami:
  - `METALS_SPOT_PM`
  - `METALS_FUTURES`
