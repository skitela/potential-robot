OANDA_MT5 — README_TESTS (MUST-RUN)

=== Zasady projektu (dopisane, zamknięte) ===
1) DEV: brak narzędzia w gate => SKIP + UNVERIFIED_TOOLING (dla wszystkich kroków, nie tylko pip-audit).
2) Konfiguracje narzędzi (black/isort/ruff/mypy) tylko w pyproject.toml + ewentualnie bandit.yaml. Bez dodatkowych plików konfiguracyjnych.
3) Każdy test ma działać z katalogu root (C:\OANDA_MT5_SYSTEM) bez ustawiania PYTHONPATH i bez modyfikacji sys.path w testach.
4) Release ZIP ma nie zawierać __pycache__ ani .pyc/.pyo (clean przed pakowaniem + asercja w gate).
5) Testy muszą przechodzić z: python -m unittest discover -s tests -v (uruchamiane z roota).
============================================


Założenia:
- Root runtime: C:\OANDA_MT5_SYSTEM (override: OANDA_MT5_ROOT)
- Manual start/stop (Task Scheduler domyślnie wyłączony)
- Start jest manualny: w tym release nie ma pliku start.bat; komponenty uruchamia się bezpośrednio z BIN\*.py.

0) Gate jakości (deterministyczny, bez zwisu)
- Gate wykonuje clean __pycache__/.pyc przed uruchomieniem oraz asercję po zakończeniu.
- Opcjonalnie: zweryfikuj spakowany release ZIP: python TOOLS\gate.py --mode release --zip <nazwa.zip>
- (Rekomendowane) utwórz venv i zainstaluj: pip install -r requirements-dev.txt
- MODE=release (domyślny): python TOOLS\gate.py --mode release
- MODE=dev (gdy brak sieci / brak pip-audit): użyj parametru: --mode dev
Expected:
- Każde wywołanie subprocess ma timeout (brak wieszek).
- pip-audit: RELEASE=FAIL przy problemie; DEV => GATE_OK | UNVERIFIED_SECURITY przy timeout/missing tool/network; znalezione podatności => FAIL.
 - Brak narzędzia (black/isort/ruff/mypy/bandit): RELEASE=FAIL; DEV => SKIP + GATE_OK | UNVERIFIED_TOOLING.


0.1) Pakowanie release (deterministyczne, clean + weryfikacja ZIP)
- python TOOLS\pack_release.py
Expected:
- Clean __pycache__/.pyc przed pakowaniem.
- Gate przechodzi (MODE z pyproject.toml lub z parametru --mode).
- Powstaje ZIP bez __pycache__/.pyc/.pyo.
1) Start od zera (czysta instalacja / brak runtime root)
- Przygotuj katalog: C:\OANDA_MT5_SYSTEM
- Rozpakuj ZIP do C:\OANDA_MT5_SYSTEM (tak, aby istniały BIN/, TOOLS/, tests/, README/ itd.)
- (Wymagane) Podłącz klucz USB z plikiem: TOKEN\BotKey.env
  Uwaga: bez klucza SafetyBot kończy pracę komunikatem krytycznym i kodem 2 — to jest zachowanie oczekiwane.
- Otwórz 2 okna konsoli (cmd/PowerShell) w C:\OANDA_MT5_SYSTEM i uruchom:

  A) SafetyBot:
     python BIN\safetybot.py

  B) SCUD (ciągły loop, min. 10s interwału):
     python BIN\scudfab02.py loop 10

- (Opcjonalnie) Learner offline (co 1h) – tylko jeśli chcesz generować META\learner_advice.json:
     python BIN\learner_offline.py loop 3600
Expected:
- Katalogi istnieją: BIN/DB/META/RUN/LOGS/README (tworzone automatycznie, jeśli brak).
- Powstają locki: RUN\safetybot.lock i RUN\scudfab02.lock.
- LOGS\safetybot.log oraz LOGS\scudfab02.log zawierają wpisy startowe.
- SCUD odświeża META\scout_advice.json (TTL 900s) i META\verdict.json (TTL 48h).

2) Multi-run / lock (druga instancja)
- Spróbuj uruchomić ponownie te same procesy (osobno), gdy pierwsze już działają:
  - python BIN\safetybot.py
  - python BIN\scudfab02.py loop 10
Expected:
- Druga instancja jest blokowana przez lock (brak duplikatów procesów).
- W RUN/ pozostaje pojedynczy lock dla każdego komponentu.

3) SQLite busy/locked (odporność)
- Na czas testu otwórz decision_events.sqlite w narzędziu blokującym (albo wymuś transakcję).
Expected:
- Brak spin-loop CPU; retry/backoff; system nie umiera „losowo”.

4) Atomic write JSON (kill)
- W czasie pracy ubij proces (Task Manager) podczas intensywnego zapisu JSON (META).
Expected:
- Brak „półplików” .json (albo jest stary poprawny, albo nowy poprawny).

5) Tie-break RUN (A/B)
- Wygeneruj sytuację TOP-2 i sprawdź czy SafetyBot tworzy RUN\tiebreak_request.json
- Sprawdź czy SCUD tworzy RUN\tiebreak_response.json
Expected:
- Jeśli response brak/timeout -> SafetyBot kontynuuje bez blokady.
- Jeśli response jest -> preferencja A/B stosowana.

6) JSONL line length (SCUD)
Expected:
- SCUD nie zapisuje linii JSONL dłuższych niż MAX_JSONL_LINE_LEN=2048.
- Gdy linia byłaby dłuższa -> wpis w logu: JSONL_LINE_TOO_LONG i brak zapisu tej linii.


UPGRADE TEST:
- Upgrade previous ZIP to new ZIP with existing DB\decision_events.sqlite
- Verify MIGRATE logs and continued operation.
