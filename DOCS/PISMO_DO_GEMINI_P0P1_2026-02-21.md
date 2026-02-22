# Pismo do Gemini: P0/P1 - pytania audytowe (OANDA_MT5_SYSTEM)

Data: 2026-02-21  
Branch: `audit/oanda_tms_live_execution_hardening`  
HEAD: `d0328a0`  
Kontekst: hybryda MT5 (MQL5) + Python, wymagania audytowe P0/P1 (bezpiecznie, deterministycznie, audytowalnie).

Uwaga o wersjach plikow:
- `INDEX` = to, co jest aktualnie **staged** (czyli to, co realnie “idzie do commita/release” w tej chwili).
- `WORKTREE` = to, co jest tylko w katalogu roboczym (nie-staged).

Prosze o odpowiedzi w formacie: `YES/NO/UNKNOWN + plan naprawy + dowod/test`.

## 1) P0: Spojnosc drzewa (INDEX vs WORKTREE)
W tej chwili stan repo jest mieszany: czesc poprawek jest tylko w WORKTREE, a w INDEX nadal siedza blokery P0.

Pytania:
1. Czy planujesz zrobic z tego **jeden** commit, czy rozbic na **atomowe** commity (rekomendowane dla audytu)?
2. Ktory stan jest “prawda” dla release: INDEX czy WORKTREE? (Prosze wskazac docelowy zestaw plikow i zakres.)

## 2) P0: MQL5 “utopiony w MT5” (HybridAgent + include)

### 2.1 Determinizm buildu i zaleznosci zewnetrzne
- `MQL5/Include/zeromq_bridge.mqh` opisuje wymog instalacji zewnetrznej biblioteki ZMQ + `libzmq.dll` + wlaczenie “Allow DLL imports”. (WORKTREE: linie 12-28, 33)
- `MQL5/Experts/HybridAgent.mq5` wymaga zewnetrznej biblioteki JSON (`Json/Json.mqh`). (INDEX: linie 14-19)

Pytania:
1. Jak wyglada docelowy plan releasowy dla tych zaleznosci?
2. Jesli DLL jest wymagane: gdzie jest allowlista + hash(e) i proces audytu pochodzenia DLL (dowod, ze to jest oczekiwana binarka)?

### 2.2 Kompilowalnosc HybridAgent (include path + timer)
W `INDEX` HybridAgent ma bledy, ktore powinny wywalic kompilacje/dzialanie:
- include: `#include <Include\\zeromq_bridge.mqh>` (INDEX: `MQL5/Experts/HybridAgent.mq5` linia 12) nie pasuje do repo (`MQL5/Include/zeromq_bridge.mqh`).
- timer: `InpTimerMs=1000` oraz `EventSetTimer((uint)InpTimerMs)` (INDEX: linie 26, 46). `EventSetTimer()` przyjmuje **sekundy**, nie milisekundy.

Pytania:
1. Czy HybridAgent byl kompilowany z tego repo (z INDEX), czy z lokalnych recznych poprawkach? Prosze o jednoznaczna odpowiedz.
2. Jesli docelowo ma byc 1s: czy przechodzisz na `InpTimerSec + EventSetTimer(InpTimerSec)` czy na `EventSetMillisecondTimer()`?

### 2.3 Semantyka wykonania (fill mode, deviation, multi-symbol)
HybridAgent wykonuje `OrderSend()` jako DEAL i ustawia m.in.:
- `request.type_filling = ORDER_FILLING_FOK` (WORKTREE: `MQL5/Experts/HybridAgent.mq5` linia 245)
- `request.deviation = 10` (WORKTREE: linia 246)
- twardy warunek `symbol == G_Symbol` (WORKTREE: linie 199-204) => agent dziala tylko na symbolu z wykresu

Pytania:
1. Czemu `FOK`? (W praktyce OANDA/MT5 bywa wrazliwe na fill mode; historycznie mielismy `TRADE_RETCODE_INVALID_FILL`.)
2. Skad bierze sie deviation=10? Czy to ma byc parametryzowane / zgodne z configiem systemu?
3. Jak ma dzialac trading wielosymbolowy?
4. Gdzie w MQL5 jest P0 guard “no pending orders” (jawny) + fail-safe “Python down/timeout => NO-TRADE albo CLOSE-ONLY”?
5. Jak MQL5 ma odeslac realny wynik do Pythona (ACK: ticket/retcode) zamiast “fire-and-forget”?

### 2.4 SafetyBotEA (szkielet HTTP) – czy to w ogole wchodzi do release?
`MQL5/Experts/SafetyBot/SafetyBotEA.mq5` wyglada na sandbox/szkielet i ma brakujace include’y:
- `..\..\Include\Hybrid\WebRequest.mqh` (linia 13) – brak w repo
- `..\..\Include\Hybrid\Contract.mqh` (linia 14) – brak w repo
- generowanie JSON ma bledna skladnie cudzyslowow (linie 107-114)

Pytania:
1. Czy ten EA ma byc usuniety z zakresu release, czy doprowadzony do kompilowalnej postaci?
2. Jesli ma zostac: gdzie jest kontrakt (schema) i walidacja odpowiedzi?

## 3) P0: Python – IPC, fail-safe, limity OANDA, rozdzial rol

### 3.1 ZMQ bridge: bind do `*` + syntax error w INDEX
`INDEX` ma dwa krytyczne problemy w `BIN/zeromq_bridge.py`:
- bind na wszystkie interfejsy: `tcp://*:{port}` (INDEX: linie 58 i 63)
- syntax error w `__main__`: rozbita multiline string w `print("...` (INDEX: linie 153-155)

Pytania:
1. Czy potwierdzasz, ze release ma byc **localhost-only** (`127.0.0.1`)?
2. Czemu do commita trafila wersja z syntax error (INDEX), skoro WORKTREE ma poprawke?

### 3.2 Brak kontraktu audytowego (rid, ttl, schema_version, hash) i brak ACK
Aktualna komunikacja Python->MQL5 jest “action/payload” bez:
- `schema_version`
- `rid` (request id)
- `ttl_sec` / deadline
- hash(owanie) / podpis / shared_secret
- mechanizmu `TRADE_ACK` z realnym `ticket` i `retcode`

Pytania:
1. Jaki jest docelowy kontrakt wiadomosci (pola + wersjonowanie)?
2. Jak bedzie wygladal end-to-end przeplyw `TRADE` -> `TRADE_ACK` z korelacja `rid`?
3. Jakie jest zachowanie fail-closed?
- brak odpowiedzi / timeout / invalid JSON => NO-TRADE albo CLOSE-ONLY
- ZMQ down => brak fallbacku do “direct mt5.order_send” (P0)

### 3.3 SafetyBot: hybrydowe dispatchowanie i falszywy “success”
W `WORKTREE` `SafetyBot._dispatch_order()` robi:
- dla `TRADE_ACTION_DEAL`: wysyla komende przez ZMQ i zwraca `ResultStub` z `TRADE_RETCODE_DONE` oraz dummy ticket `999999` (WORKTREE: `BIN/safetybot.py` linie 5909-5939)

Pytania:
1. Czy to jest tylko tymczasowy hack DEV? Jesli tak, jaki jest plan usuniecia stub-a?
2. Jak zapewnisz audytowalnosc evidence, skoro decision_event dostaje sztuczne `mt5_order/mt5_deal`?
3. Co sie dzieje, gdy `send_command()` zwroci `False`? (W tej chwili kod moze przejsc na fallback i wykonac zlecenie przez Python/MT5 – to jest sprzeczne z P0.)

### 3.4 “Thin Brain, Fast Reflex” – czy execution faktycznie przeniesione do MQL5?
Z obserwacji kodu:
- ZMQ tick cache jest wstrzykiwany do `ExecutionEngine.tick()` (WORKTREE: `BIN/safetybot.py` linie 3541-3556) i pozwala omijac budzet PRICE dla tick.
- HybridAgent wysyla tez BAR M5 (WORKTREE: `MQL5/Experts/HybridAgent.mq5` linie 93-120), ale Python jeszcze tego nie wykorzystuje do zastapienia `copy_rates`.
- W entry-path nadal istnieje klasyczny `ExecutionEngine.order_send()` (Python MT5 API), a hybrydowy dispatch jest osobnym torem w `SafetyBot` (nie widac jeszcze spiecia w calosciowej egzekucji strategii).

Pytania:
1. Co jest celem na “V1” hybrydy: tylko feed (tick/bar), czy rowniez execution?
2. Jesli execution ma byc w MQL5: gdzie zostana odtworzone guardy z `ExecutionEngine.order_send()` (limity, precheck, backoff, budzety, no-pending)?

### 3.5 Sprawnosc ograniczen OANDA (orders/sec, positions+pending, budzety)
W systemie sa istniejace ograniczenia OANDA (np. `OandaLimitsGuard`, budzety dzienne, limity positions+pending).

Pytania:
1. Jak zapewnisz, ze nowy tor hybrydowy nie omija:
- limitu `orders_per_sec`
- limitu `positions_pending_limit`
- `order_budget_day` i global backoff (za `TOO_MANY_REQUESTS` itd.)?
2. Czy budzety beda liczone “per request do MT5” czy “per faktyczne API OANDA”? (To trzeba jasno nazwac i udokumentowac.)

## 4) P0: Zmiany strategii / okien (20-22) – wymagaja jawnej decyzji
`INDEX` `CONFIG/strategy.json` wprowadza okno `MAIN_SESSION 08:00-22:00` z `group:null` (INDEX: linie 19-31). To zawiera zakres 20-22.

Pytania:
1. Czy 08-22 (w tym 20-22) ma byc produkcyjnie wlaczone? Jesli tak: prosze o osobny change record i osobny commit.
2. Jesli nie: czemu to jest staged w INDEX?

## 5) P0: Testy i polityki – sprzecznosci
`tests/test_no_direct_mt5_access.py` deklaruje P0 “Python nie moze importowac MetaTrader5”.  
`tests/test_system_integrity.py` deklaruje P0 “Python nie moze robic zadnych network calls”.

Pytania:
1. Ktora polityka jest docelowa?
- “brak internetu, localhost IPC OK” czy “w ogole zero socketow”?
- “Python moze uzywac MT5 API w LIVE” czy “Python to strict Decision Service, zero MT5 importow”?
2. Jesli testy maja zostac: jaki jest ich realny scope (caly runtime vs wyciety decision-service package)?

## 6) P0: Release hygiene (gates) + deterministyczne zaleznosci
Obecnie:
- doszedl `.bat` (`Aktualizuj_EA.bat`) i gate “cleanliness” to blokuje,
- `Aktualizuj_EA.bat` wskazuje na nieistniejacy EA (`Experts\\OANDA_SafetyBot_EA.mq5`, linia 25),
- `requirements.*.in` dopisaly `pyzmq`, ale locki nie sa zaktualizowane.

Pytania:
1. Czy `Aktualizuj_EA.bat` ma byc usuniety / przeniesiony do dozwolonego tooling?
2. Czy locki beda zaktualizowane (determinism), czy `pyzmq` jest tylko DEV?

## 7) Minimalny zestaw dowodow do “sign-off”
Prosze o dowody/testy (lub deterministyczny przepis) na:
1. Kompilacja EA z repo (dokladne kroki + lista zaleznosci + hash(e) DLL).
2. Lokalny bind (`127.0.0.1`) i brak zewnetrznego attack-surface.
3. Fail-safe: brak Pythona / timeout / invalid msg => NO-TRADE albo CLOSE-ONLY.
4. Brak pendingow: statyczny skan + runtime guard (MQL5 i/lub Python).
5. Spojnosc okien handlowych (jedno zrodlo prawdy) i jawna decyzja ws. 20-22.

