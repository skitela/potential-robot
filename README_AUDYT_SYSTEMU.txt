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

PRZYPOMINAJKA: PUSH DO GITHUB (device flow)
1) Otwórz PowerShell w C:\OANDA_MT5_SYSTEM
2) Uruchom:
   & "C:\ProgramData\skite\GitHubDesktop\app-3.5.4\resources\app\git\cmd\git.exe" push -u origin master
3) Jeśli pojawi się kod, wejdź na:
   https://github.com/login/device
   Wklej kod i zatwierdź.
4) Jeśli URL repo jest inny, ustaw go przed pushem:
   & "C:\ProgramData\skite\GitHubDesktop\app-3.5.4\resources\app\git\cmd\git.exe" remote set-url origin <URL>

Benchmark / Ranking V1 (wspolna metodyka OANDA + GH):
- Kontrakt: SCHEMAS/ranking_benchmark_metodyka_v1.json
- Launcher: TOOLS/ranking_benchmark_v1.py
- Komenda (ta sama w obu repo):
  python -B TOOLS/ranking_benchmark_v1.py
- Wymuszenie targetu:
  python -B TOOLS/ranking_benchmark_v1.py --target-root "C:\GLOBALNY HANDEL VER1"
