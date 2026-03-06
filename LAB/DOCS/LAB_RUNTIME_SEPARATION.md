# LAB vs Runtime Separation (v1.1)

## Model separacji
- Kod LAB: w repo `C:\OANDA_MT5_SYSTEM\LAB` i `C:\OANDA_MT5_SYSTEM\TOOLS`.
- Dane/artefakty LAB: poza repo, domyslnie `<LAB_DATA_ROOT>`.
- Runtime execution path pozostaje w `BIN/MQL5/RUN/LOGS/DB/META/CONFIG`.

## Read paths LAB
- `DB/decision_events.sqlite` (snapshot fallback)
- `DB/m5_bars.sqlite` (snapshot fallback)
- `CONFIG/strategy.json`
- `LOGS/safetybot.log` (window phase detection w schedulerze)
- `EVIDENCE/bridge_audit/*.json` (DP MVP)

## Write paths LAB (dozwolone)
- `LAB/*` (lekkie pointers/docs/evidence)
- `<LAB_DATA_ROOT>\data_curated\*`
- `<LAB_DATA_ROOT>\reports\*`
- `<LAB_DATA_ROOT>\snapshots\*`
- `<LAB_DATA_ROOT>\registry\*`
- `<LAB_DATA_ROOT>\run\*`

## Write paths zakazane (runtime)
- `BIN/*`
- `MQL5/*`
- `RUN/*`
- `LOGS/*`
- `DB/*`
- `META/*`
- `CONFIG/*`
- `OANDAKEY/*`

## Mechanizmy ochronne
- `write-boundary guard`: `TOOLS/lab_guardrails.py`
- `snapshot-read policy`: `LAB/DOCS/SNAPSHOT_READ_POLICY.md`
- Scheduler lock: `LAB_DATA_ROOT/run/lab_scheduler.lock`
- Skip przy aktywnym oknie runtime (domyslnie)
- Resource governor (CPU/MEM), timeout, low-priority

## Audyt separacji
- Generator: `TOOLS/lab_separation_audit.py`
- Evidence: `LAB/EVIDENCE/separation/*.json` + `*.md`
