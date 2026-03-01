# Snapshot-Read Policy (LAB)

## Cel
Zmniejszyć ryzyko kolizji odczytu z runtime i utrzymać determinizm danych wejściowych LAB.

## Tryby
- `PREFER_SNAPSHOT` (domyślny):
  - LAB tworzy snapshoty SQLite (`decision_events`, `m5_bars`) do `LAB_DATA_ROOT/snapshots/<ts>/`.
  - Jeśli oba snapshoty powstaną poprawnie -> replay idzie na snapshotach.
  - Jeśli snapshot się nie powiedzie -> fallback do runtime DB w trybie read-only.
- `FORCE_RUNTIME`:
  - LAB czyta bezpośrednio runtime DB (read-only), bez snapshotowania.

## Implementacja
- Snapshot manager: `TOOLS/lab_snapshot_manager.py`
- Pipeline LAB: `TOOLS/lab_daily_pipeline.py --snapshot-policy ...`

## Uwagi operacyjne
- Snapshoty zwiększają I/O przy starcie batcha, ale poprawiają izolację.
- Zalecana retencja snapshotów: 7-14 dni.
