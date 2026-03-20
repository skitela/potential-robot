# 160 Sharp Learning Stack And VPS Audit 2026-03-20 V1

## Cel

Ten raport domyka ostry audyt warstwy uczenia na laptopie oraz lacznosci z `VPS / live paper`.

Zakres:
- sprawdzenie lacznosci `VPS`
- sprawdzenie, czy laptop realnie uczy sie z danych kupionych w `QDM`
- sprawdzenie, czy zbyt czeste pobieranie danych blokowalo dysk i pętlę
- usuniecie zbędnych warstw artefaktow
- potwierdzenie, że po sprzataniu `refresh` i `ML training` dalej dzialaja
- raport stanu wszystkich `17` instrumentow

## Co zostalo sprawdzone

Przeglad byl wykonany w kilku przejsciach:
- pierwszy przeglad: stan `VPS`, `QDM`, `research`, `MT5`, `ML`
- drugi przeglad: naprawa warstwy uczenia i redukcja artefaktow
- trzeci przeglad: walidacja po naprawie przez `refresh` oraz ponowny trening modelu

To byl celowy tryb `trust but verify`, a nie pojedynczy szybki odczyt.

## 1. VPS / live paper

### Stan lacznosci

Aktualny test z laptopa:
- `TCP 5985`: `OK`
- `Test-WSMan`: `OK`
- `New-PSSession`: `AccessDenied`

Aktualny raport:
- [test_vps_winrm_auth_report.json](C:\OANDA_MT5_SYSTEM\EVIDENCE\test_vps_winrm_auth_report.json)
- [test_vps_remote_channels_20260320T154459Z.json](C:\OANDA_MT5_SYSTEM\EVIDENCE\vps_remote_admin\test_vps_remote_channels_20260320T154459Z.json)

Wniosek:
- siec do `VPS` dziala
- `WinRM` odpowiada
- blocker siedzi w autoryzacji `Administrator / WinRM`, nie w sieci

To oznacza, że dzisiaj nie bylo mozliwe wykonanie nowego `pull` z serwera i najnowsza lokalna prawda o `live paper` nadal pochodzi z ostatniego dostepnego snapshotu:
- okno runtime: `2026-03-18 06:51:37 -> 2026-03-19 06:51:37`
- `net = -528.92`

### Co trzeba zrobic, zeby odzyskac swiezy feedback z serwera

Najkrotsza sciezka:
1. wejsc na `VPS` przez `RDP`
2. zweryfikowac konto `Administrator`
3. w razie potrzeby ustawic nowe haslo
4. przepieczetowac lokalny sekret `DPAPI`
5. ponowic test `TEST_VPS_WINRM_AUTH.ps1`

Bez tego nie ma uczciwego, swiezego `pull feedback -> analiza -> push`.

## 2. Co bylo zle w warstwie uczenia na laptopie

### Problem 1: `QDM` pobieralo zbyt czesto

Przed naprawa weakest-sync mogl odpalac szerokie `update` zbyt czesto.

Twardy objaw:
- kolejne logi weakest-sync pojawialy sie co kilkanascie minut
- `QDM` potrafil ponownie sciagac szeroki zakres historii dla tych samych symboli

To bylo juz wczesniej naprawione przez:
- `24h` cooldown per symbol
- `6h` minimalny odstep miedzy weakest-sync

Pliki:
- [SYNC_QDM_FOCUS_PACK.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\SYNC_QDM_FOCUS_PACK.ps1)
- [START_QDM_WEAKEST_SYNC_BACKGROUND.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_QDM_WEAKEST_SYNC_BACKGROUND.ps1)

### Problem 2: warstwa danych do uczenia byla zdublowana

Przed sprzataniem sytuacja wygladala tak:
- `QDM raw history`: `69.024 GB`
- `QDM export CSV`: `32.867 GB`
- `research CSV`: `2.18 GB`
- `research parquet`: `0.639 GB`
- `research duckdb`: `1.855 GB`

To oznaczalo, że obok surowych danych trzymalismy jeszcze bardzo ciezkie warstwy pomocnicze:
- trzy ogromne eksporty `MB_*.csv`
- dwa wielkie `CSV` research:
  - `candidate_signals_latest.csv`
  - `decision_events_latest.csv`

### Problem 3: uczenie korzystalo z `QDM`, ale tylko czesciowo

Model nie byl slepy na `QDM`, ale pokrycie bylo tylko dla:
- `EURUSD`
- `USDJPY`
- `GBPUSD`

Czyli kupione dane juz pracowaly, ale jeszcze nie na cala flotę.

## 3. Co zostalo naprawione

### Naprawa A: `research export` potrafi teraz zyc bez ciezkich `QDM CSV`

Plik:
- [EXPORT_MT5_RESEARCH_DATA.py](C:\MAKRO_I_MIKRO_BOT\TOOLS\EXPORT_MT5_RESEARCH_DATA.py)

Zmiany:
- `qdm_minute_bars` potrafi odbudowac sie z lokalnego cache `parquet`, nawet gdy w `QDM_EXPORT\MT5` nie ma juz `MB_*.csv`
- `decision_events` i `candidate_signals` sa eksportowane juz jako `parquet-only`
- stare duze `CSV` sa usuwane przy odswiezeniu research

Praktyczny efekt:
- uczenie nie musi juz trzymac ciezkich eksportow `CSV`, zeby dzialac dalej

### Naprawa B: dodany ostry audyt warstwy uczenia

Nowy audyt:
- [BUILD_LEARNING_STACK_AUDIT.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_LEARNING_STACK_AUDIT.ps1)

Raport:
- [learning_stack_audit_latest.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\learning_stack_audit_latest.md)

Audyt pokazuje:
- ile zajmuje `QDM raw history`
- ile zajmuje `QDM export`
- ile zajmuje `research parquet`
- ile zajmuje `duckdb`
- czy model faktycznie widzi cechy `QDM`
- dla których symboli jest realne pokrycie `QDM`

### Naprawa C: dodany skrypt normalizacji artefaktow uczenia

Nowy skrypt:
- [NORMALIZE_LEARNING_ARTIFACT_LAYERS.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\NORMALIZE_LEARNING_ARTIFACT_LAYERS.ps1)

Jego rola:
- usuwa redundantne `QDM export CSV`, jesli cache `parquet` juz istnieje
- usuwa duze redundantne `research CSV`, jesli istnieje bezpieczny odpowiednik `parquet`

### Naprawa D: rotacja ciezkich logow runtime

Zrotowany zostal ciezki journal:
- `PLATIN incident_journal.jsonl`
- rozmiar: `555.518 MB`

To zmniejsza brud operacyjny i odciaza pętlę audytowa.

## 4. Stan po naprawie

### Aktualna architektura warstw danych do uczenia

Po sprzataniu stan jest taki:
- `QDM raw history`: `69.024 GB`
- `QDM export CSV`: `0 GB`
- `QDM cache parquet`: `0.595 GB`
- `research CSV`: `0 GB` w warstwie duzych zbiorow
- `research parquet`: `0.687 GB`
- `research duckdb`: `2.012 GB`

Wniosek:
- zostala jedna kanoniczna warstwa pobranych danych sieciowych:
  - `QDM raw history`
- do uczenia zostaly lekkie warstwy lokalne:
  - `QDM cache parquet`
  - `research parquet`
  - `research duckdb`

To jest dokladnie ten kierunek, o ktory chodzilo:
- jedna warstwa surowa
- reszta jako lekkie warstwy przetworzone do analizy

### Ile miejsca udalo sie odzyskac

Na podstawie audytu przed/po:
- `QDM export CSV`: z `32.867 GB` do `0 GB`
- `research CSV`: z `2.18 GB` do praktycznie `0 GB` dla duzych zbiorow

Lacznie odzyskano okolo:
- `35.0 GB`

### Czy po sprzataniu uczenie nadal dziala

Tak. To zostalo potwierdzone dwoma testami:

1. `refresh research`
- [REFRESH_MICROBOT_RESEARCH_DATA.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\REFRESH_MICROBOT_RESEARCH_DATA.ps1)
- przeszedl poprawnie bez obecnosci `QDM export CSV`

2. `ML training`
- [TRAIN_MICROBOT_ML_STACK.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\TRAIN_MICROBOT_ML_STACK.ps1)
- przeszedl poprawnie po sprzataniu

To jest najwazniejsze technicznie potwierdzenie:
- warstwa uczenia nie opiera sie juz na przypadkowo zostawionych wielkich eksportach `CSV`

## 5. Czy system rzeczywiscie uczy sie na podstawie tych baz danych

Tak, ale czesciowo.

### Twarde potwierdzenie

Aktualne metryki modelu:
- [paper_gate_acceptor_metrics_latest.json](C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor\paper_gate_acceptor_metrics_latest.json)

Po ostatnim refreshu i treningu:
- `total_rows = 6,393,877`
- `qdm_rows_with_coverage = 263,969`
- `qdm_coverage_ratio = 0.041285`

To oznacza:
- model rzeczywiscie widzi dane `QDM`
- ale pokrycie `QDM` jest jeszcze tylko dla czesci floty

### Dla jakich symboli `QDM` realnie pracuje w modelu

Na teraz:
- `EURUSD`
- `USDJPY`
- `GBPUSD`

### Jakie cechy `QDM` sa realnie widoczne w modelu

W aktualnym modelu widoczne sa m.in.:
- `qdm_data_present`
- `qdm_spread_mean`
- `qdm_spread_max`
- `qdm_mid_range_1m`
- `qdm_mid_return_1m`
- `qdm_tick_count`

Czyli odpowiedz jest uczciwa:
- `tak`, system uczy sie na podstawie kupionych baz danych
- ale `nie`, jeszcze nie dla wszystkich instrumentow

## 6. Jak dziala uczenie maszynowe na laptopie

Przeplyw jest teraz taki:

1. `MT5` i mikroboty zapisują:
- `candidate_signals`
- `decision_events`
- `execution_summary`
- artefakty testera

2. `QDM` dostarcza surowa historie rynku.

3. `EXPORT_MT5_RESEARCH_DATA.py` buduje z tego:
- `qdm_minute_bars_latest.parquet`
- `candidate_signals_latest.parquet`
- `decision_events_latest.parquet`
- `microbot_research.duckdb`

4. `TRAIN_PAPER_GATE_ACCEPTOR_MODEL.py` laczy:
- dane runtime/testera
- dane `QDM`

5. Python trenuje model i zapisuje:
- `joblib`
- `onnx`
- `metrics`

To znaczy:
- model uczy sie offline na laptopie
- `ONNX` jest produktem wytrenowanego modelu
- runtime `MQL5` jeszcze nie korzysta z niego bezposrednio

## 7. Stan lokalnego MT5 testera

Aktualny status:
- [mt5_tester_status_latest.json](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_tester_status_latest.json)

Na chwile raportu:
- `state = running`
- `current_symbol = SILVER`
- `latest_progress_pct = 22`
- `run_stamp = 20260320_151312`

To oznacza:
- tester na laptopie dalej pracuje
- aktualnie glownym ciezkim przypadkiem pozostaje `SILVER`

## 8. Raport wszystkich instrumentow

Stan na podstawie:
- [profit_tracking_latest.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\profit_tracking_latest.md)
- [tuning_priority_latest.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\tuning_priority_latest.md)

Uwaga:
- `live paper` dalej opiera sie na ostatnim dostepnym pullu z `2026-03-19`, bo swiezy `WinRM` pull jest zablokowany

### Pelna flota

| Instrument | Status | Live opens 24h | Live net 24h | Best tester pnl | Co z nim robic |
|---|---:|---:|---:|---:|---|
| `NZDUSD` | `NEGATIVE` | 0 | 0.00 | -9.03 | powiekszyc probke i dane historyczne, bez strojenia sygnalu |
| `GBPJPY` | `NEGATIVE` | 0 | 0.00 | -12.88 | powiekszyc probke i dane historyczne, bez strojenia sygnalu |
| `SILVER` | `NEGATIVE` | 96 | -169.47 | 0.00 | uderzyc jednoczesnie w live runtime i candidate-to-paper contract |
| `PLATIN` | `NEGATIVE` | 0 | -149.35 | 0.00 | powiekszyc probke i dane historyczne, bez strojenia sygnalu |
| `DE30` | `NEGATIVE` | 0 | -135.07 | 0.00 | naprawic reprezentatywnosc kosztu i zrodlo danych |
| `GOLD` | `NEGATIVE` | 138 | -35.95 | -31.81 | naprawic reprezentatywnosc kosztu i zrodlo danych |
| `COPPER-US` | `NEAR_PROFIT` | 0 | 0.00 | -0.01 | naprawic reprezentatywnosc kosztu i zrodlo danych |
| `GBPAUD` | `NEGATIVE` | 0 | 0.00 | 0.00 | naprawic reprezentatywnosc kosztu i zrodlo danych |
| `EURAUD` | `NEGATIVE` | 0 | 0.00 | 0.00 | utrzymac obserwacje i przygotowac kolejny tester batch |
| `GBPUSD` | `NEGATIVE` | 0 | 0.00 | -13.22 | utrzymac obserwacje i przygotowac kolejny tester batch |
| `USDJPY` | `NEAR_PROFIT` | 0 | 0.00 | -4.90 | naprawic reprezentatywnosc kosztu i zrodlo danych |
| `US500` | `NEGATIVE` | 178 | -39.08 | -63.97 | oczyscic foreground i brudne kandydaty przed tuningiem sygnalu |
| `AUDUSD` | `NEAR_PROFIT` | 0 | 0.00 | -3.30 | utrzymac obserwacje i przygotowac kolejny tester batch |
| `EURJPY` | `NEGATIVE` | 0 | 0.00 | -32.22 | utrzymac obserwacje i przygotowac kolejny tester batch |
| `USDCHF` | `NEGATIVE` | 0 | 0.00 | -9.56 | utrzymac obserwacje i przygotowac kolejny tester batch |
| `USDCAD` | `NEAR_PROFIT` | 0 | 0.00 | -2.36 | utrzymac obserwacje i przygotowac kolejny tester batch |
| `EURUSD` | `NEGATIVE` | 0 | 0.00 | -6.97 | utrzymac obserwacje i przygotowac kolejny tester batch |

### Najwazniejsze wnioski z pelnej floty

Najslabsze:
- `SILVER`
- `PLATIN`
- `DE30`
- `GOLD`

Najblizej dodatniosci lokalnie:
- `COPPER-US`
- `USDCAD`
- `AUDUSD`
- `USDJPY`

Najbardziej aktywne na `live paper` w ostatnim dostepnym oknie:
- `US500`
- `GOLD`
- `SILVER`

## 9. Najuczciwsze wnioski koncowe

1. Warstwa uczenia na laptopie zostala realnie uporzadkowana.
2. Kupione dane `QDM` sa juz realnie wykorzystywane przez `ML`, ale jeszcze nie dla calej floty.
3. Zbedne ciezkie warstwy `CSV` zostaly wyciete.
4. Po sprzataniu `refresh` i `training` przeszly poprawnie.
5. Najwiekszy blocker po stronie serwera to nadal `WinRM AccessDenied`.
6. Najwiekszy problem runtime nadal siedzi w:
- `SILVER`
- `PLATIN`
- `DE30`
- `GOLD`
7. Najwiekszy potencjal lokalny nadal maja:
- `COPPER-US`
- `USDCAD`
- `AUDUSD`
- `USDJPY`

## 10. Rekomendowany nastepny krok

1. Odblokowac `VPS` przez `RDP` i naprawic `WinRM auth`.
2. Zrobic swiezy `pull feedback`.
3. Nie wracac juz do trzymania wielkich `QDM export CSV`.
4. Rozszerzac pokrycie `QDM` na kolejne symbole, zeby `ML` przestalo byc mocne tylko dla `EURUSD`, `USDJPY`, `GBPUSD`.
5. Utrzymac zasade:
- jedna warstwa surowych danych pobranych
- lekkie warstwy research
- zero zbednych duzych `CSV`
