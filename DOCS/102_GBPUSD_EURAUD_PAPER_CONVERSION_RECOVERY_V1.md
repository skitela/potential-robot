# 102 GBPUSD EURAUD Paper Conversion Recovery V1

Data: 2026-03-16

## Cel
Domkniecie dwoch najslabszych miejsc po audycie spokojniejszych symboli:
- `GBPUSD`
- `EURAUD`

Problem nie lezal w martwym rynku. Oba symbole mialy:
- swieze ticki,
- aktywne timery,
- zdrowe polaczenie terminala.

Prawdziwy problem byl dwojaki:
- `GBPUSD` mial zablokowana konwersje papierowa i byl duszony przez `BROKER_PRICE_RATE_LIMIT` jeszcze przed sensowna lekcja,
- `EURAUD` krecil sie wokol ogromnej liczby kandydatow, ale z bardzo mala liczba nowych lekcji paper.

## Zmiany

### 1. Paper bypass dla `BROKER_PRICE_RATE_LIMIT`
W obu mikro-botach:
- `MicroBot_GBPUSD.mq5`
- `MicroBot_EURAUD.mq5`

dodano lekki bypass tylko dla trybu `paper`, gdy `rate_guard` zatrzymuje symbol z powodem:
- `BROKER_PRICE_RATE_LIMIT`

Zamiast twardego zatrzymania:
- symbol przechodzi w `CAUTION`,
- zostawia decyzje `RATE_GUARD / BYPASS`,
- i moze dalej wygenerowac lekcje paper.

Nie dotyka to `live`, ani innych powodow zatrzymania.

### 2. Dodatkowa konwersja paper dla `GBPUSD`
Dodano bardzo waski ratunek dla:
- `SETUP_TREND`
- strona `SELL`
- dobra egzekucja,
- brak zlego spreadu,
- kierunek Renko zgodny `DOWN`,
- score wystarczajaco mocny.

Cel:
- nie zalewac smieciem,
- ale pozwolic `GBPUSD` zamieniac mocniejsze sygnaly trendowe na lekcje paper.

### 3. Dodatkowa konwersja paper dla `EURAUD`
Dodano dwie rzeczy:
- brakujace `PAPER_IGNORE_MIN_LOT_BLOCK`,
- oraz waski ratunek dla `SETUP_RANGE / RANGE`, gdy:
  - score jest wystarczajaco mocny,
  - egzekucja jest dobra,
  - spread nie jest zly,
  - Renko jest dobre.

Cel:
- odetkac symbol, ktory mial ogrom kandydatow i prawie brak nowych lekcji.

## Efekt po wdrozeniu
Po kompilacji `17/17` i restarcie lokalnego MT5:

### GBPUSD
Pojawil sie pierwszy swiezy przebieg po nowej wersji:
- `RATE_GUARD / BYPASS`
- `PAPER_OPEN / OK`

Czyli symbol przestal byc tylko blokowany i zostawil nowa lekcje paper.

### EURAUD
Pojawil sie pierwszy swiezy przebieg po nowej wersji:
- seria `EVALUATED / PAPER_SCORE_GATE`
- czesc nadal zablokowana przez `PORTFOLIO_HEAT_BLOCK`
- ale pojawil sie tez `PAPER_OPEN / OK`

Czyli symbol zaczal wreszcie zamieniac nowe kandydaty na realne lekcje paper.

## Ograniczenia
- `GBPUSD` nadal ma slaba retencje i wymaga dalszej obserwacji, czy nowe lekcje sa wartosciowe, a nie tylko czestsze.
- `EURAUD` nadal ma stary fokus lokalnego agenta na `SETUP_BREAKOUT / BREAKOUT`, mimo ze runtime zaczal juz dawac swieze lekcje `SETUP_RANGE`.
- To oznacza, ze nastepna runda moze wymagac juz nie ratunku paper, tylko przestawienia samego fokusu strojenia.

