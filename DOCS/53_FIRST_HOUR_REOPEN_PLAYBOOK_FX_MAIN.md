# 53. First Hour Reopen Playbook FX_MAIN

## Cel

Pierwsza godzina po ponownym otwarciu rynku nie ma byc okresem improwizacji. Jej celem jest zebranie czystego materialu obserwacyjnego i sprawdzenie, jak zachowuje sie nowa hierarchia strojenia po weekendowych zmianach.

## Co zostawiamy nieruszone

W pierwszej godzinie po otwarciu rynku nie robimy:

- zmian w kodzie,
- recznego luzowania lub zaostrzania polityki rodziny `FX_MAIN`,
- recznego ruszania koordynatora floty,
- recznego podnoszenia `risk_cap` albo `confidence_cap`,
- recznego odblokowywania lokalnych agentow tylko dlatego, ze pojawil sie pojedynczy zysk,
- nowych czyszczen logow, jesli nie ma realnego bledu lub korupcji danych.

To okno ma byc spokojne i diagnostyczne.

## Co obserwujemy

W pierwszej godzinie po otwarciu rynku obserwujemy tylko:

- pierwsze nowe rekordy `learning_observations_v2.csv`,
- pierwsze nowe rekordy `candidate_signals.csv`,
- pierwsze `PAPER_OPEN` i `PAPER_CLOSE`,
- przewage `PAPER_TIMEOUT` kontra `PAPER_SL`,
- rozklad `spread_regime`, `execution_regime` i `market_regime`,
- skuteczna polityke `tuning_policy_effective.csv`,
- pojawienie sie lub brak `tuning_actions.csv`,
- to, czy zaczynaja aktywowac sie nowe filtry:
  - wsparcie dla rejection,
  - filtr `Renko` dla breakoutu,
  - filtr swiecy dla trendu.

## Jak interpretujemy pierwsza godzine

Jedna wygrana niczego nie potwierdza. Jedna strata tez nie przekresla kierunku. Szukamy wzorca, nie emocji.

Najwazniejsze pytania w tym oknie sa trzy:

1. Czy nowa polityka rzeczywiscie dociska klasy, ktore weekendowa analiza uznala za toksyczne.
2. Czy dodatnie klasy pozostaja przy zyciu zamiast zostac przypadkiem zduszone.
3. Czy hierarchia strojenia nie generuje szumu, opoznien albo brudnych logow.

## Kiedy wolno interweniowac

Interwencja w pierwszej godzinie jest uzasadniona tylko wtedy, gdy wystapi jedno z ponizszych:

- brak aktualizacji runtime mimo aktywnego rynku,
- uszkodzenie schematu logow lub mieszanie epok danych,
- oczywisty blad polityki skutecznej,
- seria twardych awarii wykonania, ktora wskazuje na problem techniczny, a nie zwykly wynik tradingowy.

Zwykla strata paper nie jest sama w sobie powodem do natychmiastowej zmiany.

## Co bedzie oznaka dobrego startu

Dobry start po otwarciu to nie jest od razu zysk na calej rodzinie. Dobry start to:

- czyste logi,
- logiczne aktualizacje runtime,
- pierwsze transakcje zgodne z nowa polityka,
- mniej wejsc w toksyczne klasy,
- brak regresji latencji,
- brak chaosu decyzyjnego.

## Zakres

Ten playbook dotyczy:

- `EURUSD`
- `GBPUSD`
- `USDCAD`
- `USDCHF`

Pozostale rodziny i instrumenty pozostaja w tym oknie tylko pod obserwacja, bez nowych ingerencji.
