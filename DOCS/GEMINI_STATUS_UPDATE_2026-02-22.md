# List do Gemini - status prac i decyzje architektoniczne

Data: 2026-02-22  
Repo: `C:\OANDA_MT5_SYSTEM`  
Branch: `audit/oanda_tms_live_execution_hardening`  
Commit checkpoint: `d6c2bf6` (`chore: save current workspace changes`)

## Co zostalo wykonane

1. Zapisano i zacommitowano pelny stan workspace (31 plikow, +1955 / -105).
2. Utrwalono kierunek hybrydowy Python + MQL5:
   - dodano/uzupelniono komponenty `MQL5/Experts/HybridAgent.mq5`, `MQL5/Include/zeromq_bridge.mqh`, `MQL5/Experts/SafetyBot/SafetyBotEA.mq5`,
   - utrwalono warstwe mostu IPC (`BIN/zeromq_bridge.py`) oraz powiazania po stronie Python.
3. Dopracowano elementy operacyjne i ryzyka:
   - zmiany w `BIN/safetybot.py`, `BIN/risk_manager.py`, `BIN/infobot.py`, `BIN/repair_agent.py`, `BIN/scudfab02.py`, `BIN/learner_offline.py`,
   - aktualizacja parametrow strategii (`CONFIG/strategy.json`).
4. Dospinano hygiene i testy:
   - zmiany w `TOOLS/dependency_hygiene.py`, `TOOLS/offline_analytics_cycle.py`, `TOOLS/offline_replay_analytics.py`,
   - uzupelnienie lockow zaleznosci (`requirements.live.lock`, `requirements.offline.lock`) o `pyzmq`,
   - aktualizacja testow (`tests/test_no_direct_mt5_access.py`, `tests/test_scud_advice_contract_inmem.py`) i dodanie testu integralnosci (`tests/test_system_integrity.py`).
5. Walidacja po zmianach:
   - uruchomiono pelny zestaw testow `python -m unittest discover -s tests -p 'test_*.py' -v`,
   - wynik: `OK` (177 testow).

## Decyzja nieodwracalna

Decyzja wlascicielska jest jawna i ostateczna:

- Przeniesienie czesci logiki wykonawczej do MQL5 jest nieodwracalne.
- Nie wracamy do modelu "Python-only execution path".
- Dalsze rekomendacje maja zakladac utrzymanie i hardening obecnego modelu hybrydowego, bez propozycji rollbacku tej decyzji.

## Oczekiwanie wobec Gemini

Prosze o kolejne rekomendacje tylko w tym zakresie:

1. hardening kontraktu Python <-> MQL5 (ACK, timeouty, idempotencja, retry),
2. obserwowalnosc i audytowalnosc (metryki, logi, dowody wykonania),
3. bezpieczenstwo i fail-safe (degradacja kontrolowana, brak transakcji przy utracie synchronizacji),
4. stabilnosc operacyjna pod OANDA TMS MT5.

