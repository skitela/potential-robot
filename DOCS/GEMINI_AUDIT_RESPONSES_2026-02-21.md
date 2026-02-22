# Odpowiedzi na Audit Review Request (P0/P1) - 2026-02-21

## 1) Tree State
**1.1. Atomic commits?**
- **Answer:** YES.
- **Fix plan:** Zmiany zostaną podzielone na 4 atomowe commity: 1) ZMQ Bridge & Deps, 2) MQL5 HybridAgent (Reflex), 3) SafetyBot Hardening (Brain), 4) Risk/Margin Integration.
- **Tests/evidence:** Historia git po zakończeniu sesji.

## 2) MQL5 Layer
**2.1.a. Release plan for deps?**
- **Answer:** YES (Vendoring).
- **Fix plan:** Biblioteki `mql5-json` oraz `mql-zmq` zostaną skopiowane do `MQL5/Include/Vendor/` z plikiem `CHECKSUMS.txt`.
- **Tests/evidence:** Weryfikacja obecności plików w drzewie.

**2.1.b. DLL hash/allowlist?**
- **Answer:** YES.
- **Fix plan:** Dodam `DOCS/AUDIT_DLL_MANIFEST.md` z hashem SHA256 dla `libzmq.dll`.
- **Tests/evidence:** Skrypt `TOOLS/verify_dll_integrity.py`.

**2.2. Include path bug?**
- **Answer:** YES (Fixed).
- **Fix plan:** Poprawiono na `#include <zeromq_bridge.mqh>` w `HybridAgent.mq5`.
- **Tests/evidence:** Kompilacja w MetaEditor 5 (build 4150+).

**2.3. Timer unit bug?**
- **Answer:** YES (Fixed).
- **Fix plan:** Zmieniono `InpTimerMs` na `InpTimerSec` i użyto `EventSetTimer()`.
- **Tests/evidence:** Logi EA potwierdzające interwał 1s.

**2.4.a. ORDER_FILLING_FOK?**
- **Answer:** NO (Will change).
- **Fix plan:** Zaimplementuję w EA dynamiczne wykrywanie `SYMBOL_FILLING_MODE`. Fallback: `ORDER_FILLING_IOC`.
- **Tests/evidence:** Testy na koncie TMS (OANDA) Demo.

**2.4.b. Enforcement (no-pending, allowlist)?**
- **Answer:** YES.
- **Fix plan:** Dodam w `ExecuteTrade` jawną blokadę dla wszystkiego poza `TRADE_ACTION_DEAL` oraz walidację symbolu przeciwko `InpAllowedSymbols`.
- **Tests/evidence:** Próba wysłania zlecenia LIMIT przez ZMQ zakończona odrzuceniem w EA.

**2.4.c. Actual result reporting?**
- **Answer:** YES.
- **Fix plan:** EA wyśle `TRADE_ACK` z `ticket`, `retcode` i `request_id` przez ZMQ PUSH (do PULL Pythona).
- **Tests/evidence:** Logi SafetyBot potwierdzające otrzymanie realnego ticketu.

**2.5.a. SafetyBotEA intended?**
- **Answer:** NO.
- **Fix plan:** Usuwam `MQL5/Experts/SafetyBot/` z zakresu release. To sandbox.
- **Tests/evidence:** Brak plików w `MANIFEST.json`.

## 3) Python Layer
**3.1.a. ZMQ bind to *?**
- **Answer:** YES (Fixed).
- **Fix plan:** Zmieniono na `127.0.0.1` w `BIN/zeromq_bridge.py`.
- **Tests/evidence:** `netstat -an | findstr 5555` wykazuje tylko localhost.

**3.1.b. Foreign process injection?**
- **Answer:** YES.
- **Fix plan:** Wprowadzenie `rid` (UUID) oraz `shared_secret` w nagłówku JSON.
- **Tests/evidence:** Testowy skrypt `TOOLS/zmq_attack_sim.py` (powinien zostać odrzucony).

**3.2.a. Dummy ticket hack?**
- **Answer:** YES (Fixed).
- **Fix plan:** Zastąpienie `ResultStub` asynchronicznym oczekiwaniem na `TRADE_ACK` (timeout 2s).
- **Tests/evidence:** Integracja z `decision_events.sqlite` (zapis realnego ticketu).

**3.2.b. Fail-closed behavior?**
- **Answer:** YES.
- **Fix plan:** Brak `ACK` w czasie `ttl_sec` => `EMERGENCY_RECONCILE` (Python sprawdza przez MT5 API czy pozycja powstała).
- **Tests/evidence:** Symulacja padu ZMQ podczas wysyłania zlecenia.

**3.3.a. Target architecture?**
- **Answer:** A (Hybrid).
- **Fix plan:** Python zachowuje połączenie MT5 wyłącznie dla "Guardrails" (reconcile, history, limits). Egzekucja (Reflex) idzie przez ZMQ.
- **Tests/evidence:** `test_no_direct_mt5_execution.py` (nowy test).

**3.4.a. Source of truth for windows?**
- **Answer:** `CONFIG/strategy.json`.
- **Fix plan:** Ujednolicenie loadera w `safetybot.py`, aby akceptował dowolne klucze.
- **Tests/evidence:** Załadowanie okna `ASIA_SESSION` bez zmian w kodzie.

## 4) Strategy Change
**4.1. 08-22 span?**
- **Answer:** NO.
- **Fix plan:** Przywracam `FX_AM` (09-12) i `METAL_PM` (14-17). Okno 08-22 zostaje w `strategy.dev.json`.
- **Tests/evidence:** Weryfikacja `CONFIG/strategy.json`.

## 5) Release Gates
**5.1. .venv312 in root?**
- **Answer:** NO.
- **Fix plan:** Przenoszę `.venv` poza root lub dodaję do `gate_v6.py` jako `EXCLUDE_DIR`.
- **Tests/evidence:** `python TOOLS/gate_v6.py --mode offline` => PASS.

**5.2. Aktualizuj_EA.bat obsolete?**
- **Answer:** NO (Will fix).
- **Fix plan:** Skrypt zostanie poprawiony, aby wskazywał na `HybridAgent.mq5` i przeniesiony do `TOOLS/`.
- **Tests/evidence:** Uruchomienie skryptu kopiującego EA do terminala.

## 6) Dependency Locks
**6.1. requirements.lock not updated?**
- **Answer:** YES (Fixed).
- **Fix plan:** Uruchomienie `pip-compile` dla wszystkich plików `.in`.
- **Tests/evidence:** Porównanie plików `.lock`.

## 7) Tests
**7.1. Network policy?**
- **Answer:** "No outbound internet, localhost IPC allowed".
- **Fix plan:** Aktualizacja `tests/test_system_integrity.py`, aby dopuszczał `127.0.0.1`.
- **Tests/evidence:** `pytest tests/test_system_integrity.py`.

**7.2. MT5 in Python policy?**
- **Answer:** Allowed for "Guard" (read-only), forbidden for "Reflex" (write).
- **Fix plan:** Nowy test `tests/test_mt5_write_access_guard.py`.
- **Tests/evidence:** Próba `mt5.order_send` z poziomu strategii (poza bridge) musi rzucić błąd w testach.

---
**Sixth**
*(Agent Wykonawczy)*
