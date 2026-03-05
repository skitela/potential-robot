# OANDA_MT5_SYSTEM — Zasady Architektury (PL)

## Cel
Ten dokument definiuje zasady, które są nienaruszalne przy dalszym rozwoju systemu scalpingowego.

## Mapa odpowiedzialności
- **MQL5/MT5**: właściciel egzekucji (finalna decyzja wejścia/odmowy, bezpieczeństwo runtime).
- **Python**: warstwa analityczna i sterowanie wdrożeniem konfiguracji (advisory/control-plane).
- **Bridge**: transport i translacja komunikatów, bez przejmowania logiki ryzyka.
- **LAB/Shadow**: uczenie, walidacja, eksperymenty, bez prawa do bezpośredniej egzekucji.

## Zasady główne
1. **Domyślnie brak zaufania**
- Każda decyzja i każdy plik konfiguracyjny musi przejść walidację kontraktu.
- Brak walidacji = brak wdrożenia.

2. **Rozdział myśli i czynu**
- Logika analityczna nie może blokować ścieżki wejścia z ticka do zlecenia.
- MQL5 jest ostatnim bezpiecznikiem na ścieżce handlu.

3. **Twarde blokady ryzyka kapitału**
- Parametry z klasy `RISK_LOCKED_KEYS` nie są modyfikowane automatycznie.
- Każda próba naruszenia powoduje odrzucenie paczki konfiguracji.

4. **Deterministyczna ścieżka runtime**
- Decyzje runtime muszą być powtarzalne dla tych samych warunków wejściowych.
- Brak niejawnych zależności od stanu ubocznego.

5. **Minimalizacja opóźnień w hot-path**
- Blokujące operacje I/O i ciężka analityka są poza ścieżką egzekucji.
- Bridge ma być mierzalny i budżetowany (czasowo).

6. **Brak ukrywania błędów**
- Nie stosujemy wzorca `except Exception: pass`.
- Każdy błąd ma być jawnie logowany lub obsłużony kontrolowanym fallbackiem.

7. **Wersjonowanie i atomowość**
- Zmiany konfiguracji są atomowe (`tmp + fsync + replace`).
- Każda paczka ma `schema_version` i `config_hash`.

8. **Pełna ścieżka dowodowa**
- Decyzje systemu muszą zostawiać audyt (co, kiedy, dlaczego).
- Raporty i logi mają umożliwiać replay i post-mortem.

9. **Ewolucja etapowa**
- Najpierw LAB i Shadow, potem canary, potem rozszerzenie.
- Brak skoku z prototypu do pełnego live bez etapów pośrednich.

10. **Rollback jako warunek produkcyjny**
- Każdy nowy mechanizm musi mieć szybki i pewny powrót do poprzedniego stanu.

## Antywzorce (zakazane)
- Przenoszenie ciężkiej analityki do pętli tickowej.
- Zależność egzekucji od wolnych usług pomocniczych.
- „Ciche” ignorowanie błędów.
- Niespójne kontrakty danych między modułami.

## Kryterium architektoniczne „PASS”
- MQL5 zachowuje rolę runtime owner.
- Python steruje profilem i analizą, nie przejmuje egzekucji.
- Bridge nie staje się punktem blokującym decyzję.
- Każda zmiana ma test, audyt i plan rollbacku.
