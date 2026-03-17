# Rollover Guard Migration From OANDA MT5 System V1

## Cel

Przeniesc do `MAKRO_I_MIKRO_BOT` to, co w starym `OANDA_MT5_SYSTEM` bylo bardzo dojrzale:
- codzienny guard rollover wokol `17:00 America/New_York`
- kwartalne guardy indeksowe
- reczne wydarzenia brokerowe, gdy OANDA rozdziela symbole na rozne dni
- ochrone w warstwie kontrolnej, a nie w goracej sciezce kazdego ticka

## Co bylo w starym systemie

Stary system mial trzy wazne elementy:
- blokade nowych wejsc przed i po codziennym rollover OANDA
- wymuszone zamkniecie pozycji kilka minut przed anchor `17:00 NY`
- dodatkowa logike dla indeksow kwartalnych i wydarzen recznych

Bylo to osadzone na prawdziwych strefach czasu:
- `America/New_York`
- `Europe/Warsaw`
- `Asia/Tokyo`

To wlasnie rozwiazywalo marcowy problem, gdy USA i Europa zmieniaja czas w roznych dniach.

## Co sprawdzono po stronie OANDA

Wiedza zostala porownana z materialami OANDA:
- codzienny rollover jest liczony wokol `17:00` czasu Nowy Jork
- lista rolloverow OANDA dla marca 2026 rozdziela indeksy:
  - `US500` na `18 marca 2026`
  - `DE30` na `19 marca 2026`

Wniosek:
- nowy system nie powinien zamrazac calej domeny `INDICES` jednym topornym ruchem kwartalnym
- guard kwartalny i manualny powinien byc symbolowy

## Co bylo brakujace w nowym systemie

Nowy system mial juz:
- koordynator sesji i kapitalu
- obsluge DST dla okien sesyjnych
- domenowe `runtime_control`

Ale nie mial jeszcze:
- jawnego guardu `17:00 NY`
- symbolowych wydarzen kwartalnych/manualnych
- `force_flatten` prowadzonego wspolnie dla calej floty

## Jak to zostalo osadzone

Implementacja zostala umieszczona w warstwie kontrolnej:
- `TOOLS\\APPLY_SESSION_CAPITAL_COORDINATOR.ps1`

To oznacza:
- obliczenia czasu i rollover dzieja sie poza hot-path
- mikro-boty nie licza same timezone, kwartalow i list brokerowych
- bot dostaje tylko gotowa decyzje w `runtime_control.csv`

## Nowy model ochrony

### Dzienny rollover OANDA

Na poziomie domen:
- blokada nowych wejsc `30 min przed`
- blokada `15 min po`
- `force_flatten` `5 min przed`

Dotyczy:
- `FX`
- `METALS`
- `INDICES`

### Kwartalny rollover indeksow

Na poziomie symboli:
- blokada `45 min przed`
- blokada `30 min po`
- `force_flatten` `10 min przed`

Automatycznie:
- `US500`

Recznie, wedlug listy OANDA dla marca 2026:
- `US500` -> `2026-03-18 17:00 America/New_York`
- `DE30` -> `2026-03-19 17:00 America/New_York`

## Jak boty to respektuja

Nowe pole w stanie:
- `force_flatten`

Nowe zachowanie:
- `MbRuntimeControl` czyta `force_flatten`
- `MbStorage` zapisuje i odtwarza ten stan
- `MbStrategyCommon` zamyka pozycje centralnie, gdy `force_flatten=true`

To daje jeden wspolny most dla calej floty:
- bez kopiowania logiki do `17` ekspertow
- bez zwiekszania latencji na kazdym sygnale

## Dlaczego to jest lepsze od prostej blokady domeny

Bo mamy dwa rozne poziomy:
- dzienny rollover OANDA jest szeroki i moze dotyczyc calego rynku
- kwartalne/manualne rollover indeksow sa precyzyjne i symbolowe

Czyli:
- szeroki guard tam, gdzie brokerowy koszt i chaos sa globalne
- precyzyjny guard tam, gdzie wydarzenie dotyczy konkretnego instrumentu

## Najwazniejszy efekt

Nowy system odziedziczyl ze starego to, co bylo w nim naprawde dojrzale operacyjnie, ale w formie bardziej lekkiej:
- sterowanie w koordynatorze
- wykonanie przez `runtime_control`
- jedno wspolne `force_flatten`
- bez wciskania ciezkiej logiki czasu do kazdego bota
