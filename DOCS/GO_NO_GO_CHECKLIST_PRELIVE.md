# OANDA_MT5_SYSTEM — GO/NO-GO Checklist (Pre-Live)

## Zasada
Brak spełnienia któregokolwiek punktu krytycznego = **NO-GO**.

## 1) Kryteria krytyczne (muszą być zielone)
1. Testy repo: `pytest tests -q` bez błędów.
2. Kompilacja MQL5 kluczowych ekspertów: `0 errors, 0 warnings`.
3. Walidacja kontraktów config (`schema_version`, `config_hash`) działa i odrzuca błędne paczki.
4. Blokady ryzyka kapitału (`RISK_LOCKED_KEYS`) są aktywne i testowane.
5. Runtime status: procesy wymagane działają, brak stale rosnących timeoutów.
6. Fallback i rollback są sprawdzone praktycznie (test przełączenia i powrotu).

## 2) Kryteria wydajnościowe
1. Bridge telemetry jest zbierane (`bridge_wait_ms`, timeout reason, command type).
2. Trade-path i heartbeat-path raportowane osobno.
3. Brak nowych blokujących etapów w hot-path.
4. Ostatni raport opóźnień nie pokazuje regresji względem poprzedniego baseline.

## 3) Kryteria operacyjne
1. Operator ma aktualny runbook uruchomienia i zatrzymania.
2. Backup + retencja + ścieżki recovery potwierdzone.
3. Aktywne alarmy i logi diagnostyczne zapisują się poprawnie.
4. Czas systemowy i strefy czasowe są spójne (UTC w artefaktach krytycznych).

## 4) Kryteria bezpieczeństwa
1. Sekrety nie są logowane wprost.
2. Narzędzia approval/deployer nie przyjmują paczek z niedozwolonymi polami.
3. Uprawnienia i dostęp do runtime są ograniczone do wymaganych kont/usług.

## 5) Decyzja
- **GO**: wszystkie kryteria krytyczne spełnione + brak czerwonych sygnałów wydajności.
- **NO-GO**: dowolny punkt krytyczny niespełniony lub brak dowodu z testu/artefaktu.

## 6) Protokół po decyzji
1. Zapisz decyzję i uzasadnienie do artefaktu audytowego.
2. Dla GO: uruchom etap canary zgodnie z limitem.
3. Dla NO-GO: utwórz listę działań naprawczych z właścicielem i terminem.
