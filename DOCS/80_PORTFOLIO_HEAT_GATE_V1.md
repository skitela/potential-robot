# Portfolio Heat Gate v1

## Cel

Domknac ochronę portfelową po wdrożeniu arbitrazu kandydatow `TOP-1`.

Nowa zasada:

- nawet jesli kandydat wygra lokalny arbitraz rodziny
- nie dostaje jeszcze automatycznie prawa do wejscia
- najpierw sprawdzamy, czy po dodaniu jego planowanego ryzyka cala flota nie przekroczy `max_open_risk_pct`

## Dlaczego ten krok byl potrzebny

Sam arbitraz kandydatow ogranicza liczbe slabszych wejsc, ale nie rozwiazuje jeszcze jednego ryzyka:

- zwyciezca rodziny moze byc dobry lokalnie
- a jednoczesnie moze wejsc w momencie, gdy portfel ma juz za duzo otwartego ryzyka

To jest inny problem niz jakosc sygnalu. To jest problem temperatury calego organizmu.

## Jak dziala `v1`

Mechanizm jest swiadomie lekki:

- dla `live` liczy otwarte ryzyko tylko dla pozycji naszej floty
- dla `paper` liczy otwarte ryzyko na podstawie aktywnych papierowych pozycji calej floty
- korzysta z juz istniejacego kontraktu kapitalowego i `risk_base`
- blokuje wejscie tylko wtedy, gdy:
  - `open_risk_money + planned_risk_money` przekroczyloby dozwolony sufit

Sufit:

- bierze sie z `max_open_risk_pct`
- liczony jest od aktualnej bazy ryzyka
- czyli od `core capital + czesc bufora zysku`, zgodnie z istniejacym kontraktem

## Zalozenia bezpieczenstwa

W `v1` mechanizm liczy ryzyko tylko dla naszej floty, nie dla obcych pozycji spoza systemu.

To jest swiadoma decyzja:

- chcemy chronic nasz organizm bez mieszania go z manualnym handlem lub obcymi strategiami
- chcemy zachowac niski narzut runtime

Jesli system nie umie wiarygodnie odtworzyc ryzyka juz otwartej pozycji naszej floty, traktuje to jako stan niepewny i blokuje nowe wejscie:

- `PORTFOLIO_HEAT_UNKNOWN`

Normalna blokada temperatury:

- `PORTFOLIO_HEAT_BLOCK`

## Miejsce w architekturze

Kolejnosc decyzji po tym etapie jest taka:

1. mikro-bot buduje lokalnego kandydata
2. aktywna rodzina wybiera `TOP-1`
3. `portfolio heat gate` sprawdza, czy zwyciezca miesci sie jeszcze w kontrakcie otwartego ryzyka
4. dopiero potem wchodza precheck i wykonanie

To jest bardzo celowe, bo:

- najpierw odrzucamy slabszych zawodnikow
- potem sprawdzamy, czy zwyciezca w ogole ma jeszcze miejsce w portfelu
- dopiero potem dotykamy wejscia rynkowego

## Stan wdrozenia

`v1` jest wdrozone w runtime calej floty:

- wszystkie `17` mikro-botow przekazuja stan runtime do arbitra
- kompilacja floty przechodzi `17/17`
- walidacja layoutu, koordynatora sesji i kontraktu rdzenia przechodzi bez bledow

## Oczekiwany efekt

Po polaczeniu z arbitrazem rodzinnym system powinien:

- wybierac mniej slabszych wejsc
- nie dopuszczac do zbyt goracego portfela
- pozostac lekki, bo nie robi ciezkiej globalnej orkiestracji na kazdym kroku

To jest kolejny krok w strone `live`, w ktorym celem nie jest czestszy handel, tylko madrzejszy handel i lepsza ochrona kapitalu.
