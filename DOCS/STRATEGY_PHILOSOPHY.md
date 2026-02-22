# Filozofia i Strategia Treningowo-Scalpingowa OANDA MT5

## 1. Cel Systemu
Nadrzędnym celem systemu jest **bezwzględne utrzymanie kapitału** przy jednoczesnym wykorzystaniu mikro-nieefektywności rynku (scalping) w celu jego systematycznego wzrostu. System operuje w modelu hybrydowym, łączącym analityczną moc Pythona z egzekucyjną szybkością MQL5.

## 2. Hierarchia Bezpieczeństwa (P0)
Bezpieczeństwo jest ważniejsze niż zysk. System stosuje wielowarstwowe bramki (Guards):
1.  **Bramka Fizyczna (USB Kill-Switch)**: Brak klucza na dedykowanym woluminie natychmiast zamyka wszystkie pozycje i zatrzymuje system.
2.  **Bramka Brokera (OANDA Limits)**: Ścisłe monitorowanie limitów "requests for price" (Appendix 3) oraz "orders per second" (Appendix 4). Przekroczenie progów ostrzegawczych wymusza tryb ECO.
3.  **Bramka Ryzyka (RiskManager)**: 
    - Dynamiczny sizing uwzględniający `margin_free`.
    - Twardy limit dziennej straty (Daily Loss Hard Cap).
    - Limit korelacji (Portfolio Heat) – zakaz nadmiernej ekspozycji na powiązane instrumenty.
4.  **Bramka Statystyczna (Learner Offline)**: Jeśli statystyki ex-post wykazują overfiting lub degradację strategii, system przechodzi w tryb pasywny.

## 3. Strategia Operacyjna: "Thin Brain, Fast Reflex"
### Brain (Python)
- **Analiza Trendu**: Wykorzystanie interwałów H4 i D1 do określenia dominującego kierunku.
- **Selekcja Instrumentów**: Ranking symboli na podstawie płynności, spreadu i historycznej skuteczności (Scout).
- **Zarządzanie Ryzykiem**: Obliczanie wolumenu i poziomów SL/TP.

### Reflex (MQL5)
- **Egzekucja**: Błyskawiczne wysyłanie zleceń bezpośrednio z terminala MT5.
- **Monitoring Ceny**: Subskrypcja ticków i barów, eliminująca opóźnienia sieciowe API.
- **Ostatnia Mila**: Walidacja warunków rynkowych w milisekundzie egzekucji.

## 4. Dyscyplina Czasowa (Trade Windows)
Handel odbywa się wyłącznie w zdefiniowanych oknach płynności:
- **FX (Scalping)**: Sesja poranna (09:00 - 12:00 PL).
- **Metale (XAU/XAG)**: Sesja popołudniowa (14:00 - 17:00 PL).
Poza tymi oknami system przechodzi w tryb **Maintenance**, zamykając pozycje i anulując zlecenia oczekujące.

## 5. Rozwój Kapitału
Wzrost kapitału realizowany jest poprzez:
- **Progresję Canary**: Nowe instrumenty lub parametry są wdrażane najpierw na minimalnym wolumenie (Canary Rollout).
- **Adaptacyjne Wyjścia**: Trailing Stop oparty na ATR oraz Partial Take-Profit w celu zabezpieczania zysków w dynamicznych warunkach rynkowych.

---
*Niniejsza filozofia stanowi fundament wszystkich decyzji algorytmicznych systemu OANDA MT5.*
