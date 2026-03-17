# EURUSD Auxiliary Intelligence v1

## Cel

Do `EURUSD` dodano pierwszą lekką warstwę odzyskaną ze starego `SafetyBota`, ale już w czystym `MQL5`:
- adapter świec japońskich,
- adapter `Renko`,
- warstwę fuzji pomocniczej nad bazowym sygnałem.

Ta warstwa:
- nie zastępuje głównej strategii,
- nie jest osobnym silnikiem wejścia,
- działa jako filtr i wzmacniacz/osłabiacz zaufania do bazowego sygnału,
- zachowuje niską latencję, bo cięższe obliczenia są wykonywane tylko przy nowym barze.

## Nowe pliki

- `MQL5/Include/Core/MbCandleAdvisory.mqh`
- `MQL5/Include/Core/MbRenkoAdvisory.mqh`
- `MQL5/Include/Core/MbAuxSignalFusion.mqh`

## Filozofia działania

### 1. Główna strategia

EURUSD nadal generuje podstawowy sygnał na bazie:
- EMA fast/slow,
- ATR,
- RSI,
- lokalnych setupów:
  - `SETUP_TREND`
  - `SETUP_PULLBACK`
  - `SETUP_BREAKOUT`
  - `SETUP_REJECTION`

### 2. Warstwa kontekstowa

Następnie działa istniejąca już warstwa:
- `market_regime`
- `spread_regime`
- `execution_regime`
- `confidence_score`
- `risk_multiplier`

### 3. Adapter świec japońskich

Adapter świec ocenia ostatnie bary i buduje advisory:
- `BULLISH_ENGULFING`
- `BEARISH_ENGULFING`
- `BULLISH_PIN_REJECTION`
- `BEARISH_PIN_REJECTION`
- `BULLISH_BODY_MOMENTUM`
- `BEARISH_BODY_MOMENTUM`

Wynik:
- `candle_bias`
- `candle_quality_grade`
- `candle_score`

### 4. Adapter Renko

Adapter `Renko` działa lekko na ograniczonym odczycie ticków `CopyTicks()`.

Nie tworzy osobnego wykresu `Renko` ani `custom symbol` jako runtime główny.
Zamiast tego:
- buduje uproszczone cegły `Renko` z ostatnich ticków,
- mierzy kierunek,
- długość sekwencji,
- wykrywa odwrócenie,
- wylicza advisory:
  - `renko_bias`
  - `renko_quality_grade`
  - `renko_score`
  - `renko_run_length`
  - `renko_reversal_flag`

### 5. Fuzja

Warstwa `MbAuxSignalFusion`:
- wzmacnia sygnał, jeśli świeca i `Renko` go wspierają,
- osłabia sygnał, jeśli są w konflikcie,
- w mocnym podwójnym konflikcie może zablokować wejście.

Nie nadpisuje lokalnej strategii. Działa wyłącznie jako druga warstwa decyzji.

## Wpływ na runtime

Warstwa została wdrożona tylko do `EURUSD`.

Po wdrożeniu do runtime trafiają dodatkowe pola:
- `candle_bias`
- `candle_quality_grade`
- `candle_score`
- `renko_bias`
- `renko_quality_grade`
- `renko_score`
- `renko_run_length`
- `renko_reversal_flag`

Są one zapisywane do:
- `informational_policy.json`
- `execution_summary.json`
- `paper_position.csv`
- `learning_observations.csv` dla nowych zamknięć

## Rola w uczeniu

Nowe zamknięcia `paper/live` mogą już być opisywane nie tylko przez:
- `setup_type`
- `market_regime`
- `spread_regime`
- `execution_regime`

ale też przez:
- kontekst świecowy,
- kontekst `Renko`.

To jest pierwszy krok do bardziej inteligentnego uczenia kontekstowego.

## Dlaczego to jest lekkie

- adapter świec działa tylko na ostatnich barach,
- adapter `Renko` korzysta z limitowanego odczytu ticków,
- całość działa w praktyce tylko wtedy, gdy strategia przejdzie `new bar gate`,
- nie buduje nowego ciężkiego mostu ani zewnętrznego procesu.

## Następny krok

Jeśli `EURUSD` zbierze poprawne nowe obserwacje po tej zmianie, kolejny etap to:
- pamięć podobnych przypadków `setup + regime + candle + renko`,
- a potem ostrożne rozlanie tej warstwy na rodzinę `FX_MAIN`.

## Regulacja po audycie 2026-03-13

Po pierwszym audycie spójnosci `EURUSD`:
- wydzielono czystszy plik uczenia:
  - `learning_observations_v2.csv`
- ograniczono spam powtarzalnych wpisow runtime w `decision_events.csv`
- dodano jawny slad warstwy pomocniczej:
  - faza `AUX`
  - werdykty `SUPPORT / CAUTION / BLOCK`

## Dopiecie sciezki uczenia 2026-03-13

Po kolejnym audycie i obserwacji runtime:
- znaleziono blad mechaniczny w paper close:
  - stan pozycji paper byl resetowany przed skopiowaniem do rekordu uczenia
- poprawiono `MbPaperMaybeClosePosition(...)`, tak aby przekazywal zamykany stan do warstwy uczacej
- `EURUSD` zostal przepiety na nowa wersje tej funkcji
- po poprawce `learning_observations_v2.csv` zaczal zapisywac poprawny kontekst, np.:
  - `SETUP_TREND`
  - `CHAOS`
  - `GOOD`
  - `GOOD`
- pozostawiono nowe warstwy tylko na `EURUSD`; nie rozlano ich jeszcze na reszte par
- dodatkowo przycieto halas `AUX`, aby kolejne obserwacje byly bardziej czytelne

## Twardnienie przeciw nawrotom 2026-03-13

Po nastepnej rundzie diagnostycznej wdrozono dodatkowe zabezpieczenia przeciw nawrotom szumu:
- neutralny wpis `AUX_INCONCLUSIVE` nie jest juz logowany
- `AUX_MIXED` nie trafia do logu przy slabej wartosci sygnalu bazowego
- `POSITION_ALREADY_OPEN` jest raportowane rzadziej, zeby nie zaslanialo realnych problemow
- bypassy `PAPER_IGNORE_OUTSIDE_TRADE_WINDOW` i `PAPER_IGNORE_TRADE_DISABLED` dostaly dluzszy throttle

W osobnym pomiarze tylko dla `EURUSD` uzyskano:
- srednia latencje `0.0126 ms`
- maksimum `1.095 ms`

To potwierdza, ze kolejne porzadki w warstwie `AUX` i logowaniu nie wprowadzily regresji szybkosci.

## Delikatne strojenie bucketowe 2026-03-13

Po kolejnej obserwacji bucketow `EURUSD`:
- `SETUP_BREAKOUT` pozostawal globalnie najslabszym bucketem,
- `SETUP_REJECTION` w `RANGE` pozostawal najzdrowszym bucketem.

W odpowiedzi wdrozono bardzo lekkie strojenie:
- globalny, niewielki "podatek" dla `SETUP_BREAKOUT`,
- dodatkowe zaostrzenie breakoutow w `CHAOS`, `RANGE` i przy `AUX_CONFLICT_CAUTION`,
- delikatna premia dla `SETUP_REJECTION` w `RANGE`.

Ta zmiana:
- zostala wdrozona tylko do `EURUSD`,
- zostala skompilowana i przepchnieta do aktywnego terminala,
- nie jest jeszcze kandydatem do rozlania na `FX_MAIN`,
- wymaga swiezego, pelnego cyklu paper po restarcie, zanim uznamy jej efekt za potwierdzony w danych runtime.
