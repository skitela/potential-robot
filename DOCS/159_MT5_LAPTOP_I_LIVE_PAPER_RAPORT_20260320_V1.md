# Raport MT5 Laptop i Live Paper

Data raportu: `2026-03-20`

## 1. Cel i zakres raportu

Ten raport podsumowuje dwa równoległe światy pracy systemu:

1. `MT5` uruchomione lokalnie na laptopie, wraz z testerem strategii, kolejką weakest-first, nadzorem i warstwą analityczną.
2. `Live paper` działające na zdalnym środowisku `MetaTrader VPS / OANDA TMS`, czyli to, co dzieje się już w realnym środowisku rynkowym, ale jeszcze bez realnego kapitału.

Raport został przygotowany na podstawie lokalnych artefaktów zapisanych na dysku. Dla części `live paper` trzeba podkreślić ważne ograniczenie:

- najświeższy dostępny lokalnie snapshot `live paper` pochodzi z `2026-03-19 06:51`
- próba wykonania nowego pulla z VPS w dniu `2026-03-20` zakończyła się błędem autoryzacji `AccessDenied`

Oznacza to, że część laptopowa jest świeża, natomiast część `live paper` opisuje **ostatni dostępny stan zsynchronizowany lokalnie**, a nie nowy odczyt z tej chwili.

## 2. Stan lokalny MT5 na laptopie

### 2.1. Bieżący układ procesów

W momencie sporządzania raportu lokalne laboratorium pracowało na dwóch instancjach terminala:

- `terminal64` OANDA TMS MT5, który utrzymuje główną warstwę brokerską
- `terminal64` MetaTrader 5 dla wtórnego pasa testowego
- `metatester64` dla wtórnego przebiegu testera strategii

Najświeższy snapshot operatorski pokazuje:

- `metatester64` aktywny, priorytet `AboveNormal`
- `terminal64` OANDA aktywny, priorytet `AboveNormal`
- `terminal64` MetaTrader 5 aktywny, priorytet `AboveNormal`

### 2.2. Co robi teraz lokalny tester MT5

Najświeższy status testera:

- stan: `running`
- instrument: `SILVER`
- `run_stamp`: `20260320_151312`
- ostatni potwierdzony progress: `18%`
- ostatnia linia progressu:
  - `PS  0  16:13:40.858  AutoTesting  processing 18 %`

To oznacza, że wtórny tester nie jest obecnie martwy ani zastały, tylko aktywnie liczy nowy przebieg dla `SILVER`.

### 2.3. Co zdążyło się zakończyć w weakest-first batch

W aktualnym batchu weakest-first najnowszy raport pokazuje:

- `SILVER`: `timed_out`
- `NZDUSD`: `successfully_finished`, czas `0:06:23.925`
- `GBPJPY`: `successfully_finished`, czas `0:42:37.287`
- `DE30`: `successfully_finished`, czas `0:04:40.060`
- `GOLD`: `successfully_finished`, czas `0:25:25.817`

W praktyce oznacza to:

- `SILVER` pozostaje najcięższym instrumentem i dalej wymaga osobnego, cierpliwego traktowania

### 2.4. Najważniejsze obserwacje z laptopowego weakest-first

Aktualna kolejka weakest-first wygląda następująco:

1. `SILVER`
2. `NZDUSD`
3. `GBPJPY`
5. `GOLD`
6. `EURAUD`

Interpretacja tej kolejki:

- `SILVER` jest teraz głównym problemem i jednocześnie głównym obiektem pracy
- `NZDUSD` i `GBPJPY` nadal cierpią głównie na małą próbkę i słaby materiał, a nie na prosty błąd wejścia
- `GOLD` ma aktywny problem z `FOREFIELD_DIRTY` i reprezentatywnością kosztu

### 2.5. Warstwa ML i wskazówki dla instrumentów

Najświeższy model offline ma nadal stabilne, sensowne metryki:

- `accuracy = 0.7602`
- `balanced_accuracy = 0.7991`
- `roc_auc = 0.8752`

Najmocniejsze aktywne podpowiedzi ML:

- `SILVER`: symbol ma negatywny profil
- `NZDUSD`: aktualny `SETUP_RANGE` jest negatywny
- `GBPJPY`: aktualny `SETUP_RANGE` jest negatywny

To oznacza, że lokalna warstwa ML:

- nie daje jeszcze gotowego automatycznego sterowania
- ale już dobrze wspiera decyzje o tym, które instrumenty ciąć, które dociągać danymi, a które zostawić w obserwacji

### 2.6. Problemy i audyt po stronie lokalnego MT5

Najświeższy audyt `trust-but-verify` pokazuje:

- werdykt: `RECHECK_REQUIRED`
- potrzebne ręczne spojrzenie: `True`

Powód nie jest ogólnym chaosem, tylko konkretną niespójnością:

- plik `mt5_retest_queue_latest.json` jest stary
- kolejka retestów nadal twierdzi, że jest `running`, ale nie wskazuje poprawnie bieżącego symbolu
- faktyczna prawda o teście pochodzi obecnie z watchera `mt5_tester_status_latest.json`

Najważniejszy wniosek:

- lokalny tester pracuje
- ale warstwa starej kolejki retestów nie została jeszcze do końca uporządkowana po wcześniejszych zawieszeniach i wymaga dalszego sprzątania

### 2.7. Dane historyczne na laptopie i wpływ na pracę

Najświeższy snapshot pokazuje, że lokalny ślad `QDM History` ma około:

- `63.852 GB`

Największe zbiory historyczne w `QDM`:

- `EURJPY`: `8331.64 MB`
- `GBPJPY`: `7448.98 MB`
- `XAUUSD`: `6261.84 MB`
- `EURAUD`: `5976.80 MB`
- `USDJPY`: `5859.56 MB`
- `EURUSD`: `5824.18 MB`
- `GBPUSD`: `5179.61 MB`

W trakcie dzisiejszego przeglądu ujawniono ważny problem:

- weakest-sync `QDM` potrafił zbyt często odpalać ponowne pełne aktualizacje historii
- logi pokazały, że dla symboli takich jak `NZDUSD` ponownie pobierane były szerokie zakresy danych od lat historycznych aż po bieżący rok

W efekcie wprowadzono już poprawkę:

- throttling per-symbol (`24h`)
- minimalny odstęp między uruchomieniami weakest-sync (`6h`)

To była istotna naprawa, bo bez niej system niepotrzebnie obciążał:

- dysk
- transfer
- czas pracy `QDM`
- i całą pętlę operacyjną laptopa

## 3. Stan live paper na serwerze / VPS

### 3.1. Najważniejsze ograniczenie raportowe

W tej chwili nie mamy świeżego porannego pulla z VPS, ponieważ próba połączenia zakończyła się błędem:

- `New-PSSession ... AccessDenied`

Dlatego poniższa sekcja opisuje:

- **ostatni dostępny zsynchronizowany stan `live paper`**
- a nie nowy stan pobrany w chwili przygotowania tego raportu

### 3.2. Ostatni dostępny snapshot runtime 24h

Najświeższy dostępny lokalnie kompakt runtime 24h ma:

- wygenerowano lokalnie: `2026-03-19 06:51:37`
- okno: `2026-03-18 06:51:37` -> `2026-03-19 06:51:37`

Główne parametry:

- `opens = 533`
- `closes = 532`
- `wins = 153`
- `losses = 349`
- `neutral = 30`
- `net = -528.92`
- `active_instruments = 5`
- `heartbeat_count = 27`

Wniosek:

- `live paper` w tym oknie było wyraźnie ujemne
- przewaga strat nad zyskami była duża
- problem nie leżał w samej łączności, bo latency i heartbeat wyglądały zdrowo

### 3.3. Jakość połączenia i hosting

Ostatni stan hostingu MT5 pokazuje:

- środowisko: `17 wykresy, 17 eksperci`
- ostatnia migracja: `2026.03.18 07:55`
- hosting: `VPS Warsaw 01`
- ping hostingu: około `1.80 ms`

To oznacza, że:

- środowisko `paper/live` było aktywne
- migracja ekspertów na VPS odbyła się
- problem wyników nie wynikał z ewidentnego problemu sieciowego lub niedziałającego hostingu

### 3.4. Które instrumenty naprawdę pracowały na live paper

W ostatnim dostępnym oknie 24h aktywnie pracowało `5` instrumentów:

1. `US500`
   - `opens = 178`
   - `wins = 51`
   - `losses = 113`
   - `net = -39.08`
   - trust: `PAPER_CONVERSION_BLOCKED`
   - cost: `LOW`

2. `GOLD`
   - `opens = 138`
   - `wins = 51`
   - `losses = 81`
   - `net = -35.95`
   - trust: `FOREFIELD_DIRTY`
   - cost: `HIGH`

3. `DE30`
   - `opens = 105`
   - `wins = 29`
   - `losses = 74`
   - `net = -135.07`
   - trust: `PAPER_CONVERSION_BLOCKED`
   - cost: `HIGH`

4. `SILVER`
   - `opens = 96`
   - `wins = 20`
   - `losses = 69`
   - `net = -169.47`
   - trust: `PAPER_CONVERSION_BLOCKED`
   - cost: `HIGH`

   - `opens = 16`
   - `wins = 2`
   - `losses = 12`
   - `net = -149.35`
   - trust: `PAPER_CONVERSION_BLOCKED`
   - cost: `NON_REPRESENTATIVE`

Najbardziej uderzający obraz:

- `GOLD` i `US500` były mniej złe, ale nadal ujemne
- metale i indeksy były w tym oknie wyraźnie trudniejsze niż większość instrumentów FX

### 3.5. Co działo się z pozostałymi instrumentami

Wiele istotnych symboli nie otworzyło żadnych pozycji w ostatnim widocznym oknie, mimo że pozostawały w systemie jako monitorowane:

- `COPPER-US`
- `EURUSD`
- `GBPJPY`
- `GBPUSD`
- `NZDUSD`
- `USDCAD`
- `USDCHF`

To oznacza, że te instrumenty:

- były obecne w logice
- ale nie przebiły się do realnego ruchu w paper runtime
- albo zostały zatrzymane przez trust/cost/sample

### 3.6. Najważniejsze blokady live paper

W 24h runtime dominowały trzy grupy problemów:

#### Trust / konwersja

- `PAPER_CONVERSION_BLOCKED`: `14`
- `LOW_SAMPLE`: `2`
- `FOREFIELD_DIRTY`: `1`

#### Koszt

- `HIGH`: `10`
- `NON_REPRESENTATIVE`: `6`
- `LOW`: `1`

#### Reżim rynku

- `CHAOS`: dominujący
- `BREAKOUT`: także obecny

Interpretacja:

- system nie cierpiał przede wszystkim na brak sygnałów
- cierpiał przede wszystkim na to, że sygnały nie przechodziły czysto przez warstwę `candidate -> paper`, koszt i reprezentatywność

### 3.7. Ostrzeżenia z VPS

W warningach pojawiły się m.in.:

- chwilowe rozłączenie z `OANDATMS-MT5`
- standardowe zatrzymanie terminala po migracji
- błąd pobrania listy sygnałów

Nie wygląda to na główną przyczynę straty netto, ale pokazuje, że warstwa serwerowa także wymaga regularnego, świeżego pulla i kontroli.

## 4. Porównanie: laptop vs live paper

### 4.1. Co laptop widzi lepiej

Laptop daje nam dziś:

- świeży obraz weakest-first
- lokalny tester `MT5` z aktywnym `SILVER`
- warstwę `ML`
- warstwę `QDM`
- audyt jakości procesu

Laptop dobrze pokazuje:

- które instrumenty są blisko poprawy
- które są ciężkie kosztowo
- które wymagają większej próbki
- które są toksyczne na poziomie setupów

### 4.2. Co live paper mówi mocniej niż laptop

`Live paper` jest ważniejsze od offline, bo pokazuje:

- prawdziwy koszt
- prawdziwy rytm rynku
- prawdziwą konwersję do wejść
- prawdziwy wynik netto

To właśnie `live paper` jasno pokazało, że:

- `US500` i `GOLD` generowały ruch, ale nie zysk
- wiele FX było bardziej blokowane niż aktywne

### 4.3. Co jest dziś zgodne między obiema warstwami

Najważniejsza zgodność:

- `SILVER` jest problematyczne i na `live paper`, i lokalnie
- `NZDUSD` i `GBPJPY` nadal potrzebują przede wszystkim próbki i danych, a nie brutalnego strojenia wejścia
- `GOLD` wymaga naprawy kosztu i foregroundu
- warstwa `candidate -> paper` pozostaje jednym z kluczowych wąskich gardeł systemu

## 5. Najważniejsze wnioski końcowe

1. Lokalny `MT5` na laptopie działa i faktycznie prowadzi bieżący retest `SILVER`.
3. `SILVER` pozostaje najtrudniejszym instrumentem w całym układzie.
4. `Live paper` w ostatnim dostępnym oknie 24h było wyraźnie ujemne: `-528.92`.
6. Najważniejsze blokady nie wynikają tylko z kierunku rynku, ale z połączenia:
   - kosztu
   - reprezentatywności
   - małej próbki
   - i zacięć w `candidate -> paper`
7. Po stronie danych `QDM` wykryto zbyt agresywne ponowne odświeżanie szerokiej historii i wdrożono throttling.
8. Warstwa audytu lokalnego działa lepiej niż wcześniej, ale nadal wykazuje stary problem ze starym plikiem kolejki retestów.
9. Najważniejsza luka operacyjna na tę chwilę:
   - brak świeżego pulla z VPS z dnia `2026-03-20`
   - bez tego widzimy lokalną prawdę bardzo dobrze, ale paper/live tylko z ostatniego dostępnego snapshotu

## 6. Rekomendacja na następny krok

Najbardziej sensowna kolejność dalszej pracy:

1. odzyskać świeży pull `live paper` z VPS
2. utrzymać bieżący retest `SILVER` do końca
3. po domknięciu retestu porównać:
   - `SILVER local tester`
   - `SILVER live paper`
   - `SILVER ML hints`
4. dalej zawężać aktywny roster paper/live zamiast równo ciągnąć wszystkie instrumenty
5. utrzymać zasadę:
   - najpierw czystość laptopa i lokalnych artefaktów
   - dopiero potem kolejna migracja na VPS
