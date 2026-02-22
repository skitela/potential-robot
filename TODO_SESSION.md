# TODO - Sesja 2026-02-21

## 1. Diagnostyka i Sprzątanie
- [ ] Analiza `BIN/learner_offline.py` pod kątem zapisu raportów (problem plików `.tmp`)
- [ ] Usunięcie zbędnych plików `.tmp` z katalogu `LOGS/` po potwierdzeniu poprawki
- [ ] Sprawdzenie `LOGS/learner_offline.log` w celu znalezienia błędów zapisu

## 2. Safety & Risk
- [ ] Przegląd zmian w `BIN/safetybot.py` (zgodnie z handoff)
- [ ] Weryfikacja konfiguracji w `CONFIG/risk.json` i `CONFIG/strategy.json`
- [ ] Analiza incydentów `TRADE_RETCODE_NO_MONEY` - czy risk manager powinien to wyłapać wcześniej?

## 3. Analityka Offline
- [ ] Sprawdzenie statusu `TOOLS/offline_replay_analytics.py`
- [ ] Uruchomienie testów integracyjnych dla limitów OANDA (`tests/test_oanda_limits_integration.py`)

## 4. Konsolidacja
- [ ] Commit oczekujących zmian jeśli są stabilne
- [ ] Przygotowanie nowego handoffu
