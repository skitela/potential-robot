# 96_EXPERIMENT_CYCLE_RUNTIME_CONFIRMATION_V1

## Cel

Potwierdzic, ze nowy model eksperymentu agenta strojenia nie jest juz tylko kodem, ale pracuje na zywych danych runtime.

## Co zostalo potwierdzone

Na realnych logach `tuning_experiments.csv` pojawily sie wszystkie kluczowe etapy:

- `START`
- `REVIEW_PENDING`
- `ACCEPT`
- `ROLLBACK`

## Potwierdzone przykłady

### EURUSD

Potwierdzony pelny cykl skuteczny:

- `START`
- `REVIEW_PENDING`
- `ACCEPT`

Zmiana `FILTER_TREND_CANDLE` dla `SETUP_TREND / BREAKOUT` dala:

- przyrost probki
- przyrost wygranych
- dodatni przyrost `realized_pnl_lifetime`

Agent utrzymal zmiane.

### US500

Potwierdzony pelny cykl skuteczny:

- `START`
- `REVIEW_PENDING`
- `ACCEPT`

Zmiana `DAMP_INDEX_OPEN` dla `SETUP_BREAKOUT / BREAKOUT` zostala utrzymana po dodatnim materiale paper.

### AUDUSD

Potwierdzony pelny cykl negatywny:

- `START`
- `REVIEW_PENDING`
- `ROLLBACK`

Zmiana `FLOOR_RANGE_CONFIDENCE` dla `SETUP_RANGE / TREND` zostala cofnięta po wzroscie przegranych i ujemnym przyroscie wyniku.

### USDJPY

Potwierdzony pelny cykl negatywny:

- `START`
- `REVIEW_PENDING`
- `ROLLBACK`

Zmiana `FLOOR_RANGE_CONFIDENCE` dla `SETUP_BREAKOUT / TREND` zostala cofnięta po serii stratnych lekcji.

## Dopieta poprawka

Przy pierwszej wersji rollback log cofniecia tracil czesc kontekstu eksperymentu.

To zostalo poprawione:

- agent zachowuje teraz w rollbacku:
  - akcje eksperymentu
  - fokus eksperymentu
  - bazowa probe
  - bazowy wynik

Czyli cofniecie nie jest juz „pustym rollbackiem”, tylko czytelnym zapisem tego, co zostalo obalone.

## Wniosek

Agent strojenia potrafi juz:

- wdrozyc nowy pomysl,
- dac mu czas,
- ocenic skutek,
- utrzymac dobra zmiane,
- cofnac zla zmiane,
- i nie wracac od razu do sciezki, ktora swiezo zakonczyla sie fiaskiem.
