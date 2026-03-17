# 41. EURUSD - plan kolejnych zmian

## Cel
Doprowadzić `EURUSD` do stanu, w którym:
- ogranicza słabe wejścia w `BREAKOUT` i `CHAOS`,
- zmniejsza liczbę zamknięć typu `PAPER_TIMEOUT`,
- utrzymuje bardzo niską latencję,
- poprawia wynik netto bez utraty ochrony kapitału.

## Stan wyjściowy
Na podstawie ostatniego ciężkiego audytu:
- mechanika runtime jest stabilna,
- uczenie `v2` jest czyste,
- warstwa `AUX` działa już poprawniej,
- największy problem siedzi w jakości decyzji, nie w samej architekturze.

Najbardziej problematyczne buckety:
- `SETUP_TREND / BREAKOUT`
- `SETUP_BREAKOUT / TREND`
- `SETUP_BREAKOUT / RANGE`
- `SETUP_BREAKOUT / CHAOS`

Najbardziej obiecujące buckety:
- `SETUP_REJECTION / RANGE`
- `SETUP_TREND / TREND`

## Plan zmian

### Krok 1. Ograniczyć wejścia trendowe w środowisku breakout-chaos
Cel:
- zmniejszyć liczbę słabych wejść, które kończą się `PAPER_TIMEOUT` albo stratą.

Zakres:
- osłabić dopuszczanie `SETUP_TREND`, gdy:
  - `market_regime = BREAKOUT` i confidence jest niskie,
  - `market_regime = CHAOS`,
  - spread nie jest `GOOD`.

Oczekiwany efekt:
- mniej wejść o niskiej jakości,
- wyższy udział sytuacji, w których rynek daje kontynuację po wejściu.

### Krok 2. Zmienić logikę timeout dla słabych wejść
Cel:
- nie trzymać pozycji paper zbyt długo, jeśli rynek od początku nie potwierdza wejścia.

Zakres:
- dodać prosty warunek "brak postępu po wejściu",
- szybciej zamykać słabe wejścia zamiast czekać na pełny `PAPER_TIMEOUT`,
- oznaczać takie przypadki osobnym, czytelnym powodem zamknięcia.

Oczekiwany efekt:
- czystszy materiał do uczenia,
- mniej strat z wejść, które od początku nie miały paliwa.

### Krok 3. Osłabić wpływ confidence, gdy wynik netto nadal jest słaby
Cel:
- nie dopuszczać do zbyt dużej pewności siebie, gdy runtime nadal przegrywa.

Zakres:
- dodać delikatny hamulec confidence powiązany z:
  - ujemnym `realized_pnl_day`,
  - serią strat,
  - słabymi bucketami dominującymi.

Oczekiwany efekt:
- mniej sytuacji, w których bot uważa się za gotowego mimo słabego realnego wyniku.

### Krok 4. Wydobyć większą wartość z Renko i świec
Cel:
- sprawić, żeby warstwa pomocnicza była bardziej użyteczna, a nie tylko poprawna technicznie.

Zakres:
- sprawdzić, czy progi `Renko` nie są zbyt ostre,
- sprawdzić, czy warstwa świec nie daje zbyt wielu słabych `FAIR/POOR`,
- jeśli trzeba, lekko przesunąć progi jakości bez rozbudowywania logiki.

Oczekiwany efekt:
- więcej realnych sygnałów wspierających decyzję,
- mniej przypadków `AUX_INCONCLUSIVE`.

### Krok 5. Uporządkować diagnostykę latencji
Cel:
- odróżnić prawdziwe koszty hot-path od artefaktów restartu, bezczynności i opóźnionych zdarzeń.

Zakres:
- odseparować profil bieżący od pełnego kumulacyjnego,
- oznaczać skrajne skoki jako artefakty środowiskowe,
- nie traktować restartów jako kosztu decyzji strategii.

Oczekiwany efekt:
- bardziej uczciwy obraz latencji runtime,
- lepsza podstawa do dalszego strojenia bez fałszywych alarmów.

## Dlaczego nie wdrażać wszystkiego od razu
Nie wdrażamy wszystkiego jednocześnie, bo:
- kilka zmian naraz zaciera związek przyczyna-skutek,
- łatwo poprawić jeden bucket kosztem innego i tego nie zauważyć,
- przy złożonym bocie trzeba widzieć, która regulacja naprawdę pomogła,
- im więcej zmian na raz, tym większe ryzyko powrotu ukrytych błędów i szumu.

W praktyce:
- najpierw jedna zmiana,
- potem obserwacja,
- potem kolejna.

To jest wolniejsze, ale dużo bardziej wiarygodne.

## Kolejność wdrożenia
1. Krok 1
2. obserwacja
3. Krok 2
4. obserwacja
5. Krok 3
6. obserwacja
7. Krok 4
8. obserwacja
9. Krok 5

## Definicja sukcesu
Za sukces uznajemy sytuację, w której:
- maleje udział bucketów breakoutowych stratnych,
- maleje liczba `PAPER_TIMEOUT`,
- rośnie udział bucketów neutralnych lub dodatnich,
- wynik netto przestaje systemowo schodzić w dół,
- latencja nie traci swojej lekkości.

## 2026-03-13 - wdrozenie Kroku 1

Krok 1 zostal wdrozony tylko do `EURUSD`.

Zakres wykonanej zmiany:
- `SETUP_TREND` dostal dodatkowy podatek jakosciowy, gdy:
  - `spread_regime = CAUTION`
  - `market_regime = BREAKOUT`
  - `market_regime = CHAOS`
  - warstwa pomocnicza `AUX` nie wspiera kierunku bazowego sygnalu
- podatek jest lekki i sklada sie z:
  - obnizenia `confidence_score`
  - lekkiego zmniejszenia `risk_multiplier`
  - lekkiego podniesienia `trigger_abs`

Cel wdrozenia:
- odciac czesc slabszych wejsc `SETUP_TREND` w trudnym srodowisku
- nie rozwalic lekkosci runtime
- zostawic czysta mozliwosc obserwacji przyczyna-skutek

Status po wdrozeniu:
- kod zostal skompilowany poprawnie
- `MT5` zostal przeladowany
- dalsze dzialanie wymaga teraz spokojnej obserwacji, bez dokladania kolejnych zmian naraz
