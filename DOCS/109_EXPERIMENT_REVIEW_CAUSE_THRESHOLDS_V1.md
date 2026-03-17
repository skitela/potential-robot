# 109 Experiment Review Cause Thresholds V1

## Cel
Domkniecie warstwy epistemologii eksperymentu tak, aby `review`, `accept` i `rollback`
uwzglednialy osobno:
- `trust_state`
- `execution_quality`
- `cost_pressure`

Chodzi o to, zeby aktywny eksperyment nie rozumial porazki tylko jako "ujemny wynik",
ale jako klase przyczyny:
- sygnal,
- wykonanie,
- koszt,
- dane / trust,
- ograniczenie ryzyka / konwersji,
- stan centralny,
- brak postepu.

## Zmiany
Wdrozone zostaly cztery elementy.

### 1. Pamiec stanu bazowego eksperymentu
Do lokalnej polityki strojenia dodano:
- `experiment_baseline_trust_state`
- `experiment_baseline_execution_quality_state`
- `experiment_baseline_cost_pressure_state`

To pozwala porownywac eksperyment nie tylko po `P/L` i liczbie lekcji, ale tez po tym,
z jakiej jakosci materialu startowal.

### 2. Jawna klasyfikacja przyczyny review
Do polityki dodano:
- `experiment_cause_domain`
- `experiment_cause_class`
- `experiment_cause_code`
- `experiment_last_review_domain`
- `experiment_last_review_class`
- `experiment_last_review_code`
- `experiment_failure_domain`
- `experiment_failure_class`
- `experiment_failure_code`

Agent aktywnego eksperymentu zapisuje teraz:
- przyczyne startu eksperymentu,
- przyczyne ostatniego review,
- przyczyne rollbacku lub fiaska.

### 3. Review reason oparty o osie epistemologiczne
Dodano klasyfikator `MbTuningResolveExperimentReviewReason(...)`, ktory rozroznia:
- `DATA / TRUST / ...`
- `EXECUTION / DEGRADATION / ...`
- `COST / PRESSURE / ...`
- `RISK / CONTRACT / ...`
- `CENTRAL / STALENESS / ...`
- `INFRA / HEALTH / ...`
- `SIGNAL / POSITIVE_OUTCOME / ...`
- `SIGNAL / NEGATIVE_OUTCOME / ...`
- `MODE / OBSERVATION / ...`

Klasyfikator bierze pod uwage:
- stan `trust_state`
- stan `execution_quality`
- stan `cost_pressure`
- delty probki, zamknietych lekcji, `paper_open`
- delte `realized_pnl_lifetime`
- wiek eksperymentu

### 4. Progi `accept / rollback` zalezne od klasy przyczyny
Logika eksperymentu zostala zaostrzona:

- `ACCEPT`
  - wymaga judgeable local alpha:
    - `trust_state == TRUSTED`
    - `execution_quality != BAD`
    - `cost_pressure != NON_REPRESENTATIVE`
  - i dodatniej klasy review z domeny `SIGNAL`

- `ROLLBACK`
  - `RISK / CONTRACT`
    - szybszy rollback przy utrzymanej blokadzie konwersji i braku `paper_open`
  - `DATA / TRUST`
    - rollback po kilku review bez postepu, ale bez obwiniania sygnalu
  - `EXECUTION / DEGRADATION`
    - dluzej czeka na material, potem rollback jako fiasko egzekucyjne
  - `COST / PRESSURE`
    - dluzej czeka, potem rollback jako kosztowo niereprezentatywny
  - `INFRA / HEALTH`, `CENTRAL / STALENESS`
    - rollback po czasie jako fiasko warunkow, nie pomyslu sygnalowego
  - `SIGNAL / NEGATIVE_OUTCOME`
    - rollback jako prawdziwe fiasko lokalnej zmiany
  - `MODE / OBSERVATION / EXPERIMENT_NO_PROGRESS`
    - rollback przy dlugim braku postepu

## Retencja i logi
Rozszerzono:
- `tuning_policy.csv`
- `tuning_policy_effective.csv`
- `tuning_policy_stable.csv`
- `tuning_experiments.csv`

`tuning_experiments.csv` zapisuje teraz:
- stany bazowe eksperymentu,
- przyczyne startu eksperymentu,
- przyczyne ostatniego review,
- przyczyne fiaska,
- dalej rownolegle surowy `trust_reason` i surowy `report_reason`.

## Zmienione pliki
- `MQL5\Include\Core\MbTuningTypes.mqh`
- `MQL5\Include\Core\MbTuningStorage.mqh`
- `MQL5\Include\Core\MbTuningLocalAgent.mqh`

## Walidacja
- kompilacja floty: `17/17`
- `VALIDATE_PROJECT_LAYOUT.ps1`: `ok=true`
- `VALIDATE_TUNING_HIERARCHY.ps1`: `ok=true`
- `VALIDATE_SYMBOL_POLICY_CONSISTENCY.ps1`: `ok=true`
- `VALIDATE_MT5_SERVER_INSTALL.ps1`: `ok=true`

## Efekt praktyczny
Agent aktywnego eksperymentu nie reaguje juz tak samo na kazda porazke.
Eksperyment wie teraz:
- czy przegral przez sygnal,
- czy przez wykonanie,
- czy przez koszt,
- czy przez brak zaufania do materialu,
- czy przez brak postepu mimo czasu.

To jest kolejny krok od "regulatora parametrow" do "zdyscyplinowanego operatora przyczyny".
