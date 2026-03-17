# FX MAIN Tuning Bridge Rollout V1

## Cel

Rozszerzyc most strojenia `lokalny -> rodzinny -> flotowy` z wzorcowego `EURUSD` na pozostale dojrzale pary rodziny `FX_MAIN`:

- `GBPUSD`
- `USDCAD`
- `USDCHF`

## Zakres

Rollout V1 obejmuje:

- dodanie warstwy polityki strojenia do strategii lokalnych,
- dodanie skutecznej polityki lokalnej `tuning_policy_effective.csv`,
- uruchomienie serwisu strojenia na `OnTimer`,
- podpiecie blokad `FAMILY_FREEZE` i `FREEZE_FLEET`,
- zapis lokalnego stanu strojenia i sygnalow deckhanda.

## Zasada bezpieczenstwa

- nie zmieniamy hot-path `OnTick`,
- nie przepisujemy genotypu danej pary,
- overlay strojenia dziala tylko przez lagodne ograniczenia i podatki,
- lokalne zmiany moga zostac zablokowane przez rodzine albo koordynatora floty.

## Efekt V1

Po rolloucie trzy pary `FX_MAIN`:

- laduja skuteczna polityke strojenia przy starcie,
- odswiezaja ja w cyklu timerowym,
- zapisują surowa polityke lokalna osobno od polityki skutecznej,
- dziedzicza ograniczenia rodziny i floty bez bezposredniego dotykania logiki execution.

## Aktualny stan

- `GBPUSD`, `USDCAD` i `USDCHF` maja juz aktywny most strojenia,
- surowa polityka lokalna pozostaje neutralna na starcie,
- skuteczna polityka pokazuje juz nalozone limity rodziny `FX_MAIN` i koordynatora,
- deckhand pracuje i zapisuje stan danych,
- lokalne `tuning_actions.csv` moga jeszcze nie powstawac, jesli hierarchia utrzymuje `FREEZE`.
