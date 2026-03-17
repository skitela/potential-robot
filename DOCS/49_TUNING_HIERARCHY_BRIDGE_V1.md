# Tuning Hierarchy Bridge V1

## Cel

Most hierarchii strojenia spina trzy poziomy:

- lokalne strojenie instrumentu,
- polityke rodziny,
- polityke koordynatora floty.

Wynik tej kompozycji trafia do skutecznej polityki lokalnej bez wchodzenia w hot-path `OnTick`.

## Zasada pracy

- lokalny bot dalej przechowuje swoja surowa polityke strojenia,
- rodzina i koordynator pozostaja warstwami nadrzednymi,
- w cyklu timerowym budowana jest skuteczna polityka lokalna,
- strategia dostaje juz wynik zlozenia lokalnego + rodzinnego + flotowego.

## Zakres V1

V1 wprowadza:

- mape rodzin dla `FX_MAIN`, `FX_ASIA`, `FX_CROSS`,
- blokade nowych lokalnych zmian przy `FAMILY_FREEZE` albo `FREEZE_FLEET`,
- skladanie skutecznych limitow:
  - `confidence_cap`
  - `risk_cap`
  - rodzinny breakout tax
  - rodzinny trend tax
  - rodzinny rejection boost
- zapis skutecznej polityki do:
  - `state/<symbol>/tuning_policy_effective.csv`

## Bezpieczenstwo

- warstwa dziala tylko w serwisie timerowym,
- nie dotyka `OnTick`,
- nie przepisuje kodu strategii,
- nie niszczy lokalnego genotypu,
- nadpisuje tylko przez bezpieczne ograniczenia typu `min` / lagodne podatki.

## Aktualny stan

V1 zostal wpiety produkcyjnie do `EURUSD` jako pierwszy wzorzec runtime.
