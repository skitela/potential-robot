# GEMINI AUDIT AND EVOLUTION BRIEF (CODEX)
Date: 2026-02-22
Repo: C:\OANDA_MT5_SYSTEM
Branch: audit/oanda_tms_live_execution_hardening
Head commit: 785c0e7

## 1) Executive technical summary
System przeszedl kolejna sesje hardeningu warstwy hybrydowej Python <-> MQL5.
Najwazniejsze zmiany zostaly wdrozone wokol deterministycznego kontraktu REQ/REP,
integralnosci wiadomosci oraz fail-safe na utracie synchronizacji.

Glowne cele sesji:
- podniesienie stabilnosci operacyjnej,
- skrocenie drogi decyzyjnej dla scalpingu bez rollbacku architektury hybrydowej,
- mocniejsze zabezpieczenie kapitalu i zgodnosci z ograniczeniami brokera.

## 2) Co zostalo zrobione (fakty)

### 2.1 Python bridge hardening (`BIN/zeromq_bridge.py`)
Wdrozone:
- deterministyczne hash requestu i response (`build_request_hash`, `build_response_hash`),
- automatyczne dopelnienie `__v`, `schema_version`, `msg_id`, `request_hash`, `request_ts_utc`,
- walidacja korelacji (`correlation_id`),
- walidacja hashy odpowiedzi (`response_hash`) i opcjonalnie echa `request_hash`,
- retry/timeout z reconnect REQ oraz audyt trail eventow,
- metryka RTT (`ZMQ_RTT`) dla monitoringu opoznien.

Uzasadnienie:
- eliminuje ciche desynchronizacje i duplikacje wykonania,
- poprawia audytowalnosc i identyfikowalnosc kazdego polecenia.

### 2.2 Python orchestration hardening (`BIN/safetybot.py`)
Wdrozone:
- walidacja kontraktu reply w dispatchu trade (correlation/hash),
- heartbeat REQ/REP z walidacja hash; progresja do fail-safe po N kolejnych porazkach,
- mechanizm snapshot freshness (`hybrid_snapshot_max_age_sec`) i blokada nowych wejsc przy stale data,
- snapshot-first pipeline:
  - preferencja BAR z MQL5 zamiast fetchowania M5 przez Python,
  - opcjonalny resampling M5 -> wyzsze TF z lokalnego store,
  - strict no-fetch path dla danych M5,
- opcjonalne uzycie cech z MQL5 (`sma_fast`, `adx`, `atr`) jako fast-path dla wejsc.

Uzasadnienie:
- zmniejsza zaleznosc od wolniejszych sciezek i niepotrzebnych fetchy,
- poprawia determinism i stabilnosc decyzji przy scalpingu.

### 2.3 MQL5 execution hardening (`MQL5/Experts/HybridAgent.mq5`)
Plik zostal przebudowany pod twardy kontrakt i niezawodnosc:
- dopelnienie i walidacja `__v`, `schema_version`, `request_hash`,
- odpowiedzi zawieraja `request_hash` + `response_hash`,
- idempotency cache reply po `msg_id` (powtorka requestu nie duplikuje akcji),
- twarda obsluga heartbeat (`HEARTBEAT_REPLY`) przez ten sam kontrakt hash,
- telemetryczne BAR/TICK wysylane z wersjonowaniem i schema,
- BAR moze zawierac fast feature payload (`sma_fast`, `adx`, `atr`) liczony lokalnie w MT5,
- fail-safe timeout po stronie EA utrzymany (zamykanie pozycji na utrate lacznosci).

Uzasadnienie:
- skrocenie "last mile execution" i redukcja slabej spojnosc request/reply,
- mniejsze ryzyko powtornego wykonania i ryzyko dryfu protokolu.

### 2.4 Testy i walidacja
Zaktualizowano testy:
- `tests/test_zeromq_bridge_e2e.py` (happy path, timeout/retry, desync, hash mismatch),
- `tests/test_hybrid_m5_no_fetch.py` (store-first, strict no-fetch, fallback behavior).

Wynik regresji:
- `python -B -m unittest discover -s tests -p 'test_*.py' -v`
- rezultat: OK, 188 testow.

### 2.5 Deploy do MT5
Wykonano:
- `cmd /c Aktualizuj_EA.bat`
- finalnie status: sukces kopiowania `HybridAgent.mq5` i include `.mqh` po uruchomieniu z podniesionymi uprawnieniami.

Uwaga operacyjna:
- po deploy wymagane standardowo: kompilacja EA w MetaEditor (`F7`) i przeladowanie EA na wykresie.

## 3) Relacje i zaleznosci komponentow (scalping architecture)

### 3.1 Warstwa MQL5 (owner execution + market snapshots)
- `HybridAgent.mq5`: agent wykonawczy i publisher danych TICK/BAR.
- `zeromq_bridge.mqh`: transport ZMQ (PUSH data + REP reply).

Odpowiedzialnosc:
- MQL5 jest wlascicielem danych terminalowych i egzekucji zlecen,
- MQL5 nie oddaje "price placement" do Pythona,
- MQL5 potwierdza wykonanie i zwraca wynik transakcji.

### 3.2 Warstwa Python (decision service + risk orchestration)
- `safetybot.py`: decyzja trade/no-trade, harmonogram, tryby, fail-safe orchestration.
- `zeromq_bridge.py`: kontrakt IPC, walidacje, retry i audyt.
- `risk_manager.py`: sizing i twarde ograniczenia ryzyka.
- `learner_offline.py`: offline uczenie i ewaluacja.

Odpowiedzialnosc:
- Python operuje na snapshotach i danych kontraktowych,
- Python nie powinien realizowac "price polling loop" jako glowny mechanizm decyzyjny dla scalpingu.

### 3.3 Przeplyw uczenia i wykorzystania wiedzy
1. MQL5 publikuje TICK/BAR (+ optional features).
2. Python dokonuje selekcji sygnalu i policy check.
3. Python wysyla decyzje trade przez REQ/REP.
4. MQL5 wykonuje i zwraca potwierdzenie z retcode/details/hash.
5. Python zapisuje zdarzenie decyzji i outcome do analityki offline.
6. Warstwa offline kalibruje parametry i governance (bez lamania granic ryzyka/compliance).

## 4) Dlaczego teraz powinno dzialac lepiej niz przedtem

1. Lepsza deterministycznosc:
- request/reply ma jednoznaczny podpis i korelacje.

2. Mniejsze ryzyko "silent failure":
- heartbeat i hash mismatch nie sa ignorowane.

3. Lepsza odpornosc runtime:
- stale snapshot -> blokada nowych wejsc zamiast handlu na niepewnych danych.

4. Lepsza wydajnosc skarpingu:
- fast path cech i data-plane z MQL5 zmniejsza overhead po stronie Pythona.

5. Lepsza audytowalnosc:
- kazda krytyczna operacja ma artefakt i identyfikator.

## 5) Kontekst 3 kryteriow wlascicielskich (must-hold)

K1 Stabilnosc bota:
- brak deadlockow REQ/REP,
- kontrolowany fallback i fail-safe przy degradacji.

K2 Efektywnosc i jakosc skarpingu:
- szybki tor decyzyjny MQL5+Python,
- brak zbednych fetchy,
- stabilny feed snapshot i przewidywalna latencja.

K3 Ochrona kapitalu:
- twarde limity i bloker ryzyka,
- brak transakcji przy utracie spojnosc kontraktu,
- brak przekroczen ograniczen brokera.

## 6) Zlecenie audytowe dla Gemini (P0/P1/P2/P3)

### P0 (critical - blocker do live)
1. Kontrakt IPC:
- sprawdzic zgodnosc hash/version/correlation po obu stronach,
- potwierdzic idempotency replay dla duplikowanego `msg_id`.

2. Fail-safe i no-trade discipline:
- udowodnic, ze na timeout/desync/hash mismatch nie ma nowych wejsc,
- potwierdzic close-only/no-trade zgodnie z policy mode.

3. Pending-order ban:
- statyczny scan i runtime proof, ze nie powstaja nowe pendingi,
- dopuszczalne tylko cancel/remove.

4. No-fetch policy integrity:
- potwierdzic, ze decision path pracuje snapshot-first,
- wskazac kazde wyjatek i uzasadnienie.

### P1 (hardening operacyjny)
1. OANDA constraints compliance:
- potwierdzic przestrzeganie limitow request/order i ograniczen platformowych,
- wykazac, ze system wykorzystuje limity efektywnie, bez naruszen.

2. Latency and throughput:
- benchmark REQ/REP RTT i scan cadence przy typowym i stresowym obciazeniu,
- wskazac bottleneck i plan redukcji.

3. Recovery drills:
- scenariusze restart/reconnect MT5/Python/ZMQ,
- dowod poprawnego powrotu do stanu gotowosci bez side effects.

### P2 (jakosc decyzji i trening)
1. Data quality i leakage control:
- walidacja struktury danych treningowych i etykiet outcome,
- testy anty-overfit i drift.

2. Feature governance:
- ocena czy cechy dostarczane przez MQL5 sa stabilne i niezaszumione,
- weryfikacja ich realnego wplywu na precision scalp entries.

3. Decision analytics:
- analiza false-positive/false-negative dla sygnalow BUY/SELL,
- propozycje poprawy quality gate bez podnoszenia ryzyka.

### P3 (evolution, ale bez psucia kontraktu)
1. Refactor plan:
- propozycja co jeszcze przeniesc do MQL5 dla szybszej egzekucji,
- przy zachowaniu roli Python jako decision policy layer.

2. Production readiness:
- plan canary/live rollout z twardymi warunkami GO/NO-GO,
- mierniki sukcesu i kill criteria.

## 7) Oczekiwane artefakty od Gemini (obowiazkowo)
1. Raport audytowy P0/P1/P2/P3 z klasyfikacja: PASS/FAIL/UNKNOWN.
2. Lista ryzyk z priorytetem i planem remediacji.
3. Test matrix (offline + stress + fail-safe + replay/idempotency).
4. Konkretne rekomendacje architektoniczne:
- co utrzymac,
- co uproscic,
- co przyspieszyc (Python vs MQL5 split).
5. Minimalny plan wdrozenia kolejnej iteracji bez regresji i bez naruszenia limitow OANDA.

## 8) Twarde zasady dla dalszej pracy
- Nie rollbackowac hybrydy Python+MQL5.
- Nie oslabiaac fail-safe.
- Nie dodawac pending-order pathway.
- Nie dopuszczac "silent acceptance" wiadomosci bez walidacji.
- Kazda zmiane MQL5 wdrazac przez `Aktualizuj_EA.bat`, potem kompilacja EA.

---
Prepared by: GPT-5 Codex
Intent: handoff for independent, critical Gemini audit and next-step optimization.
