# Risk Policy Split

## Cel

Ten dokument ustala, co w architekturze `MAKRO_I_MIKRO_BOT` jest:

- wspolnym ryzykiem forexowym,
- lokalnym ryzykiem symbolowym.

Najwazniejsza zasada:

`nie wyciagamy do Common niczego, co wydluza hot-path albo rozmywa lokalne geny pary`

## Wniosek ze wzorca `EURUSD`

Analiza wzorcowego `EURUSD` pokazuje dwa rozne poziomy ryzyka:

1. `hard runtime protection`
2. `local trade risk model`

To nie sa te same rzeczy.

## Co jest wspolne

Do `Common` wolno trzymac tylko ryzyka i veto, ktore:

- sa identyczne logicznie dla wszystkich par,
- nie wymagaja symbolowego edge,
- nie wydluzaja decyzyjnego hot-path przez centralizacje.

To obejmuje:

- `trade permissions`
- `kill-switch`
- `margin guard`
- `loss caps`
- `spread cap / spread caution`
- `tick freshness`
- `cache freshness`
- `entry cooldown`
- `close_only / halt`
- wspolny schemat `OrderCheck` i execution precheck
- wspolny schemat budowy risk planu

To sa `hard guards`.

## Co musi zostac lokalne

W mikro-bocie maja zostac wszystkie parametry i decyzje, ktore tworza lokalny styl handlu symbolu:

- `risk_pct_base`
- `risk_pct_min`
- `risk_pct_max`
- `execution_floor`
- `execution_decay`
- `ATR SL/TP multipliers`
- `SL/TP minimum points`
- `trail multiplier`
- lokalna reakcja na `execution_pressure`
- lokalne progi `ready/caution trigger`
- lokalne setupy i scoring

To sa `symbol genes`.

## Zasada latencji

Poniewaz celem nadrzednym jest:

- minimalna latencja,
- ochrona kapitalu,
- maksymalizacja zysku netto,

to model ryzyka wejscia ma pozostac:

- lokalny,
- w pamieci bota,
- bez dodatkowego lookupu do centralnego runtime ownera,
- bez zewnetrznego brokera decyzji.

`Common` ma dostarczac helper, nie autorytet.

## Jak to wyglada teraz

Aktualny podzial jest zgodny z ta zasada:

- `MbMarketGuards` i runtime guardy w `Core` robia wspolne veto
- `MbStrategyCommon` daje wspolny helper do liczenia i budowy planu ryzyka
- lokalne strategie nadal przechowuja swoje:
  - modele ryzyka
  - mnozniki
  - minima
  - trailing

## Decyzja projektowa

Nie przenosimy `risk modelu symbolu` do centralnego `Core`.

Przenosimy tylko:

- wspolne kontrakty,
- wspolny schemat,
- wspolne helpery obliczeniowe.

Kazda para zachowuje swoj lokalny risk profile.

## Konsekwencja dla dalszego rozwoju

Przy dalszym refaktorze pytanie kontrolne brzmi:

`czy ta zmiana dotyczy wspolnej ochrony kapitalu, czy lokalnej osobowosci ryzyka symbolu?`

Jesli dotyczy lokalnej osobowosci ryzyka symbolu:

- zostaje w mikro-bocie

Jesli dotyczy wspolnego veto i ochrony runtime:

- moze trafic do `Common`
