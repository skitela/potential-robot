# Runtime Log Rotation Tool

## Cel

Narzedzie sluzy do bezpiecznej rotacji przerosnietych logow runtime w `Common Files`, tak aby:

- zatrzymac narastanie starych, bardzo ciezkich plikow,
- zachowac historie w `archive`,
- zostawic czyste pliki robocze dla kolejnych sesji,
- nie traktowac historycznego balastu jako aktywnego materialu operacyjnego.

## Zakres

Narzedzie skanuje tylko glowne logi runtime poza katalogami `archive`:

- `incident_journal.jsonl`
- `decision_events.csv`
- `latency_profile.csv`

## Zasady bezpieczenstwa

- plik jest kandydatem do rotacji tylko po przekroczeniu limitu rozmiaru,
- plik musi byc starszy niz minimalny wiek ochronny,
- plik nie jest usuwany: jest przenoszony do `archive\\timestamp`,
- w miejscu roboczym zostaje pusty plik gotowy na kolejne wpisy.

## Domyslne progi

- `incident_journal.jsonl`: `8 MB`
- `decision_events.csv`: `8 MB`
- `latency_profile.csv`: `16 MB`

## Uzycie

Audit bez zmian:

```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\ROTATE_RUNTIME_LOGS.ps1
```

Rotacja z zastosowaniem zmian:

```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\ROTATE_RUNTIME_LOGS.ps1 -Apply
```

## Artefakty

Narzedzie zapisuje raporty do:

- `EVIDENCE\runtime_log_rotation_report.json`
- `EVIDENCE\runtime_log_rotation_report.txt`
