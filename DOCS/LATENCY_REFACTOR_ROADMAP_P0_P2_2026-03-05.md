# OANDA_MT5_SYSTEM — Roadmap Zmian Latency (P0/P1/P2)

Data: 2026-03-05  
Cel: skrócić opóźnienia bez osłabiania ochrony kapitału i bez psucia logiki handlu.

## Zasady nienaruszalne
1. Nie ruszamy twardych blokad ryzyka kapitału.
2. Nie usuwamy mechanizmów bezpieczeństwa, tylko przenosimy ciężkie rzeczy poza szybki tor decyzji.
3. Każda zmiana ma pomiar „przed i po”.
4. Każda zmiana ma plan cofnięcia.

## Szybki tor decyzji (ma zostać minimalny)
1. Tick.
2. Szybkie sprawdzenie spreadu.
3. Szybkie sprawdzenie ryzyka.
4. Sygnał.
5. Wysłanie zlecenia.

---

## P0 — Zmiany natychmiastowe (bez łamania kontraktu)
Priorytet: najwyższy.  
Horyzont: 1-3 dni.

1. Odciążenie logowania w bridge
- Co: przenieść ciężki zapis audytu z toru komendy do kolejki w tle.
- Po co: zmniejszyć blokowanie na wysyłce i odbiorze komend.
- Oczekiwany efekt: wyraźnie mniej skoków opóźnień (szczególnie p95/p99).

2. Rozdzielenie blokad komend
- Co: heartbeat nie może blokować komendy handlowej.
- Po co: handel ma mieć pierwszeństwo przed kontrolą „żyje/nie żyje”.
- Oczekiwany efekt: mniej timeoutów i mniejszy `bridge_wait_ms` na ścieżce TRADE.

3. Osobne budżety czasu dla TRADE i HEARTBEAT
- Co: krótsze i ostrzejsze limity dla heartbeat, stabilne limity dla trade.
- Po co: żeby heartbeat nie „zjadał” czasu systemu.
- Oczekiwany efekt: stabilniejsza pętla runtime.

4. Redukcja stałego usypiania pętli
- Co: ograniczyć wpływ stałego `sleep(0.01)` w miejscach, gdzie to możliwe.
- Po co: zmniejszyć sztuczny jitter.
- Oczekiwany efekt: lepsza reakcja na tick.

Kryterium zaliczenia P0:
1. Brak regresji testów.
2. Spadek `bridge_wait_ms` p95 na TRADE vs baseline.
3. Mniej timeoutów TRADE w tym samym oknie pomiarowym.

---

## P1 — Zmiany średnie (kontrolowana przebudowa)
Priorytet: wysoki.  
Horyzont: 3-7 dni.

1. Fizyczny podział kanałów komunikacji
- Co: osobny kanał dla handlu, osobny kanał dla heartbeat.
- Po co: brak wzajemnego zakłócania.
- Oczekiwany efekt: stabilniejsza latencja TRADE.

2. Ranking symboli i TOP-N
- Co: pełny ranking co 1 sekunda, szybki tor analizuje tylko TOP-N.
- Po co: mniejszy koszt CPU na decyzję.
- Oczekiwany efekt: krótszy czas decyzji przy wielu instrumentach.

3. Przeniesienie cięższych analiz do trybu async/shadow
- Co: Renko/candles/drift/mikrostruktura liczone poza torami wejścia.
- Po co: szybsza decyzja bez utraty wiedzy analitycznej.
- Oczekiwany efekt: mniejszy czas pętli i mniej skoków.

Kryterium zaliczenia P1:
1. Dalszy spadek p95/p99 na TRADE.
2. Brak wzrostu odrzuceń z powodów ryzyka.
3. Brak pogorszenia jakości decyzji (shadow porównanie).

---

## P2 — Zmiany docelowe (większa modernizacja)
Priorytet: średni.  
Horyzont: 1-3 tygodnie.

1. Kolejka zleceń i worker wykonawczy
- Co: decyzja i wykonanie rozdzielone, wykonanie idzie przez dedykowany worker.
- Po co: zero blokowania decyzji przez operacje wykonawcze.
- Oczekiwany efekt: najniższy jitter i większa płynność pracy.

2. Model bardziej reaktywny (event-driven)
- Co: więcej zdarzeń, mniej aktywnego „kręcenia pętli”.
- Po co: krótsza droga od ticka do działania.
- Oczekiwany efekt: dalsza poprawa czasu reakcji.

3. Opcjonalna migracja wybranych mikro-kontroli bliżej MQL5
- Co: tylko te elementy, które są krytyczne czasowo i bezpieczne.
- Po co: maksymalne skrócenie drogi decyzji.
- Oczekiwany efekt: poprawa końcowa przy zachowaniu bezpieczeństwa.

Kryterium zaliczenia P2:
1. Stabilna poprawa p50/p95/p99 przez kilka sesji.
2. Brak pogorszenia bezpieczeństwa.
3. Udokumentowany rollback i test awaryjny.

---

## Kolejność wdrożenia (dokładna)
1. Baseline 24h: pomiary „przed”.
2. P0.1 odciążenie logów.
3. P0.2 rozdzielenie blokad.
4. P0.3 budżety czasu per typ komendy.
5. P0.4 redukcja wpływu `sleep`.
6. Pomiar po P0 i decyzja GO/STOP.
7. P1.1 fizyczny podział kanałów.
8. P1.2 ranking TOP-N.
9. P1.3 przeniesienie analiz do async/shadow.
10. Pomiar po P1 i decyzja GO/STOP.
11. P2.1 kolejka + worker wykonawczy.
12. P2.2 event-driven.
13. P2.3 ewentualne mikro-przeniesienia bliżej MQL5.
14. Pomiar końcowy i decyzja produkcyjna.

---

## Czy to da efekt?
Tak, ale warunkowo.

1. Sam „podział mostu” logiczny nie wystarczy, jeśli dalej jest blokujące czekanie i ciężki zapis na tej samej ścieżce.
2. Największy efekt da zestaw P0 + P1, nie pojedyncza zmiana.
3. Oczekiwany rezultat jest realny jako poprawa etapowa, nie „magiczny skok po jednej poprawce”.

---

## Ryzyko i kontrola
1. Ryzyko: zbyt agresywne odchudzanie może osłabić ochronę.
- Kontrola: nie ruszać twardych guardów ryzyka.

2. Ryzyko: poprawa średniej, ale pogorszenie skrajnych przypadków.
- Kontrola: monitorować p95/p99, nie tylko p50.

3. Ryzyko: trudna diagnoza po kilku zmianach naraz.
- Kontrola: wdrażać krokowo i mierzyć po każdym kroku.
