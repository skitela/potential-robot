# 72. Runtime Persistence And Log Rotation Policy V1

## Cel

Ta warstwa porzadkuje trzy rozne klasy danych runtime:

- biezacy stan nadpisywany,
- dzienniki operacyjne rotowane,
- pamiec uczenia zachowywana celowo.

Nie wszystko, co jest zapisywane, powinno rosnac bez konca.
Jednoczesnie nie wolno nam ucac tej historii, z ktorej korzysta agent strojenia.

## 1. Stan nadpisywany

Te pliki maja pozostac male i aktualne. One nie sa historia.

Przyklady:

- `runtime_state.csv`
- `paper_position.csv`
- `runtime_status.json`
- `execution_summary.json`
- `informational_policy.json`
- `broker_profile.json`
- `runtime_control.csv`
- `tuning_policy.csv`
- `tuning_policy_effective.csv`
- globalne i domenowe kontrakty oraz stany sesyjne

Te pliki sa nadpisywane i nie wymagaja rotacji.

## 2. Dzienniki rotowane

To sa pliki append-only, ktore maja wartosc diagnostyczna i operatorska, ale nie sa naszym glownym magazynem uczenia.

V1 rotuje:

- `incident_journal.jsonl`
- `decision_events.csv`
- `candidate_signals.csv`
- `execution_telemetry.csv`
- `latency_profile.csv`
- `trade_transactions.jsonl`
- `tuning_actions.csv`
- `tuning_deckhand.csv`
- `tuning_family_actions.csv`
- `tuning_coordinator_actions.csv`

Rotacja przenosi je do `archive` i zostawia czysty plik roboczy.

## 3. Pamiec uczenia zachowywana

Te pliki maja wartosc poznawcza dla strojenia i nie powinny byc rotowane mechanicznie:

- `learning_observations_v2.csv`
- `learning_bucket_summary_v1.csv`

Jesli kiedys beda wymagaly odchudzenia, to przez:

- cięcie epok,
- przebudowe summary,
- albo kompresje semantyczna,

a nie przez zwykla rotacje jak dla telemetrii.

## 4. Pliki legacy

`learning_observations.csv` jest traktowany jako kandydat do sprzatania legacy.
Nowa architektura powinna opierac sie na `v2`, nie na starym formacie.

## 5. Narzedzia

Do kontroli tej warstwy sluza teraz:

- `TOOLS\ROTATE_RUNTIME_LOGS.ps1`
- `TOOLS\AUDIT_RUNTIME_PERSISTENCE.ps1`
- `TOOLS\AUDIT_AND_CLEAN_RUNTIME_ARTIFACTS.ps1`

To daje nam trzy rozne odpowiedzi:

- co trzeba zrotowac,
- co trzeba zachowac,
- i co jest juz tylko starym artefaktem.
