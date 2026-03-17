# Symbol Differentiation Status

## Cel

Ten dokument opisuje aktualny poziom roznicowania `11` mikro-botow i pokazuje, co juz jest lokalne, a co nadal nadaje sie do wspolnej propagacji.

## Rodziny strategii

### FX_MAIN

- `EURUSD`
- `GBPUSD`
- `USDCAD`
- `USDCHF`

Wspolne cechy:

- okna glownie `8-11` albo `8-12`
- `M5`
- ten sam wspolny flow runtime
- `trend / pullback / breakout` jako dominujacy model

Lokalne roznice:

- `EURUSD` ma `rejection`
- `USDCAD` ma `reversal`
- rozne `EMA`
- rozne progi triggera
- rozny risk i trailing

### FX_ASIA

- `USDJPY`
- `NZDUSD`
- `AUDUSD`

Wspolne cechy:

- okna `0-3` albo `0-5`
- `M5`
- ten sam wspolny flow runtime
- nacisk na spokojniejszy profil ryzyka i ciasniejsze okna

Lokalne roznice:

- `AUDUSD` ma `range`
- `USDJPY` i `NZDUSD` maja etykiety `*_ASIA`
- rozne `EMA`
- rozne `ATR` multipliers i trailing

### FX_CROSS

- `EURJPY`
- `GBPJPY`
- `EURAUD`
- `GBPAUD`

Wspolne cechy:

- okna `7-11` albo `7-12`
- `M5`
- ten sam wspolny flow runtime
- wiekszy nacisk na osobne trailing/risk per symbol

Lokalne roznice:

- `EURAUD` ma `range`
- `GBPJPY` i `EURJPY` sa bardziej trend/pullback
- `GBPAUD` ma mocniejszy trailing i ostrzejszy trigger

## Co jest juz naprawde lokalne

Na ten moment per symbol sa juz rozne:

- `session_profile`
- okna handlu
- `max_spread_points`
- `EMA fast / EMA slow`
- `risk_pct`
- `sl/tp atr multipliers`
- `trail_atr_multiplier`
- `trigger_abs`
- aktywne setupy

## Co nadal jest wspolne

To nadaje sie do dalszej propagacji z jednego wzorca:

- `trade_tf = M5`
- `ATR = 14`
- `RSI = 14`
- nowy bar jako warunek wejscia
- wspolny lifecycle strategii
- wspolny schemat:
  - inicjalizacja indikatorow
  - sygnal
  - risk plan
  - precheck
  - send
  - manage position

## Ocena dojrzalosci

### Zrobione

- wszystkie `11` botow maja lokalne profile i lokalne parametry
- boty sa zroznicowane rodzinnie
- w kodzie widac juz rzeczywiste roznice symbolowe

### Jeszcze niedojrzale

- wspolny `Common Strategy Flow` jest juz czesciowo wyciety, ale nadal nie obejmuje jeszcze wszystkich mozliwych helperow symbolowych
- nadal istnieje lokalne powielenie formuly scoringu i setupow, celowo pozostawione jako geny par
- propagacja zmian wspolnych jest gotowa na poziomie helperow, ale wymaga jeszcze twardszej walidacji polityk symbolowych

## Nastepny techniczny krok

1. Utrzymac zgodnosc `registry` z profilami i wariantami strategii.
2. Zostawic override'y w registry/profilach.
3. Dodac walidator zgodnosci polityk symbolowych.
4. Dopiero wtedy propagowac zmiany z bota wzorcowego na cala rodzine.
