# Trust Conversion Ratio And Contract Subtypes V1

Data: 2026-03-16

## Cel

Domkniecie warstwy decyzji agenta strojenia w dwoch miejscach:
- `conversion_ratio` staje sie twardym warunkiem zaufania,
- `PAPER_CONVERSION_BLOCKED` i `FOREFIELD_DIRTY` przestaja byc tylko ogolnymi etykietami i dostaja kontraktowe podtypy.

## Co zostalo zmienione

### 1. `conversion_ratio` jako twardy warunek zaufania

Wczesniej brak konwersji paper byl rozpoznawany glownie heurystycznie:
- duzo kandydatow,
- brak nowych lekcji,
- duzo blokad ryzyka.

To zostalo zaostrzone.

Od teraz deckhand wylicza i zapisuje:
- `conversion_ratio`
- `recent_conversion_ratio`
- `min_conversion_ratio`
- `min_conversion_candidates`

Zaufanie nie przechodzi do `TRUSTED`, jezeli:
- liczba kandydatow po `PAPER_SCORE_GATE` przekracza minimalny prog dla rodziny,
- lifetime `conversion_ratio` jest ponizej wymaganego progu,
- a biezaca, najnowsza konwersja nie pokazuje realnej poprawy.

To oznacza, ze:
- pojedynczy `paper_open` nie wystarcza juz do odzyskania zaufania,
- sam ruch w kandydaturach nie wystarcza,
- agent nie stroi lokalnej alfy na pozornej aktywnosci bez sensownej zamiany na lekcje.

### 2. Kontraktowe podtypy `PAPER_CONVERSION_BLOCKED`

Zamiast jednej, szerokiej etykiety deckhand wystawia teraz podtyp przyczyny:
- `PAPER_CONVERSION_BLOCKED_BY_RISK_CONTRACT`
- `PAPER_CONVERSION_BLOCKED_BY_PORTFOLIO_HEAT`
- `PAPER_CONVERSION_BLOCKED_BY_RATE_GUARD`
- `PAPER_CONVERSION_BLOCKED_BY_LOW_RATIO`
- `PAPER_CONVERSION_BLOCKED_BY_UNKNOWN`

Podtyp wybierany jest na podstawie realnych sladow z:
- `candidate_signals.csv`
- `decision_events.csv`

To poprawia epistemologie agenta:
- nie myli juz slabszej konwersji z problemem setupu,
- widzi, czy blokada lezy w ryzyku, heat, rate-guardzie czy po prostu w chronicznie slabym ratio.

### 3. Kontraktowe podtypy `FOREFIELD_DIRTY`

Tak samo zostalo doprecyzowane brudne przedpole:
- `FOREFIELD_DIRTY_BY_OBSERVATION_GAPS`
- `FOREFIELD_DIRTY_BY_CANDIDATE_INVALID`
- `FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_CANDLE`
- `FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_RENKO`
- `FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_HYBRID`
- `FOREFIELD_DIRTY_BY_DIRTY_RATIO`
- `FOREFIELD_DIRTY_BY_UNKNOWN`

Deckhand rozroznia teraz:
- brud wynikajacy z brakow obserwacji,
- brud wynikajacy z niespojnych kandydatow,
- brud typu candle,
- brud typu renko,
- brud mieszany,
- oraz przypadki, gdzie dirty ratio samo w sobie przekracza dopuszczalny kontrakt.

### 4. Logowanie i retencja

Do logow deckhanda i reasoningu dopisane zostaly pola:
- `recent_conversion_ratio`
- `min_conversion_ratio`
- `min_conversion_candidates`
- `max_dirty_ratio`
- liczniki dirty subtype:
  - candle
  - renko
  - hybrid
- liczniki block subtype:
  - risk contract
  - portfolio heat
  - rate guard

To nie zmienia hot-path decyzji wejsciowej. To porzadkuje tylko warstwe oceny materialu do strojenia.

### 5. Agent lokalny zostal przepiety na nowe kontrakty

Lokalny tuning agent nie sprawdza juz tylko:
- `report.reason_code == PAPER_CONVERSION_BLOCKED`
- `report.reason_code == FOREFIELD_DIRTY`

Od teraz korzysta z kontraktowych helperow:
- `MbIsPaperConversionBlockedReason(...)`
- `MbIsForefieldDirtyReason(...)`

To oznacza, ze wszystkie podtypy sa interpretowane spojnie przez:
- deckhanda,
- agenta,
- telemetrie reason domain/class.

## Progi rodzine

W warstwie epistemologii doszly progi rodzinne:
- minimalny `conversion_ratio`
- minimalna liczba kandydatow po `PAPER_SCORE_GATE`
- maksymalny dopuszczalny `dirty_ratio`

Sa one lekkie i jawne. Nie sa zaszyte jako nieczytelna heurystyka w kilku miejscach naraz.

## Wynik techniczny

Po zmianach:
- kompilacja floty: `17/17`
- kompilacja: `0 errors, 0 warnings`
- layout projektu: `ok=true`
- tuning hierarchy: `ok=true`
- symbol policy consistency: `ok=true`

## Ocena

To nie jest nowa alfa.

To jest poprawa dyscypliny epistemicznej:
- mniej falszywego zaufania,
- mniej strojenia na slabej konwersji,
- mniej strojenia na brudnym materiale,
- lepsze rozroznienie przyczyny problemu jeszcze przed ruszeniem parametru.
