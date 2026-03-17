# GBPUSD and USDJPY Agent Support v1

## Cel
Powtorzyc chirurgiczne wsparcie agenta strojenia po wzorze `EURUSD`, ale lokalnie i zgodnie z genotypem:
- `GBPUSD` jako bot bardziej trendowo-breakoutowy,
- `USDJPY` jako bot z mocnym komponentem `RANGE`.

## Co pokazaly dane

### GBPUSD
- Ogromna liczba kandydatow `EVALUATED`, ale praktycznie wszystko konczylo sie na `SIZE_BLOCK -> RISK_CONTRACT_BLOCK`.
- Brak nowych `PAPER_OPEN` i `PAPER_CLOSE`, wiec lokalny agent praktycznie nie dostawal swiezych domknietych lekcji.
- Najbardziej brudny material:
  - `SETUP_TREND` w `CHAOS` i `TREND`
  - slaba swieca
  - czesto slaby lub niejednoznaczny Renko
  - niski bucket pewnosci
- Dodatkowo runtime byl zasypywany `BROKER_PRICE_RATE_LIMIT`.

### USDJPY
- Tak samo wystepowal dominujacy `RISK_CONTRACT_BLOCK`, ale wzorzec genotypowy byl inny.
- Najwiecej materialu papierowego przechodzilo przez `SETUP_RANGE`, czesto w `TREND`, `CHAOS` albo nawet `BREAKOUT`, z niska pewnoscia i slaba jakoscia aux.
- To oznaczalo ryzyko zalewania agenta strojenia slaba probka mean-reversion tam, gdzie warunki nie byly mean-reversion.

## Wdrozone poprawki

### Wspolne
- Wylaczono naliczanie pasywnych tickow do `price probe` w paper runtime, zeby nie produkowac falszywych `BROKER_PRICE_RATE_LIMIT`.
- Dodano paperowa podloge minimalnego lota, zeby poprawny kandydat nie umieral tylko dlatego, ze po skali ryzyka lot schodzil do zera.
- Paper gate przestal wskrzeszac sygnaly, ktore twarde filtry strojenia juz uznaly za zbyt slabe.

### GBPUSD
- Zaostrzono paper gate dla slabych trendow i breakoutow:
  - szczegolnie `CHAOS + LOW + POOR candle`
  - jeszcze mocniej dla kombinacji `POOR candle + POOR/UNKNOWN renko`
- Dodano lokalny paperowy fallback minimalnego lota takze wtedy, gdy blokada byla czysto rozmiarowa jeszcze przed krokiem mnoznika.

### USDJPY
- Zaostrzono paper gate dla `SETUP_RANGE`, gdy:
  - rynek byl w `TREND` lub `BREAKOUT`,
  - confidence bylo niskie,
  - candle lub renko byly slabe.
- Utrzymano zgodnosc z aktywnymi filtrami breakoutu i range, zeby paper nie obchodzil tego, co agent juz uznal za toksyczne.

## Efekt po wdrozeniu

### USDJPY
- Po restarcie pojawil sie swiezy `PAPER_OPEN`.
- W `paper_position.csv` jest aktywna pozycja `0.01`.
- To oznacza, ze agent zaczal znow dostawac prawdziwe lekcje domkniete przez paper runtime.

### GBPUSD
- Poprawki sa wdrozone i skompilowane.
- Ostatni stary wzorzec przed swiezym cyklem nadal pokazuje `SETUP_TREND` w `CHAOS` z bardzo slaba jakoscia i zerowym lotem.
- Po ostatnim restarcie potrzeba jeszcze swiezego cyklu runtime, zeby logi zostawily nowy dowod po poprawce. Kod jest juz gotowy, ale dokumentacyjnie uczciwie czeka na potwierdzenie.

## Wniosek
- `USDJPY` zostal realnie odetkany.
- `GBPUSD` dostal potrzebne filtry i odetkanie paperowego lota, ale wymaga jeszcze chwili runtime, zeby zostawic nowy sladowy dowod w logach.
