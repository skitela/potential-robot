# SCUD + Runtime Latency Architecture Review (2026-03-05)

## 0) Cel dokumentu
Ten dokument odpowiada na note techniczny dotyczacy:
- roli SCUD w runtime,
- wplywu SCUD na opoznienia,
- wykonalnosci uproszczenia pipeline pod low-latency scalping.

Dokument jest przygotowany pod analize techniczna "kuzyna" (ChatGPT-5.3-Instant).

---

## 1) Co proponuje note (tlumaczenie na nasz system)
Propozycja sprowadza sie do 3 tez:
1. Ograniczyc runtime do minimalnej sciezki decyzyjnej.
2. Przeniesc advisory/analityke (SCUD) poza sciezke tick->decyzja->zlecenie.
3. Sprawdzic, czy glowny koszt latencji nie wynika z blokujacej komunikacji bridge.

To jest logiczne dla scalpingu.

---

## 2) Mapa obecnej implementacji (pliki + rola)

### 2.1 Glowna petla runtime
- `BIN/safetybot.py:14692` — heartbeat REQ/REP (synchronous).
- `BIN/safetybot.py:14862` — `scan_once()` (decyzja wejsc/filtry).
- `BIN/safetybot.py:14350` — `send_command()` dla TRADE (synchronous REQ/REP).

### 2.2 Bridge (Python <-> MQL5)
- `BIN/zeromq_bridge.py`:
  - PULL: dane market (`setup_sockets`, pull socket),
  - REQ/REP: komendy i potwierdzenia (`send_command`).
- `send_command` robi `poll(timeout)` i czeka synchronicznie na odpowiedz.
- To jest obecnie glowny punkt blokowania.

### 2.3 SCUD i tie-break
- `BIN/safetybot.py:13983` — SCUD path uruchamiana tylko przy near-tie.
- `BIN/safetybot.py:3904` — zapis `RUN/tiebreak_request.json`.
- `BIN/safetybot.py:3909` — polling odpowiedzi do `TIEBREAK_WAIT_SEC=0.35`.
- `BIN/scudfab02.py:393` — szybka obsluga tie-break request po stronie SCUD.
- `BIN/scudfab02.py:1410` + loop co 10s — SCUD pracuje jako osobny proces.

### 2.4 Procesy uruchamiane razem
- `TOOLS/SYSTEM_CONTROL.ps1:711`:
  - SafetyBot,
  - SCUD,
  - Learner,
  - InfoBot,
  - RepairAgent.
- Profil `safety_only` uruchamia tylko SafetyBot.

---

## 3) Odpowiedz na pytania z note

### Q1. Czy SCUD jest pytany synchronicznie podczas trade decision loop?
`TAK, WARUNKOWO`.
- Tylko gdy jest near-tie (`has_near_tie_in_topk`) i dodatkowe warunki verdict.
- Nie jest to kazda iteracja i nie jest to kazdy sygnal.

### Q2. Czy engine czeka na SCUD output przed execution?
`CZESCIOWO`.
- W sciezce tie-break engine moze czekac do `0.35s`.
- Brak odpowiedzi SCUD nie zatrzymuje calosci: fallback do bazowej kolejnosci kandydatow.

### Q3. Czy SCUD doklada IPC zwiekszajace bridge_wait?
`NIE BEZPOSREDNIO` dla ZMQ bridge_wait.
- SCUD nie korzysta z runtime ZMQ REQ/REP.
- SCUD komunikuje sie glownie przez pliki (`RUN/META`) i SQLite read-only.
- Moze dokladac posredni jitter I/O/CPU, ale nie jest glownym zrodlem `bridge_wait`.

---

## 4) Dane z runtime i logow (fakty)

### 4.1 Latencja
Plik:
- `C:\Users\skite\Desktop\LATENCY_DIAGNOSTIC_OANDA_MT5_SYSTEM.txt`

Wskazania:
- `bridge_wait_p95_ms ~ 984`
- `decision_core_p95_ms ~ 982`
- `HEARTBEAT RTT p95 ~ 1005 ms`
- `io_log_p95_ms ~ 2 ms`

Wniosek:
- Dominujacy koszt = czekanie na bridge/odpowiedz (REQ/REP), nie log I/O.

### 4.2 Aktywnosc tie-break
Analiza `LOGS/safetybot.log`:
- `TIEBREAK_SKIP` bardzo czesto (verdict zwykle RED),
- `TIEBREAK_TIMEOUT` = 0,
- `TIEBREAK_RESP` = 0.

Dodatkowo:
- `META/verdict.json` pokazuje `light=RED`.

Interpretacja:
- SCUD tie-break obecnie prawie nie ma realnego wplywu na decyzje (bo nie wchodzi do akcji).

---

## 5) Czy propozycja jest logiczna i czy da sie wdrozyc?

## 5.1 Czy logiczna?
`TAK`.
- Dla scalpingu minimalizacja hopow i blokowania jest prawidlowa.
- Rozdzielenie execution od analytics jest zgodne z dobrymi praktykami low-latency.

## 5.2 Czy da sie wdrozyc "1:1" juz teraz?
`NIE 1:1` bez duzej przebudowy.
- Note zaklada model "MT5 decyduje i egzekwuje, Python tylko offline".
- Nasz obecny runtime owner decyzji to Python SafetyBot + bridge do MQL5.
- Przeniesienie calej logiki decyzyjnej do MQL5 to osobny projekt (duzy refactor).

## 5.3 Co da sie wdrozyc od razu (bez ryzyka rozbicia systemu)?
`TAK, etapowo`:
1. Odlaczyc SCUD od runtime loop (profil `safety_only`).
2. Zostawic SCUD jako offline advisor (harmonogram, bez runtime gatingu).
3. Dodac twardy flag-switch `scud_tiebreak_enabled=false` w SafetyBot.
4. Skupic optymalizacje na bridge REQ/REP i heartbeat path.

---

## 6) Krytyka i rzetelna ocena propozycji "kuzyna"

### Mocne strony propozycji
- Trafnie identyfikuje koszt architektoniczny "advisory blisko runtime".
- Trafnie wskazuje bridge jako podejrzane zrodlo opoznien.
- Wymusza prostszy pipeline i lepsza obserwowalnosc latencji.

### Slabe strony propozycji
- Upraszcza role MT5 i pomija koszt przepisu decyzji strategii do MQL5.
- Nie rozroznia "SCUD moze byc aktywny" od "SCUD faktycznie dominuje latencje".
- Nie daje planu migracji kompatybilnego z obecnym kontraktem runtime.

### Konkluzja
- Kierunek jest poprawny.
- Wdrozenie musi byc etapowe i kompatybilne z obecna architektura.

---

## 7) Rekomendacja wdrozeniowa (bezpieczna)

### Etap A (natychmiast, P0)
- Run profile: `safety_only` (bez SCUD/Learner/InfoBot/RepairAgent w runtime).
- Potwierdzic poprawny heartbeat i brak regresji decyzji.

### Etap B (P1)
- Dodac config flag:
  - `scud_tiebreak_enabled` (default `false` dla live runtime),
  - `scud_verdict_read_enabled` (opcjonalnie `false`).
- W kodzie SafetyBot ominac `write_tiebreak_request/load_tiebreak_response`.

### Etap C (P1/P2)
- SCUD uruchamiac cyklicznie offline:
  - write `META/verdict.json`,
  - write `META/scout_advice.json`,
  - bez read w hot path.

### Etap D (P2)
- Bridge optimization:
  - analiza timeout budget i retry polityki,
  - redukcja blokowania heartbeat,
  - osobny profiler TRADE_PATH E2E (tick->signal->send->fill).

---

## 8) Odpowiedz gotowa do wyslania "kuzynowi"

Poniżej wersja techniczna, gotowa do przeklejenia:

---
**Temat: SCUD i latencja runtime — wynik weryfikacji**

Dzieki za note. Sprawdzilem kod i runtime.

1. SCUD jest podpinany do petli decyzyjnej tylko warunkowo (near-tie + verdict GREEN), nie globalnie.
2. W tej sciezce moze wystapic krotkie czekanie na odpowiedz (do ~350 ms), ale brak odpowiedzi nie blokuje execution — jest fallback.
3. SCUD nie uczestniczy bezposrednio w ZMQ bridge REQ/REP (glowny trade/heartbeat channel). Korzysta glownie z plikow RUN/META i SQLite read-only.

Z danych runtime:
- bridge_wait p95 ~ 984 ms,
- HEARTBEAT RTT p95 ~ 1005 ms,
- io_log p95 ~ 2 ms.

Wniosek: glownym zrodlem opoznien jest blokujaca komunikacja bridge (REQ/REP wait), nie SCUD.

SCUD obecnie ma niski realny wplyw decyzyjny (w logach dominuje TIEBREAK_SKIP, brak TIEBREAK_RESP/TIMEOUT), bo verdict jest zwykle RED.

Rekomendacja:
- przeniesc SCUD do trybu offline advisory,
- usunac SCUD z runtime loop (`safety_only` + flagi tie-break OFF),
- skupic tuning na bridge i heartbeat path.

To da uproszczenie pipeline i lepsza kontrola latencji bez utraty analityki.

---

## 9) Status
- Analiza wykonana.
- Brak zmian runtime code w tym kroku (tylko dokumentacja).
