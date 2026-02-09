README_AUDYT_SYSTEMU — instrukcja uruchomienia audytu (wrapper)

KANON / jedyne źródło prawdy audytorskiej:
- AUDIT_POLICY.json
Kanoniczny release_id: 20260207_1321_v6_2_corehygiene2

Zakres (twardo):
- OFFLINE: brak sieci, brak KEY, brak LIVE.
- CORE/: w tej iteracji dopuszczone tylko higieniczne zmiany mechaniczne (bez semantyki/strategii).
- Brak zmian strategii tradingu/scalpingu ani logiki biznesowej.

Tryby audytu:

1) OFFLINE (ZIP-first; po rozpakowaniu do katalogu roboczego)
   - python -B TOOLS/diag_bundle_v6.py
   - python -B TOOLS/gate_v6.py --mode offline

2) ONLINE_PREFLIGHT (pozwala mieć internet, ale testy nie wysyłają zleceń i nie wymagają KEY)
   - python -B TOOLS/gate_v6.py --mode online_preflight

3) ONLINE_SMOKE (Windows, terminal OANDA MT5; test IPC/terminal_info, bez handlu)
   - python -B TOOLS/online_smoke_mt5.py --mt5-path "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe"

Dowody:
- Bramki: EVIDENCE/gates/<gate_name>__<run_id>.txt
- Diagnostyka: DIAG/bundles/LATEST/*
- ONLINE_SMOKE: EVIDENCE/online_smoke/<run_id>_mt5_smoke.json

Zasada: brak dowodu = FAIL (szczegóły w AUDIT_POLICY.json).
