# REVIEW DELTA FIXES - CAUSE SEMANTICS V1

## Cel

Domkniecie semantycznych luk wskazanych w zewnetrznej recenzji bez przebudowy architektury:
- poprawna klasyfikacja `PAPER_CONVERSION_BLOCKED`,
- aktywne wykorzystanie `experiment_baseline_*`,
- spojnosc `experiment_cause_*`,
- dokladniejsza pamiec fiaska dla `avoid_repeat`,
- bogatszy zapis `tuning_experiments.csv`,
- jawna jakosc / confidence rollback cause w raporcie runtime.

## Zmiany w kodzie

### 1. Kontrakt przyczyny eksperymentu

W `MbTuningLocalAgent.mqh`:
- `PAPER_CONVERSION_BLOCKED` jest rozpoznawane przed ogolnym fallbackiem `trust_state != TRUSTED`,
- `FOREFIELD_DIRTY` jest rozpoznawane jawnie przed fallbackiem trust,
- `experiment_cause_code` bierze sie teraz z tej samej osi co `experiment_cause_domain` i `experiment_cause_class`, czyli z `report.normalized_reason`.

### 2. Baseline nie jest juz tylko retencja

Dodano aktywne wykorzystanie `experiment_baseline_trust_state`, `experiment_baseline_execution_quality_state` i `experiment_baseline_cost_pressure_state`:
- `ACCEPT` wymaga judgeable baseline,
- review potrafi oznaczyc `EXPERIMENT_BASELINE_NOT_JUDGEABLE`,
- rollback potrafi zakonczzyc eksperyment jako nieosadzalny, zamiast wciskac go sztucznie do domeny `SIGNAL`.

### 3. Pamiec fiaska

W `MbTuningTypes.mqh` i `MbTuningStorage.mqh` rozszerzono lokalna polityke o:
- `last_failed_cause_domain`,
- `last_failed_cause_code`.

`avoid_repeat` porownuje teraz:
- `action_code`,
- `focus_setup_type`,
- `focus_market_regime`,
- `cause_domain`,
- `cause_class`,
- `cause_code`.

To uszczelnia blokade powrotu do swiezo obalonej sciezki.

### 4. Retencja eksperymentu

`tuning_experiments.csv` zapisuje teraz dodatkowo:
- `execution_quality_reason_code`,
- `cost_pressure_reason_code`.

To pozwala raportowi runtime uzywac precyzyjniejszego fallbacku dla `EXECUTION` i `COST`.

### 5. Raport runtime rollback cause

W `GENERATE_TUNING_ROLLBACK_CAUSE_REPORT.ps1`:
- dodano `rollback_cause_confidence`,
- raport rozroznia juz:
  - `HIGH` dla `failure_reason`,
  - `MEDIUM` dla `review_reason` i `report_reason`,
  - `LOW` dla fallbackow po stanie,
  - `INFERRED_LEGACY` dla starych rollbackow.

## Wdrozenie operacyjne

Po zmianach wykonano:
- pelna kompilacje floty `17/17`,
- walidacje layoutu, hierarchii i spojnosc symbol policy,
- eksport i instalacje pakietu MT5,
- reset aktywnego schematu `tuning_experiments.csv`,
- restart terminala MT5.

## Stan dowodowy po wdrozeniu

### Potwierdzone

- kod kompiluje sie czysto,
- walidacje przechodza,
- terminal zaladowal wszystkie `17` mikrobotow po restarcie,
- raport runtime ma juz jawne pole confidence,
- reset schematu odcial aktywne `tuning_experiments.csv` do archiwum.

### Jeszcze niepotwierdzone swiezym runtime tego buildu

Po resecie nie pojawil sie jeszcze nowy aktywny `tuning_experiments.csv`.

To oznacza, ze:
- nie ma jeszcze swiezego rollbacku nowego buildu,
- nie ma jeszcze runtime proof, ze `PAPER_CONVERSION_BLOCKED` po tej konkretnej poprawce wpada juz do `RISK / CONTRACT` zamiast do `DATA / TRUST`.

Obecny raport `latest` zawiera:
- rollbacki `legacy_v1` z confidence `INFERRED_LEGACY`,
- wczesniejsze rollbacki `cause_v2` z archiwum.

Nie nalezy traktowac tych archiwalnych rekordow jako dowodu przeciw obecnej poprawce.

## Zakres delta

To nie jest redesign.

To jest domkniecie szesciu punktow semantycznych z recenzji:
1. kolejnosc dla `PAPER_CONVERSION_BLOCKED`,
2. aktywne uzycie baseline,
3. spojnosc `experiment_cause_code`,
4. dokladniejsze `avoid_repeat`,
5. bogatsze `tuning_experiments.csv`,
6. confidence dla rollback cause runtime.
