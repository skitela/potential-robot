# Etap 1 / Krok 1 — Odrzucone setupy + pokrycie per instrument

## Co robi runtime

- Każdy `ENTRY_SKIP` z aktywnym kontekstem symbolu zapisuje rekord odrzucenia do lokalnej bazy.
- Rekord zawiera:
  - symbol,
  - grupę,
  - tryb,
  - `reason_code`,
  - klasę powodu (np. `COST_QUALITY`, `RISK_GUARD`, `DATA_READINESS`),
  - etap (`stage`),
  - kontekst sygnału/regime (jeśli dostępny).

To jest zapis tylko audytowo-treningowy. Nie zmienia logiki execution.

## Raport pokrycia

Uruchom:

```powershell
py -3.12 -B TOOLS/rejected_coverage_report.py --root C:\OANDA_MT5_SYSTEM --lookback-hours 24
```

Wyniki:

- `EVIDENCE/learning_coverage/rejected_coverage_<timestamp>.json`
- `EVIDENCE/learning_coverage/rejected_coverage_<timestamp>.txt`

Raport pokazuje:

- instrumenty bez danych (`MISSING_ALL_DATA`),
- instrumenty z odrzuceniami, ale bez próbek trade-path (`TRADE_PATH_STARVATION`),
- instrumenty z balansiem trade/no-trade (`OK_BALANCED`).

## Etap 1 / Krok 2 — bramka pokrycia (uczenie tylko na sensownym N)

Uruchom:

```powershell
py -3.12 -B TOOLS/rejected_coverage_gate.py --root C:\OANDA_MT5_SYSTEM --focus-group FX --lookback-hours 24
```

Raport:

- `EVIDENCE/learning_coverage/rejected_coverage_gate_<timestamp>.json`
- `EVIDENCE/learning_coverage/rejected_coverage_gate_<timestamp>.txt`

Werdykt:

- `PASS` — pokrycie danych wystarcza do następnej iteracji uczenia.
- `HOLD` — za mało danych (total/reject/trade) dla części instrumentów.

## Etap 1 / Krok 3 — cykl automatyczny + porządki

Uruchom:

```powershell
powershell -ExecutionPolicy Bypass -File TOOLS/run_stage1_learning_cycle.ps1 -Root C:\OANDA_MT5_SYSTEM -FocusGroup FX -LookbackHours 24 -RetentionDays 14
```

Cykl robi:

1. raport odrzuceń,
2. bramkę pokrycia,
3. budowę datasetu uczenia (NO_TRADE + TRADE_PATH),
4. bramkę jakości datasetu (wolumen + balans + bucket coverage),
5. retencję starych raportów/datasetów.

Rejestracja zadania dziennego (user-level, bez wymuszania admin):

```powershell
powershell -ExecutionPolicy Bypass -File TOOLS/register_stage1_learning_task_user.ps1 -Root C:\OANDA_MT5_SYSTEM -StartTime 22:30
```

## Etap 1 / Krok 4 — bramka jakości datasetu

Uruchom:

```powershell
py -3.12 -B TOOLS/stage1_dataset_quality.py --root C:\OANDA_MT5_SYSTEM
```

Wyniki:

- `EVIDENCE/learning_dataset_quality/stage1_dataset_quality_<timestamp>.json`
- `EVIDENCE/learning_dataset_quality/stage1_dataset_quality_<timestamp>.txt`

Werdykt:

- `PASS` — dane sa wystarczajaco rownomierne per instrument.
- `HOLD` — brak balansu NO_TRADE/TRADE_PATH albo za mala liczba bucketow.

## Dataset v2 (uzupelnienie pod nauke)

Dataset Stage-1 (`stage1_learning_*.jsonl`) zapisuje teraz dodatkowo:

- `instrument`, `side`,
- `gate_result`, `decision_stage`,
- `session_state`, `regime_state`,
- `command_type` (rozdzielone HEARTBEAT/TRADE_PATH/OTHER, gdy dostepne),
- `source_module`, `label_quality`.

To nadal warstwa audytowo-treningowa (brak ingerencji w execution path).
