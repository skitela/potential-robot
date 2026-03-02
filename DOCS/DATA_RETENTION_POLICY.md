# Data Retention Policy (Trading vs Maintenance)

## Cel
- Ograniczyc szum danych i I/O.
- Zachowac dane transakcyjne do kalibracji strategii (w tym Renko i swiece).
- Trzymac dane maintenance tylko tyle, ile potrzeba do diagnostyki.

## Konfiguracja
- Plik polityki: `CONFIG/data_retention_policy.json`
- Narzedzie wykonawcze: `TOOLS/data_retention_cycle.py`
- Auto-harmonogram: `TOOLS/runtime_stability_cycle.py` (poza `ACTIVE`, raz dziennie przez `--daily-guard`)

## Co jest czyszczone
- `LOGS/execution_telemetry_v2.jsonl` (transakcyjne, domyslnie 180 dni)
- `LOGS/incident_journal.jsonl` (transakcyjne, domyslnie 180 dni)
- `LOGS/audit_trail.jsonl` (maintenance, domyslnie 14 dni)

## Co jest archiwizowane
- Transakcyjne rekordy po terminie retencji: `ARCHIVE/retention/transactional/...`
- Maintenance po terminie retencji: domyslnie bez raw archive.
- Anomalie usuwane przez retencje trafiaja do paczki incydentowej:
  - `EVIDENCE/retention/incidents/incident_pack_*.json`

## Raporty
- Raport uruchomienia:
  - `EVIDENCE/retention/runs/retention_cycle_*.json`
- Raport dzienny:
  - `EVIDENCE/retention/daily/retention_daily_YYYYMMDD.json`
- Raport dzienny zawiera:
  - co usunieto,
  - ile bajtow odzyskano,
  - z jakiego powodu (retencja wg polityki),
  - czy powstal incident pack.

## Uruchomienie reczne
```powershell
python TOOLS/data_retention_cycle.py --root C:\OANDA_MT5_SYSTEM --policy CONFIG/data_retention_policy.json --apply
```

## Tryb bezpieczny (raz dziennie)
```powershell
python TOOLS/data_retention_cycle.py --root C:\OANDA_MT5_SYSTEM --policy CONFIG/data_retention_policy.json --daily-guard --apply
```

## Uwagi
- Narzedzie nie zmienia logiki strategii.
- Operuje na danych i raportowaniu retencji.
- W `ACTIVE` retention jest odpalany przez stability cycle tylko poza oknem aktywnym.
