# 69. Core Capital And Profit Buffer V1

## Cel

Ten etap porzadkuje bardzo wazne rozroznienie:

- kapital rdzeniowy,
- skumulowany zysk,
- kapital ryzyka,
- oraz prog, przy ktorym `live` ma przestac zachowywac sie jak system rosnacy i wrocic do dyscypliny startowej.

W praktyce nie chcemy liczyc ryzyka `live` od calego chwilowego equity. To za szybko rozluznia system po serii dobrych dni albo po chwilowym plusie.

## Trzy warstwy kapitalu

### 1. Kapital rdzeniowy

To jest kapital poczatkowy, od ktorego zaczynamy prace.

Przyklad:

- `1000 PLN`

To jest konstytucja kapitalowa systemu.

### 2. Bufor zysku

To jest dodatni, zrealizowany wynik ponad rdzen.

Przyklad:

- rdzen `1000`
- laczny zrealizowany wynik `+200`
- bufor zysku `200`

### 3. Kapital ryzyka

To nie jest cale equity.

Dla `live` przyjmujemy:

- `risk_base = core_capital + 0.5 * profit_buffer`

Czyli:

- rdzen `1000`
- bufor `200`
- kapital ryzyka `1100`

Nie `1200`.

To daje oddech po wzroscie rachunku, ale nie pozwala systemowi od razu rozpędzac ryzyka 1:1 wraz z rachunkiem.

## Dlaczego to jest lepsze

Ten model robi trzy rzeczy naraz:

- chroni realny, wplacony kapital,
- pozwala systemowi oddychac po zyskach,
- nie nagradza zbyt szybko pojedynczej dobrej serii zbyt duzym wzrostem ryzyka.

## Luzowanie dziennych limitow

Przy `live` dopuszczamy tylko ograniczone luzowanie, zalezne od zrealizowanego bufora zysku.

Model jest schodkowy:

- do `10%` bufora ponad rdzen: brak luzowania,
- od `10%` do `25%`: dojscie maksymalnie do `1.25x` bazowego limitu dziennego i sesyjnego,
- od `25%` do `50%`: dojscie maksymalnie do `1.50x`,
- powyzej `50%`: dalszego luzowania juz nie ma.

To oznacza:

- system moze oddychac bardziej swobodnie po realnie wypracowanej nadwyzce,
- ale nie dostaje nieograniczonego prawa do glebszego obsuniecia.

## Twarda podloga rdzenia

`live` dostaje dodatkowy bezpiecznik:

- jezeli equity spadnie do kapitalu rdzeniowego,
- system uznaje to za naruszenie podlogi `CORE_CAPITAL_FLOOR`.

To nie jest jeszcze pelna logika rekonwalescencji i powrotu do `paper`.
To jest pierwszy, twardy sygnal:

- przestalismy grac nadwyzka,
- wracamy do granicy kapitalu bazowego,
- dalsze ryzyko musi zostac zatrzymane.

## Co zostalo wdrozone

### Runtime state

Dodano nowe pola:

- `realized_pnl_lifetime`
- `capital_core_anchor`
- `effective_profit_buffer`
- `effective_risk_base`
- `effective_loss_allowance_multiplier`

### Closed-deal tracking

Kazde zamkniecie aktualizuje teraz nie tylko `day/session`, ale tez:

- `realized_pnl_lifetime`

### Lot sizing

Sizing przestal liczyc `risk_money` od calego `snapshot.equity`.

Od teraz liczy je od:

- `capital_core_anchor + 0.5 * profit_buffer`

### Market guards

Guardy dostaly:

- detekcje naruszenia `CORE_CAPITAL_FLOOR`,
- dynamiczne luzowanie `soft/hard daily loss` i `hard session loss` dla `live`,
- odswiezanie efektywnego stanu kapitalowego w runtime.

## Czego ten etap jeszcze nie robi

- nie ma jeszcze osobnego, recznego interfejsu do ustawiania `core_capital`,
- nie ma jeszcze rozdzialu `live_bootstrap` vs `live_full`,
- nie ma jeszcze pelnego trybu rekonwalescencji `live -> paper -> probation -> live`.

Czyli:

to jest bardzo wazny krok kapitalowy, ale nie ostatni krok architektury bezpieczenstwa.

## Najwazniejszy wniosek

Od teraz system zaczyna odrozniać:

- to, co jest Twoim kapitalem bazowym,
- od tego, co dopiero zarobil.

I to jest duzy krok w strone dojrzalszego `live`, bo przestajemy traktowac chwilowy wzrost equity jak automatyczne prawo do rownie duzego wzrostu ryzyka.
