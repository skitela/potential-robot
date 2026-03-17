# 62. Capital Risk Contract Enforcement V1

## Cel

Ten etap zamienia kontrakt kapitalowy z dokumentu `61` w realna warstwe egzekwowania w runtime.

Najwazniejsza zmiana brzmi prosto:

`paper` i `live` nie sa juz tylko etykietami organizacyjnymi. Od teraz maja osobne, twarde kotwice strat i osobne sufity ryzyka.

## Co zostalo wdrozone

### 1. Wspolny kontrakt runtime

Dodano warstwe:

- `MbCapitalRiskContract.mqh`

Ta warstwa:

- rozroznia `paper` i `live`,
- wystawia immutable progi,
- sluzy tylko do odczytu,
- nie daje agentom mozliwosci podniesienia ryzyka.

### 2. Twarde guardy dziennie i sesyjne

Guard rynku zostal rozszerzony tak, aby:

- w `paper` liczyc strate od `realized_pnl_day/session`,
- w `live` liczyc strate od realnego `equity`,
- pilnowac dodatkowo dziennej straty symbolu.

To usuwa stary problem, w ktorym `paper` mogl krwawic, a guard patrzyl na nienaruszone equity brokera.

### 3. Clamp ryzyka przed sizingiem

Wspolny sizing strategii zostal spiety z kontraktem tak, aby:

- bazowe ryzyko nie moglo przekroczyc kontraktu,
- `soft daily loss` automatycznie scinal ryzyko,
- lokalny model ryzyka nie mogl przebic `paper/live` sufitow.

### 4. Koniec z wzmacnianiem ryzyka przez sygnal ponad kontrakt

Wszystkie mikro-boty dostaly poprawiony etap post-scaling:

- mnoznik sygnalu nie moze juz podbic lota ponad `1.0`,
- jezeli hierarchia strojenia zetnie ryzyko do zera, wejscie jest blokowane,
- minimalna sztuczna podloga `0.25` zostala usunieta.

To jest kluczowe, bo wlasnie tam stary model potrafil omijac duch kontraktu.

### 5. Rodzina i flota dostaly wlasne bezpieczniki strat

Agent rodzinny liczy teraz laczna dzienna strate rodziny.

Po przekroczeniu `family_hard_daily_loss_pct`:

- rodzina przechodzi w freeze,
- skuteczne `confidence_cap` spada do `0.0`,
- skuteczne `risk_cap` spada do `0.0`.

Agent koordynacji liczy analogicznie laczna dzienna strate floty.

Po przekroczeniu `account_hard_daily_loss_pct` w trybie `paper`:

- flota przechodzi w freeze,
- globalne `confidence_cap` spada do `0.0`,
- globalne `risk_cap` spada do `0.0`.

## Co to daje praktycznie

Najwazniejsze skutki sa cztery:

- `paper` przestaje miec iluzje ochrony i zaczyna byc liczony uczciwie na wlasnym PnL,
- `live` zachowuje ostrzejszy kontrakt bez psucia lokalnych genotypow,
- rodzina i flota potrafia teraz same zatrzymac dalsze ryzyko po przekroczeniu progow,
- agent strojenia moze dalej uczyc sie na krwi, ale nie moze jej juz ignorowac ani romantyzowac.

## Aktualizacja: core capital i profit buffer

Warstwa egzekwowania zostala dalej rozwinieta:

- runtime pamieta `capital_core_anchor`,
- zamkniete transakcje buduja `realized_pnl_lifetime`,
- `live` liczy kapital ryzyka od rdzenia plus polowy zysku,
- oraz pilnuje dodatkowej podlogi `CORE_CAPITAL_FLOOR`.

To zamyka stary problem, w ktorym samo rosnace equity moglo zbyt szybko zwiekszac nominalna wartosc ryzyka.

## Czego ten etap jeszcze nie robi

Nie wdrozyliśmy jeszcze pelnego `max_open_risk_pct` na poziomie calego portfela otwartych pozycji.

To zostalo odlozone swiadomie, bo wymaga bardzo precyzyjnego liczenia ryzyka juz otwartych pozycji w skali calej floty i nie powinno byc robione na skroty.

## Jakie pliki zostaly dotkniete

Najwazniejsze miejsca:

- `MbCapitalRiskContract.mqh`
- `MbMarketGuards.mqh`
- `MbStrategyCommon.mqh`
- `MbRuntimeTypes.mqh`
- `MbStorage.mqh`
- `MbTuningFamilyAgent.mqh`
- `MbTuningCoordinator.mqh`
- `MbTuningStorage.mqh`
- wszystkie `MicroBot_*.mq5`

## Walidacja

Po wdrozeniu:

- `11/11` mikro-botow kompiluje sie poprawnie,
- layout projektu przechodzi,
- walidacja hierarchii strojenia przechodzi.
