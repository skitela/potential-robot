# 59. First Hour Reopen Playbook FX_CROSS

## Cel

Pierwsza godzina po otwarciu rynku dla `FX_CROSS` ma sluzyc sprawdzeniu, czy najtrudniejsza rodzina zaczyna zachowywac sie czytelniej po wdrozeniu hierarchii strojenia i czy nie wraca od razu do najbardziej toksycznych klas wejsc.

To nie jest godzina odwagi. To jest godzina dyscypliny i potwierdzenia, czy crossy nie rozchodza sie zbyt szybko we wlasne skrajne zachowania.

## Co zostawiamy nieruszone

W pierwszej godzinie po otwarciu rynku nie robimy:

- zmian w kodzie,
- recznego luzowania polityki rodziny `FX_CROSS`,
- recznego ruszania koordynatora floty,
- recznego podnoszenia `risk_cap` albo `confidence_cap`,
- recznego wzmacniania `SETUP_RANGE`,
- nowych schema resetow journali, jesli nie ma realnej korupcji danych.

## Co obserwujemy

W pierwszej godzinie po otwarciu rynku obserwujemy:

- pierwsze nowe rekordy `candidate_signals.csv`,
- pierwsze nowe rekordy `learning_observations_v2.csv`,
- pierwsze `PAPER_OPEN` i `PAPER_CLOSE`,
- przewage `PAPER_TIMEOUT` kontra `PAPER_SL`,
- rozklad `spread_regime`, `execution_regime` i `market_regime`,
- skuteczna polityke `tuning_policy_effective.csv`,
- to, czy lokalne `LOW_SAMPLE` zaczyna schodzic do bardziej wiarygodnego stanu,
- to, czy `GBPJPY` znow wpada w `SETUP_RANGE/CHAOS`,
- czy `EURJPY`, `EURAUD` i `GBPAUD` zaczynaja w ogole dostarczac nowy material zamiast tylko stac w ciszy.

## Jak interpretujemy pierwsza godzine

Jedna transakcja niczego nie rozstrzyga. W `FX_CROSS` szukamy przede wszystkim:

1. czy `GBPJPY` dalej ciagnie strate przez `SETUP_RANGE/CHAOS`,
2. czy pozostale symbole zaczynaja budowac probke bez natychmiastowej toksycznosci,
3. czy hierarchia strojenia pozostaje spokojna i nie generuje brudu w logach.

## Kiedy wolno interweniowac

Interwencja w pierwszej godzinie jest uzasadniona tylko wtedy, gdy wystapi jedno z ponizszych:

- brak aktualizacji runtime mimo aktywnego rynku,
- korupcja schematu `candidate_signals.csv` albo `learning_observations_v2.csv`,
- oczywisty blad skutecznej polityki strojenia,
- seria twardych awarii execution wskazujaca na problem techniczny, a nie zwykla strate tradingowa.

## Co bedzie oznaka dobrego startu

Dobry start dla `FX_CROSS` to:

- czyste logi,
- sensowny przeplyw kandydatow,
- brak natychmiastowego powrotu do `SETUP_RANGE/CHAOS` jako dominujacej rany,
- brak regresji latencji,
- brak agresywnego lokalnego strojenia przy nadal malej probce,
- pierwsze sygnaly, ze najtrudniejsza rodzina daje sie mierzyc i porzadkowac.

## Zakres

Ten playbook dotyczy:

- `EURJPY`
- `GBPJPY`
- `EURAUD`
- `GBPAUD`
