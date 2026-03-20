# Deep Learning Stack And Legacy Separation Audit

Data: `2026-03-20`

## Cel

Ten audyt odpowiada na cztery pytania:

1. czy aktywny system `MAKRO_I_MIKRO_BOT` nadal ma runtime-krytyczne zaleznosci od `OANDA_MT5_SYSTEM`,
2. jakie sa poziomy uczenia i strojenia w nowym systemie,
3. czy te poziomy wspolpracuja logicznie, czy sobie przecza,
4. czy w systemie istnieja warstwy sprzatajace i czy rzeczywiscie czyszcza przedpole pod nauke.

## Werdykt ogolny

Werdykt jest mieszany, ale dobry:

- rdzen uczenia w `MQL5` jest architektonicznie spojny,
- najwiekszy realny balagan siedzial nie w samych agentach strojenia, tylko w warstwie raportowania i legacy-sciezkach,
- aktywne twarde zaleznosci `MAKRO_I_MIKRO_BOT -> OANDA_MT5_SYSTEM` zostaly odciete z codziennych raportow, priorytetow, guardow MT5 i audytu,
- pozostaly juz tylko jawne slady historyczne oraz skrypt sluzacy do wylaczenia starego systemu.

## Co bylo zle

Przed tym audytem nowy system mial kilka niebezpiecznych przeciekow ze starego repo:

- `BUILD_FULL_STACK_AUDIT.ps1` ocenial swiezosc feedbacku po plikach z `C:\OANDA_MT5_SYSTEM`,
- `BUILD_PROFIT_TRACKING_REPORT.ps1` i `BUILD_TUNING_PRIORITY_REPORT.ps1` czytaly `paper/live` z legacy runtime compact,
- otwieranie MT5 w nowym systemie wołalo guard z legacy repo,
- raporty operatorskie mogly wygladac jak nowe, ale nadal opierac sie na starej warstwie dowodowej.

To bylo mylace, bo z zewnatrz system wygladal na jeden organizm, ale w srodku mial jeszcze kilka starych kabli.

## Co naprawiono

W tej rundzie wprowadzono:

### 1. Kanoniczny feedback `paper/live` w nowym repo

Dodany zostal:

- [BUILD_CANONICAL_PAPER_LIVE_FEEDBACK.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_CANONICAL_PAPER_LIVE_FEEDBACK.ps1)

Ten skrypt buduje lokalny, kanoniczny raport:

- [paper_live_feedback_latest.json](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\paper_live_feedback_latest.json)
- [paper_live_feedback_latest.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\paper_live_feedback_latest.md)

Od teraz to jest zrodlo prawdy dla:

- `BUILD_PROFIT_TRACKING_REPORT.ps1`
- `BUILD_TUNING_PRIORITY_REPORT.ps1`
- `BUILD_FULL_STACK_AUDIT.ps1`

### 2. Lokalny raport zdrowia hostingu MT5

Dodany zostal lokalny generator:

- [BUILD_MT5_HOSTING_DAILY_REPORT.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_MT5_HOSTING_DAILY_REPORT.ps1)

Wyjscie:

- [mt5_hosting_daily_report_latest.json](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_hosting_daily_report_latest.json)
- [mt5_hosting_daily_report_latest.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_hosting_daily_report_latest.md)

Ten raport czyta:

- dzisiejsze logi hostingu `MetaQuotes`,
- roster `17` EA z logu ekspertow,
- oraz lokalny kanoniczny feedback `paper/live`.

### 3. Lokalny guard popupu ryzyka MT5

Skopiowany i odciety od legacy:

- [mt5_risk_popup_guard.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\mt5_risk_popup_guard.ps1)

Nowe launchery MT5:

- [OPEN_OANDA_MT5_WITH_MICROBOTS.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\OPEN_OANDA_MT5_WITH_MICROBOTS.ps1)
- [OPEN_OANDA_MT5_WITH_VPS_CLEAR_PROFILE.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\OPEN_OANDA_MT5_WITH_VPS_CLEAR_PROFILE.ps1)

nie wola juz guardow z `OANDA_MT5_SYSTEM`.

### 4. Supervisor przestal polegac na legacy runtime compact

Supervisor:

- [RUN_AUTONOMOUS_90P_SUPERVISOR.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\RUN_AUTONOMOUS_90P_SUPERVISOR.ps1)

teraz:

- odswieza raport dzienny,
- buduje kanoniczny feedback `paper/live`,
- buduje raport hostingu MT5,
- i dopiero na tym buduje priorytety oraz profit tracking.

### 5. Heavy-job throttle

Wykryto tez realny problem architektoniczny:

- [GENERATE_DAILY_SYSTEM_REPORTS.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\GENERATE_DAILY_SYSTEM_REPORTS.ps1)

jest kosztowny, bo czyta duze logi i agreguje dzienny wynik per instrument. Nie moze byc bezmyslnie odpalany co kazde `5` minut.

Dlatego supervisor dostal ograniczenie:

- raport dzienny jest przebudowywany tylko wtedy, gdy jest starszy niz `3600 s`

To usuwa konflikt:

- potrzebujemy swiezego obrazu `paper/live`,
- ale nie mozemy sami zapchac laptopa raportem, ktory mieli za duzo danych.

## Poziomy uczenia i strojenia

Nowy system ma co najmniej `8` warstw, ktore razem tworza caly obieg nauki.

### Warstwa 0. Telemetria runtime

To jest surowy material:

- `runtime_state.csv`
- `execution_summary.json`
- `informational_policy.json`
- `decision_events.csv`
- `learning_observations_v2.csv`
- `learning_bucket_summary_v1.csv`

Lokalizacja:

- `Common Files\\MAKRO_I_MIKRO_BOT\\state`
- `Common Files\\MAKRO_I_MIKRO_BOT\\logs`

To jest najnizsza warstwa prawdy operacyjnej.

### Warstwa 1. Lokalny agent strojenia symbolu

Plik:

- [MbTuningLocalAgent.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningLocalAgent.mqh)

Najwazniejsze zachowania:

- nie stroi niczego bez zamknietych lekcji,
- nie stroi niczego bez minimalnej liczby czystych przegladow,
- pilnuje limitu zmian w oknie,
- stroi po bucketach i reason-code, a nie w ciemno.

Najwazniejsze bezpieczniki:

- `MIN_CLOSED_LESSONS`
- `MIN_CLEAN_REVIEWS`
- `LOW_SAMPLE`
- `COOLDOWN`
- `ADAPTATION_WINDOW_LIMIT`
- `BUCKETS_MISSING`

To jest dobra logika. Ona nie pozwala agentowi miotac parametrami po kilku przypadkach.

### Warstwa 2. Deckhand i reason normalization

Plik:

- [MbTuningDeckhand.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningDeckhand.mqh)

To jest warstwa porzadkujaca:

- normalizuje reason-code,
- zapisuje zrozumiale powody,
- utrzymuje porzadek w epistemice runtime.

To nie jest oddzielny agent decyzyjny, tylko warstwa stabilizujaca material dla lokalnego strojenia.

### Warstwa 3. Agent rodzinny

Plik:

- [MbTuningFamilyAgent.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningFamilyAgent.mqh)

Ta warstwa:

- zbiera polityki symboli w rodzinie,
- liczy zaufane symbole, zdegradowane symbole, chaos, bad spread,
- zaciska `confidence_cap` i `risk_cap`,
- moze zamrozic nowe zmiany dla calej rodziny.

To jest logicznie poprawne: kiedy cala rodzina jest zla lub brudna, nie pozwalamy kazdemu symbolowi stroic sie agresywnie w izolacji.

### Warstwa 4. Koordynator flotowy

Plik:

- [MbTuningCoordinator.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningCoordinator.mqh)

Ta warstwa:

- patrzy na wszystkie rodziny,
- ogranicza globalny `confidence_cap`,
- ogranicza globalny `risk_cap`,
- zmniejsza `max_local_changes_per_cycle`,
- potrafi zamrozic cala florete przy duzej degradacji lub mocnej stracie dziennej.

To nie dubluje lokalnego agenta. To jest wyzszy poziom kontraktu ryzyka.

### Warstwa 5. Hierarchy bridge

Plik:

- [MbTuningHierarchyBridge.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningHierarchyBridge.mqh)

To jest jedna z najwazniejszych czesci calej architektury.

Kluczowy fakt:

- w `paper runtime` freeze rodziny lub floty **nie blokuje** lokalnego uczenia

Kod robi to jawnie przez `ALLOW_PAPER_RUNTIME`.

To oznacza:

- live ma byc chronione,
- paper ma sie dalej uczyc.

To jest spojne i dobrze przemyslane. Tu nie ma sprzecznosci, jest swiadome rozdzielenie:

- `ochrona produkcji`
- `utrzymanie laboratorium`

### Warstwa 6. Arbitraz kandydatow i kontrakt kapitalowy

Pliki:

- [MbCandidateArbitration.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbCandidateArbitration.mqh)
- [MbMarketGuards.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbMarketGuards.mqh)

Ta warstwa:

- pilnuje jednej pozycji,
- ogranicza nowe wejscia per cykl,
- pilnuje kontraktu kapitalowego,
- rozdziela ryzyko miedzy symbole i rodziny.

To nie jest uczenie w sensie ML, ale ma ogromny wplyw na to, czy uczenie ma czysty material.

### Warstwa 7. Offline research i ML

Glowny ciag:

- `QDM raw history`
- `QDM cache parquet`
- `Research parquet`
- `DuckDB`
- trening modelu w Pythonie
- eksport `ONNX`

Najwazniejsze pliki:

- [EXPORT_MT5_RESEARCH_DATA.py](C:\MAKRO_I_MIKRO_BOT\TOOLS\EXPORT_MT5_RESEARCH_DATA.py)
- [TRAIN_PAPER_GATE_ACCEPTOR_MODEL.py](C:\MAKRO_I_MIKRO_BOT\TOOLS\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.py)
- [BUILD_LEARNING_STACK_AUDIT.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_LEARNING_STACK_AUDIT.ps1)

To jest zupelnie inna warstwa niz lokalny agent `MQL5`. Ona:

- nie rusza bezposrednio parametrow symbolu w runtime,
- tylko uczy modele pomocnicze i buduje material diagnostyczny.

### Warstwa 8. Sprzatanie i higiena nauki

To sa wlasnie te nasze "sprzataczki", ktorych brak bylby katastrofalny:

- [AUDIT_AND_CLEAN_RUNTIME_ARTIFACTS.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\AUDIT_AND_CLEAN_RUNTIME_ARTIFACTS.ps1)
- [AUDIT_RUNTIME_PERSISTENCE.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\AUDIT_RUNTIME_PERSISTENCE.ps1)
- [ROTATE_RUNTIME_LOGS.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\ROTATE_RUNTIME_LOGS.ps1)
- [BUILD_LEARNING_STACK_AUDIT.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_LEARNING_STACK_AUDIT.ps1)
- [NORMALIZE_LEARNING_ARTIFACT_LAYERS.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\NORMALIZE_LEARNING_ARTIFACT_LAYERS.ps1)

Ich rola:

- wycinanie zbednych artefaktow,
- pilnowanie retencji logow,
- pilnowanie zeby QDM export CSV nie lezal wiecznie obok cache i DuckDB,
- utrzymanie tylko jednej sensownej warstwy artefaktow do nauki.

## Czy te warstwy sie wykluczaja

Po glebokim przegladzie: **nie widze krytycznej sprzecznosci architektonicznej**.

Widze za to celowy podzial odpowiedzialnosci:

- lokalny agent stroi symbol,
- rodzina koryguje symbol w kontekscie rodziny,
- koordynator hamuje cala florete,
- hierarchy bridge chroni live, ale nie zabija paper-labu,
- offline ML uczy modele z szerszej historii i podpowiada, co jest toksyczne,
- housekeeping pilnuje, zeby uczenie nie dlawilo sie od smieci.

To jest logiczne.

## Gdzie byly realne niedociagniecia

### 1. Legacy feedback leakage

Najwiekszy realny problem nie siedzial w `MQL5`, tylko w tym, ze nowy system raportowal i priorytetyzowal czesc rzeczy po starych sciezkach.

To zostalo naprawione.

### 2. Zbyt ciezki raport dzienny w supervisorze

To byl drugi wazny problem.

`GENERATE_DAILY_SYSTEM_REPORTS.ps1` jest przydatny, ale kosztowny. Nie moze byc odpalany bezwarunkowo co kazdy krotki cykl.

To zostalo poprawione przez limit wieku artefaktu.

### 3. QDM coverage jest jeszcze niskie

Aktualny audyt uczenia pokazuje:

- `learning_verdict = QDM_PARTIALLY_ACTIVE`
- `qdm_rows_with_coverage = 263969`
- `qdm_coverage_ratio = 0.041285`
- symbole z realnym pokryciem QDM:
  - `EURUSD`
  - `USDJPY`
  - `GBPUSD`

To znaczy:

- system juz uczy sie z kupionych danych,
- ale jeszcze nie w skali calej floty `17`.

### 4. MT5 retest queue dalej ma stary, niespojny plik statusu

To nadal widac w audycie `trust-but-verify`.

Nie jest to juz problem warstwy legacy, ale wciaz jest to problem wiarygodnosci statusow pomocniczych.

## Czy system uczy sie z kupionych danych

Tak, ale tylko czesciowo.

Twarde potwierdzenie:

- [learning_stack_audit_latest.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\learning_stack_audit_latest.md)
- [paper_gate_acceptor_metrics_latest.json](C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor\paper_gate_acceptor_metrics_latest.json)

Na dzis:

- `QDM history = 69.024 GB`
- `QDM cache parquet = 0.595 GB`
- `research parquet = 0.687 GB`
- `research duckdb = 2.012 GB`
- `QDM export CSV = 0 GB`
- `research CSV = 0 GB`

To jest dobry stan:

- warstwa surowa jest zachowana,
- warstwa robocza do uczenia jest odchudzona,
- zbedne duze warstwy CSV nie zapychaja juz pracy.

## Czy zbyt czeste pobieranie baz danych blokowalo dysk

Tak, to bylo realne ryzyko.

Wczesniej weakest-sync `QDM` odpalal sie za agresywnie. To juz zostalo ograniczone przez:

- cooldown per symbol,
- minimalny odstep miedzy weakest-sync.

Z punktu widzenia architektury to jest poprawne: pobieranie danych ma karmic nauke, nie mielic stale tych samych zakresow.

## Stan po naprawie

Po tym audycie aktywne odwolania do `OANDA_MT5_SYSTEM` w nowym repo zostaly zredukowane do:

- skryptu jawnie sluzacego do wylaczenia legacy autostartu,
- sladow dokumentacyjnych i historycznych.

To znaczy:

- nowy system nie miesza juz na co dzien raportowania i guardow z legacy repo,
- warstwa uczenia jest logicznie spojna,
- cleanup istnieje i ma sens,
- glownym dalszym zadaniem nie jest juz odcinanie starego repo, tylko:
  - domkniecie kolejek statusu `MT5`,
  - rozszerzenie pokrycia `QDM`,
  - i dalej selektywne zawiezanie rosteru aktywnych instrumentow.

## Najwazniejsze rekomendacje na nastepny krok

1. Nie odpalac ciezkiego raportu dziennego co krotki cykl.
2. Rozszerzac `QDM` na kolejne symbole, bo `4.13%` pokrycia to dopiero poczatek.
3. Trzymac `paper/live` w nowym repo przez kanoniczny raport, a nie przez stare sciezki.
4. Domknac stale `mt5_retest_queue`, bo to teraz najbardziej myli obraz pracy testera.
5. Oddzielic roster `active/probation/bench`, zeby nie ciagnac wszystkich `17` z ta sama agresja.

