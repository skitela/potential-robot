# 106 Epistemology Layer Contracts V1

## Cel

Domkniecie warstwy epistemologii agenta strojenia bez przebudowy calej architektury:

- jawne kontrakty `trust_state`, `execution_quality`, `cost_pressure`
- normalizacja przyczyny do `reason_domain / reason_class / reason_code`
- nowy status `CENTRAL_STATE_STALE`
- bounded adaptation jako jawny kontrakt rodzinny

## Zakres zmian

### 1. Typy i retencja

Dodano lekkie typy:

- `MbReasonTriple`
- `MbTrustState`
- `MbExecutionQualityState`
- `MbCostPressureState`
- `MbTuningAdaptationContract`

Rozszerzono:

- `MbTuningLocalPolicy`
- `MbTuningDeckhandReport`

Nowe pola lokalnej polityki przechowuja m.in.:

- `trust_reason_domain`
- `trust_reason_class`
- `last_trust_state`
- `last_execution_quality_state`
- `last_cost_pressure_state`
- `adaptation_window_started_at`
- `adaptation_changes_in_window`
- `experiment_cause_class`
- `last_failed_cause_class`

### 2. Warstwa epistemologii

Dodano nowy modul:

- `MbTuningEpistemology.mqh`

Modul odpowiada za:

- mapowanie surowych powodow na `reason_domain / reason_class / reason_code`
- ocene `execution_quality`
- ocene `cost_pressure`
- wykrywanie `CENTRAL_STATE_STALE`
- rodzinny kontrakt bounded adaptation

### 3. Deckhand

Deckhand dostal nowe obowiazki:

- wylicza `execution_quality`
- wylicza `cost_pressure`
- wykrywa `CENTRAL_STATE_STALE`
- sklada z tego jawny `trust_state`
- zapisuje znormalizowany powod oraz nowe metryki do logu deckhanda

Nowa logika nie pozwala juz traktowac starego stanu centrali jako twardej prawdy.

### 4. Lokalny agent strojenia

Agent dostal twarda bramke decyzyjna:

- strojenie tylko gdy `trust_state == TRUSTED`
- strojenie tylko gdy `execution_quality != BAD`
- strojenie tylko gdy `cost_pressure != NON_REPRESENTATIVE`
- strojenie tylko po minimalnej liczbie domknietych lekcji
- strojenie tylko po minimalnej liczbie czystych review
- strojenie z limitem zmian w oknie

Dodano tez:

- bounded step dla taxow, boostow, capow i confidence floor
- `cause_class` do eksperymentu i rollbacku
- blokade powrotu do fiaska po `action + setup + regime + cause_class`

### 5. Flota mikrobotow

Wszystkie 17 mikrobotow przekazuje teraz do deckhanda biezacy `MbMarketSnapshot`, aby:

- ocena wykonania nie byla slepa
- ocena kosztu nie byla oparta tylko na historii
- statusy epistemologiczne mialy dostep do aktualnego obrazu rynku

## Zmienione pliki

- `MQL5/Include/Core/MbTuningTypes.mqh`
- `MQL5/Include/Core/MbTuningStorage.mqh`
- `MQL5/Include/Core/MbTuningDeckhand.mqh`
- `MQL5/Include/Core/MbTuningLocalAgent.mqh`
- `MQL5/Include/Core/MbTuningEpistemology.mqh`
- `MQL5/Experts/MicroBots/*.mq5` w miejscu wywolania `MbRunTuningDeckhand(...)`

## Wazne ograniczenia tej wersji

To jest wersja `V1`, czyli domkniecie kontraktu, nie finalna doskonalosc modelu.

Swiadomie zostawiono na kolejny etap:

- rozszerzenie `reason_domain / reason_class / reason_code` na wszystkie raw reason codes calego runtime
- podpiecie nowych stanow bezposrednio do `execution_summary.json` i `informational_policy.json`
- bardziej precyzyjne, per-symbol benchmarki `cost_pressure`
- per-parameter override bounded adaptation dla pojedynczych symboli

## Oczekiwany efekt

Najwazniejszy efekt tej rundy nie polega na zwiekszeniu liczby trade'ow.

Oczekiwany efekt to:

- mniej falszywych zmian parametrow
- mniej strojenia na zlym materiale
- mniej mylenia sygnalu z wykonaniem, kosztem, danymi i centrala
- wyzsza jakosc lesson loop
- lepsza baza pod dalsze, chirurgiczne strojenie mikrobotow
