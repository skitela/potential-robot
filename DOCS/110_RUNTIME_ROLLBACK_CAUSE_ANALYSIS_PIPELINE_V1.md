# 110 Runtime Rollback Cause Analysis Pipeline V1

## Cel
Podpiac nowe klasy przyczyny eksperymentu do pozniejszej analizy runtime tak, aby bylo
widac per instrument:
- kiedy eksperyment wszedl w `ROLLBACK`,
- jaka byla domena przyczyny,
- czy byl to problem `SIGNAL`, `EXECUTION`, `COST`, `DATA`, `RISK`, `CENTRAL` albo `INFRA`,
- czy klasyfikacja pochodzi z jawnych pol nowego schema, czy z fallbacku dla starszego materialu.

## Co zostalo zrobione

### 1. Dodano lekki raport runtime
Nowe narzedzie:
- `TOOLS\GENERATE_TUNING_ROLLBACK_CAUSE_REPORT.ps1`

Raport:
- czyta `tuning_experiments.csv` ze wszystkich symboli,
- obsluguje:
  - aktywne logi,
  - archiwa po `schema_reset`,
- rozroznia:
  - `legacy_v1`
  - `cause_v2`
- dla rollbacku wybiera klase przyczyny w kolejnosci:
  1. `failure_reason_*`
  2. `review_reason_*`
  3. `report_reason_*`
  4. fallback po `execution_quality_state`
  5. fallback po `cost_pressure_state`
  6. fallback po `trust_state`
  7. ostrozny fallback `SIGNAL / NEGATIVE_OUTCOME / LEGACY_INFERRED_SIGNAL_FAILURE`

Raport zapisuje:
- JSON
- Markdown
- pliki timestampowane
- oraz wariant `latest`

### 2. Odsunieto stary schemat logow
Przed restartem wykonano:
- `RESET_RUNTIME_JOURNAL_SCHEMA.ps1`
  - dla `tuning_experiments.csv`
  - na wszystkich `17` symbolach

To bylo konieczne, zeby nie mieszac nowych kolumn `failure_reason_*` i `review_reason_*`
ze starym naglowkiem.

### 3. Odswiezono paczke i runtime MT5
Wykonano:
- `EXPORT_MT5_SERVER_PROFILE.ps1`
- `INSTALL_MT5_SERVER_PACKAGE.ps1`
- restart przez:
  - `RUN\OPEN_OANDA_MT5_WITH_MICROBOTS.ps1`

MT5 po restarcie zaladowal ponownie cala flote `17` mikro-botow.

## Wynik pierwszego raportu runtime
Pliki:
- `EVIDENCE\TUNING_ROLLBACK_CAUSE_RUNTIME_latest.json`
- `EVIDENCE\TUNING_ROLLBACK_CAUSE_RUNTIME_latest.md`

Stan na ten etap:
- historyczny material rollbacku zostal poprawnie odczytany z archiwum,
- nowy pipeline runtime dziala,
- ale pierwsze swieze rollbacki po schema `cause_v2` jeszcze sie nie pojawily.

To oznacza:
- analiza jest juz podpieta,
- srodowisko runtime jest juz czyste,
- ale obecny raport jeszcze uczciwie klasyfikuje historyczne rollbacki glownie jako:
  - `SIGNAL / NEGATIVE_OUTCOME / LEGACY_INFERRED_SIGNAL_FAILURE`

Nie jest to wada nowej warstwy. To oznacza po prostu, ze po czyszczeniu schematu i restarcie
rynek nie zdazyl jeszcze zapisac pierwszych nowych rollbackow z jawna przyczyna `failure_reason_*`.

## Najwazniejszy efekt praktyczny
Od teraz mamy porzadek:
- stare rollbacki sa odlozone do archiwum,
- nowe rollbacki beda wchodzily do czystego schematu,
- raport runtime jest juz gotowy i nie wymaga kolejnej przebudowy.

## Zmienione / dodane pliki
- `TOOLS\GENERATE_TUNING_ROLLBACK_CAUSE_REPORT.ps1`

## Artefakty operacyjne tego etapu
- `EVIDENCE\TUNING_ROLLBACK_CAUSE_RUNTIME_latest.json`
- `EVIDENCE\TUNING_ROLLBACK_CAUSE_RUNTIME_latest.md`
- `EVIDENCE\install_mt5_server_package_report.json`
- `EVIDENCE\install_mt5_server_package_report.txt`

## Walidacja
- `VALIDATE_PROJECT_LAYOUT.ps1`: `ok=true`
- `VALIDATE_MT5_SERVER_INSTALL.ps1`: `ok=true`

## Uczciwy wniosek
Pipeline analizy przyczyny rollbacku jest wdrozony poprawnie.
Runtime jest juz przygotowany do jawnej klasyfikacji:
- `SIGNAL`
- `EXECUTION`
- `COST`
- `DATA`
- `RISK`
- `CENTRAL`
- `INFRA`

Na te chwile mamy jeszcze glownie material `legacy_v1`.
Pierwsza pelna korzysc z nowej epistemologii pojawi sie wtedy, gdy po tym restarcie
rynek zostawi nowe wpisy `ROLLBACK` w czystym schemacie `cause_v2`.
