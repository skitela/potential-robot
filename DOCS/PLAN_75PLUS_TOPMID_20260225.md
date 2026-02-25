# PLAN 75+ / TOP-MID (2026-02-25)

## 1) Cel i horyzont
- Cel operacyjny: stabilnie przekroczyc `75/100` w benchmarku V1.
- Cel strategiczny: dojsc do `80/100` (segment TOP) po stabilizacji live.
- Horyzont:
- Etap A (0-2 dni): odblokowanie egzekucji i zamkniecie blockerow P0.
- Etap B (3-7 dni): podniesienie jakosci sygnal->egzekucja i prelive.
- Etap C (8-21 dni): tuning pod wynik i stabilnosc (bez naruszania ochrony kapitalu).

## 2) Kryteria sukcesu (twarde progi)
- Benchmark V1: `>= 75.0` (Etap B), docelowo `>= 80.0` (Etap C).
- Prelive GO/NOGO: `go=true`.
- Retcode `10017`: `0` w aktywnych oknach handlu.
- Incident journal (24h): `critical=0`, `error_or_worse <= 8`.
- Learner QA: `qa_light != RED`, `n_total >= 40`.
- Konwersja sygnalow:
- `ENTRY_SIGNAL -> ORDER_EXECUTED >= 20%` (min. prog techniczny).
- `ENTRY_SIGNAL -> DISPATCH_REJECT(10017) = 0%`.
- Fairness grup:
- Brak twardego faworyzowania: egzekucje per grupa w granicach konfiguracji (+/-15% od target share na sesje).

## 3) Priorytety wykonawcze (kolejnosc)
- P0: zamknac `10017` (konto/serwer/zgody) i potwierdzic `trade_allowed=true`.
- P1: domknac prelive blokery: `LEARNER_QA_RED`, `INCIDENT_*`, `COLD_START_CANARY_OVERRIDE`.
- P2: utrzymac nowe odblokowanie wejsc metali bez psucia ryzyka.
- P3: kalibracja sygnal->egzekucja per grupa i instrument.

## 4) Plan dzienny (checklista operacyjna)
- Start sesji:
- uruchom `START_LONG_SUPERVISOR_72H.bat` (monitoring + watchdog + guard aktywnosci).
- sprawdz procesy monitorow (`live_trade_monitor`, `night_watchdog`, `trade_activity_guard`, `mt5_risk_popup_guard`).
- wykonaj gate:
- `py -3.12 -B TOOLS\\prelive_go_nogo.py --root .`
- wykonaj benchmark:
- `powershell -NoProfile -ExecutionPolicy Bypass -File RUN\\RANKING_BENCHMARK_V1.ps1`
- W trakcie sesji (co 30-60 min):
- kontrola `ENTRY_SIGNAL`, `ORDER_EXECUTED`, `HYBRID_DISPATCH_REJECT`.
- kontrola top reason `ENTRY_SKIP` (czy nie dominuje jeden sztuczny blok).
- kontrola czasu trzymania pozycji vs time-stop.
- Koniec sesji:
- raport dzienny: score, prelive, retcode mix, incident mix, PnL brutto/netto.
- decyzja: utrzymac parametry / cofnac zmiane / lekko dostroic.

## 5) Zasady tuningu (zeby nie rozwalic ryzyka)
- Zmieniamy tylko jedna klase parametrow na raz (single-variable change).
- Każda zmiana ma rollback i pomiar po min. 1 pelnym oknie aktywnym.
- Nie podnosic jednoczesnie:
- `risk_per_trade_max_pct` i `max_open_risk_pct`.
- Dla fairness:
- najpierw heat weighting i limity grupowe,
- dopiero potem progi sygnalu per instrument.

## 6) Najblizsze kroki (konkret)
- Krok 1: potwierdzic z brokerem i terminalem `trade_allowed=true` (P0 blocker).
- Krok 2: po odblokowaniu zrobic 1 sesje walidacyjna i policzyc:
- `ENTRY_SIGNAL`,
- `ORDER_EXECUTED`,
- `retcode distribution`,
- `skip reason distribution`.
- Krok 3: jesli `PORTFOLIO_HEAT` nadal dominuje, dostroic tylko heat (bez ruszania hard-loss).
- Krok 4: podniesc prelive do `GO` i dopiero wtedy pelny tuning pod wynik.

## 7) Kryterium STOP (fail-safe operacyjny)
- Natychmiast stop wejsc, jesli:
- `critical incidents > 0` i narastaja,
- seria rejectow retcode krytycznych przekracza burst guard,
- drawdown dzienny zbliza sie do hard limitu.

