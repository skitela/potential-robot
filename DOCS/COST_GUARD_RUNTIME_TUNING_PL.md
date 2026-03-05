# COST GUARD / JPY BASKET — instrukcja operacyjna (PL)

## Cel
- Ustabilizować automatyczne luzowanie bramki kosztowej.
- Wykrywać flapping (`active` <-> `inactive`) zanim zacznie blokować trading.
- Dawać operatorowi bezpieczny tuner z limitem zmian na dobę i rollbackiem.

## Nowe elementy
- `BIN/cost_guard_runtime.py` — logika progów ON/OFF + histereza + okno flappingu.
- `TOOLS/cost_block_breakdown.py` — raport rozbicia blokad.
- `TOOLS/cost_guard_safe_tuner.py` — bezpieczny tuner + rollback.

## Szybkie komendy
1. Raport blokad od ostatniego restartu:
```powershell
python TOOLS/cost_block_breakdown.py --root C:\OANDA_MT5_SYSTEM --mode since_restart
```

2. Status tunera:
```powershell
python TOOLS/cost_guard_safe_tuner.py --root C:\OANDA_MT5_SYSTEM --mode status
```

3. Bezpieczne strojenie (profil stabilizacji):
```powershell
python TOOLS/cost_guard_safe_tuner.py --root C:\OANDA_MT5_SYSTEM --mode apply --profile fast_relax_stable --daily-limit 2 --note "operator apply"
```

4. Rollback do ostatniej kopii:
```powershell
python TOOLS/cost_guard_safe_tuner.py --root C:\OANDA_MT5_SYSTEM --mode rollback --note "operator rollback"
```

## Uwaga operacyjna
- Po `apply`/`rollback` zrestartuj `SafetyBot`:
```powershell
powershell -ExecutionPolicy Bypass -File TOOLS/SYSTEM_CONTROL.ps1 -Action stop -Root C:\OANDA_MT5_SYSTEM -Profile safety_only
powershell -ExecutionPolicy Bypass -File TOOLS/SYSTEM_CONTROL.ps1 -Action start -Root C:\OANDA_MT5_SYSTEM -Profile safety_only
```
