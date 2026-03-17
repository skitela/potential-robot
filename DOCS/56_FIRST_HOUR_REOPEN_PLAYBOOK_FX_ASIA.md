# 56. First Hour Reopen Playbook FX_ASIA

## Cel

Pierwsza godzina po otwarciu rynku dla `FX_ASIA` ma sluzyc ocenie, czy rodzina zachowuje nowa dyscypline i czy lokalni kapitanowie nie wracaja od razu do najbardziej toksycznych klas wejsc.

To nie jest godzina odwagi. To jest godzina potwierdzania, czy weekendowe wnioski trafily w prawde rynku.

## Co zostawiamy nieruszone

W pierwszej godzinie po otwarciu rynku nie robimy:

- zmian w kodzie,
- recznego luzowania polityki rodziny `FX_ASIA`,
- recznego ruszania koordynatora floty,
- recznego podnoszenia `risk_cap` albo `confidence_cap`,
- recznego odblokowywania `NZDUSD` po pojedynczym sygnale,
- nowych porzadkow runtime, jesli nie ma realnej korupcji danych.

## Co obserwujemy

W pierwszej godzinie po otwarciu rynku obserwujemy:

- pierwsze nowe rekordy `learning_observations_v2.csv`,
- pierwsze `candidate_signals.csv`,
- pierwsze `PAPER_OPEN` i `PAPER_CLOSE`,
- przewage `PAPER_TIMEOUT` kontra `PAPER_SL`,
- rozklad `spread_regime`, `execution_regime` i `market_regime`,
- skuteczna polityke `tuning_policy_effective.csv`,
- to, czy aktywuja sie nowe filtry:
  - `Renko` dla breakout,
  - swieca dla trendu,
  - ewentualne przyszle range-specific filtry,
- czy `NZDUSD` pozostaje w uczciwym trybie obserwacyjnym zamiast dostac zbyt szybkie strojenie.

## Jak interpretujemy pierwsza godzine

`USDJPY` ma pokazac przede wszystkim mniej toksycznego breakoutu.

`AUDUSD` ma pokazac mniej slepego range bez jakosci. Jesli nadal bedzie krwawil, bedzie to sygnal, ze kolejny jezyk strojenia musi wejsc juz w filtry specyficzne dla range.

`NZDUSD` nie musi niczego udowadniac przez pierwsza godzine. Dla tej pary dobrym wynikiem jest brak nerwowego strojenia przy nadal malej probce.

## Kiedy wolno interweniowac

Interwencja w pierwszej godzinie jest uzasadniona tylko wtedy, gdy wystapi jedno z ponizszych:

- brak aktualizacji runtime mimo aktywnego rynku,
- korupcja schematu `candidate_signals.csv` albo `learning_observations_v2.csv`,
- oczywisty blad skutecznej polityki strojenia,
- techniczna seria awarii execution, ktora nie jest zwykla strata tradingowa.

## Co bedzie oznaka dobrego startu

Dobry start dla `FX_ASIA` to:

- czyste logi,
- sensowny przeplyw kandydatow,
- mniej wejsc w toksyczne klasy,
- brak regresji latencji,
- brak agresywnego strojenia przy niskiej probce,
- pierwsze sygnaly, ze rodzina uczy sie dyscypliny zamiast tylko zaciskac wszystko na slepo.

## Zakres

Ten playbook dotyczy:

- `USDJPY`
- `AUDUSD`
- `NZDUSD`
