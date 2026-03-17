# Telemetry Epistemology Integration And Cleanup V1

Data: 2026-03-16

## Cel

Domkniecie warstwy epistemologii agenta strojenia w runtime tak, aby:
- nowe stany byly widoczne poza samym deckhandem i agentem,
- wspolna telemetria nie psula kompilacji ani hot-path,
- zniknely techniczne ostrzezenia zostawiajace szum w buildzie.

## Zakres zmian

### 1. Integracja nowych stanow z telemetria runtime

Do warstw runtime JSON zostaly podpiete jawne stany epistemiczne:
- `reason_domain`
- `reason_class`
- `trust_state`
- `trust_reason`
- `execution_quality_state`
- `execution_quality_reason_code`
- `cost_pressure_state`
- `cost_pressure_reason_code`

Zmiany weszly do:
- `MQL5/Include/Core/MbExecutionSummaryPlane.mqh`
- `MQL5/Include/Core/MbInformationalPolicyPlane.mqh`
- `MQL5/Include/Core/MbTuningEpistemology.mqh`

W efekcie runtime przestal trzymac epistemologie tylko w logach strojenia. Te same osie sa teraz widoczne rowniez w:
- `execution_summary.json`
- `informational_policy.json`

To poprawia czytelnosc przyczyn, upraszcza audyt i ogranicza ryzyko mylenia problemu sygnalu z problemem wykonania, kosztu, danych lub centrali.

### 2. Odchudzenie wspolnego zapisu JSON

`MbExecutionSummaryPlane.mqh` mial zbyt ciezki pojedynczy `StringFormat`, co rozwalalo wspolna kompilacje.

Naprawa:
- payload zostal rozbity na trzy mniejsze segmenty,
- zachowano ten sam zestaw pol,
- nie dodano zadnych ciezkich runtime helperow,
- nie wprowadzono dodatkowej retencji ani zbednych obliczen.

To jest poprawka techniczna i porzadkowa: mniej ryzyka, zero obejsc, czysty build.

### 3. Doczyszczenie arbitrazu kandydatow

W `MQL5/Include/Core/MbCandidateArbitration.mqh` usuniety zostal stary wzorzec `switch` na `ulong magic`, ktory zostawial ostrzezenie o konwersji.

Naprawa:
- `switch` zostal zastapiony prostym, jawnie typowanym lancuchem porownan `== ...UL`

Efekt:
- brak ostrzezen w kompilacji,
- brak ukrytego castowania,
- prostsza i bezpieczniejsza logika.

### 4. Podpiecie wszystkich mikrobotow do nowych sygnatur telemetrycznych

Wszystkie `17` mikrobotow przekazuja teraz lokalna polityke strojenia do:
- `MbFlushInformationalPolicy(...)`
- `MbFlushExecutionSummary(...)`

To zapewnia spojnosc: runtime telemetria widzi te same stany epistemiczne, na ktorych pracuje lokalny agent i deckhand.

## Weryfikacja

Po zmianach:
- kompilacja floty: `17/17`
- wynik kompilacji: `0 errors, 0 warnings`
- `VALIDATE_PROJECT_LAYOUT.ps1` -> `ok=true`
- `VALIDATE_TUNING_HIERARCHY.ps1` -> `ok=true`
- `VALIDATE_SYMBOL_POLICY_CONSISTENCY.ps1` -> `ok=true`
- `VALIDATE_MT5_SERVER_INSTALL.ps1` -> `ok=true`

## Ocena architektoniczna

Ta runda nie dodaje nowej alfy i nie zmienia logiki wejsc. Jej wartosc polega na:
- zwiekszeniu czytelnosci przyczyny wyniku,
- zmniejszeniu technicznego szumu,
- usunieciu build debt,
- przygotowaniu lepszego gruntu pod dalsze strojenie per symbol.

Najwazniejszy efekt praktyczny:
- agent, deckhand i runtime telemetryczne mowia teraz bardziej jednym jezykiem.
