# Bootstrap Status

## 2026-03-14 - dashboardy bardziej po polsku i wyraznie podzielone na trzy swiaty

- dashboard dzienny zostal przebudowany tak, aby mocniej pokazywal trzy glowne domeny:
  - `Waluty`
  - `Metale`
  - `Indeksy`
- kazda domena ma teraz:
  - wlasny opis po polsku
  - liczbe rodzin
  - liczbe instrumentow
  - wynik sumaryczny
  - `READY 24h`
  - karty rodzin wewnetrznych
- raport dzienny zostal dodatkowo napisany bardziej po polsku i bardziej opisowo:
  - mniej surowej telemetrii bez kontekstu
  - wiecej sensu operatorskiego
  - jasniejsze rozroznienie:
    - domena
    - rodzina
    - instrument
- raport wieczorny dla wlasciciela zostal dopelniony o:
  - blok `Swiaty systemu`
  - bardziej ludzki opis
  - jezyk `instrumentow` zamiast samej `pary`
- potwierdzono regeneracje:
  - `EVIDENCE/DAILY/dashboard_dzienny_latest.html`
  - `EVIDENCE/DAILY/dashboard_wieczorny_latest.html`

## 2026-03-14 - dashboardy i panel uzupelnione o MT5 oraz skroty na pulpit

- dashboard dzienny przestal juz byc tylko widokiem `FX` i zostal uzupelniony o:
  - jezyk `instrumentow` zamiast samych `par`
  - sekcje `Terminal MT5 / OANDA`
  - status instalacji do terminala
  - nazwe profilu `MT5`
  - liczbe wykresow profilu
  - stan procesu `terminal64`
  - bezposrednia akcje `Uruchom OANDA MT5`
- raport wieczorny zostal uzupelniony o prosty blok:
  - status `MT5`
  - status instalacji
  - nazwe profilu
  - liczbe wykresow
- panel operatora:
  - przeszedl z jezyka `pary` na jezyk `instrumentu`
  - pokazuje teraz rowniez stan `MT5`, instalacji i profilu
  - dostal przycisk `Uruchom OANDA MT5`
- dodano skrypt tworzenia skrotow na pulpit Windows:
  - `RUN/UTWORZ_SKROTY_NA_PULPICIE.ps1`
- skrypt utworzyl skroty do:
  - `MT5 + Panel + Dashboard`
  - `Panel Operatora`
  - `Dashboard Dzienny`
  - `Raport Wieczorny`
  - `Tylko Dashboardy`
  - `OANDA MT5`
- zapisano raport:
  - `EVIDENCE/desktop_shortcuts_report.json`

## 2026-03-14 - rzeczywisty rollout `METALS` i `INDICES` do terminala OANDA MT5

- domknieto pakiet montazowy tak, aby przenosil:
  - zrodla `mq5`
  - binaria `ex5`
  - presety bazowe
  - presety aktywne `ActiveLive`
  - konfiguracje projektu
- ponownie wykonano pelny rollout preflight i symulowana instalacje pakietu
- pakiet zostal rzeczywiscie zainstalowany do danych terminala:
  - `C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856`
- walidacja po instalacji zwrocila:
  - `ok=true`
- zbudowano i uruchomiono profil:
  - `MAKRO_I_MIKRO_BOT_AUTO`
- profil zawiera `17` wykresow:
  - cala domene `FX`
  - cztery metale
  - dwa indeksy
- od tego etapu `METALS` i `INDICES` sa juz nie tylko gotowe projektowo, ale realnie podpiete do lokalnego `OANDA MT5`
- zapisano:
  - `DOCS/82_OANDA_MT5_METALS_AND_INDICES_TERMINAL_ROLLOUT_V1.md`
  - `EVIDENCE/OANDA_MT5_METALS_AND_INDICES_TERMINAL_ROLLOUT_20260314.md`

## 2026-03-14 - prelive audit maszyny stanow domenowych

- dodano nowy walidator maszyny stanow domenowych i wpieto go do glownego `prelive go/no-go`
- audyt sprawdza teraz:
  - kompletność wspolnych stanów domenowych
  - poprawnosc rezerw domen w koordynatorze sesji
  - obecnosc i spojnosc plikow:
    - `session_capital_state`
    - `runtime_control`
  - zgodnosc `requested_mode` i `risk_cap`
  - brak sprzecznych kombinacji typu:
    - `SLEEP` z aktywna grupa
    - `PAPER_ACTIVE` bez `PAPER_ONLY`
    - `LIVE_DEFENSIVE` bez `RUN`
    - `REENTRY_PROBATION` bez `RUN`
  - brak wielu domen proszacych jednoczesnie o `RUN`
- poprawiono tez sam `prelive go/no-go`, tak aby krok maszyny stanow przechodzil tylko wtedy, gdy walidator zwraca `ok=true`
- aktualny wynik audytu:
  - `ok=true`
  - jedna domena `RUN`
  - brak bledow blokujacych
  - obecne sa tylko ostrzezenia o symbolach metali i indeksow, ktore nie maja jeszcze lokalnego runtime na wykresach
- zapisano:
  - `DOCS/81_PRELIVE_STATE_MACHINE_AUDIT_V1.md`
  - `EVIDENCE/PRELIVE_STATE_MACHINE_AUDIT_20260314.md`

## 2026-03-14 - portfolio heat gate po arbitrazu rodzinnym

- domknieto egzekwowanie `max_open_risk_pct` po wdrozeniu arbitrazu kandydatow `TOP-1`
- nowa kolejnosc decyzyjna wyglada teraz tak:
  - mikro-bot wystawia kandydata
  - aktywna grupa wybiera `TOP-1`
  - `portfolio heat gate` sprawdza, czy zwyciezca miesci sie jeszcze w otwartym ryzyku floty
  - dopiero potem wejscie trafia do prechecku i wykonania
- dla `live` liczone jest otwarte ryzyko tylko dla naszej floty
- dla `paper` liczone jest otwarte ryzyko aktywnych pozycji papierowych calej floty
- jesli system nie umie wiarygodnie odtworzyc ryzyka juz otwartej pozycji naszej floty, blokuje nowe wejscie jako:
  - `PORTFOLIO_HEAT_UNKNOWN`
- normalne przekroczenie temperatury portfela blokuje wejscie jako:
  - `PORTFOLIO_HEAT_BLOCK`
- kompilacja calej floty przeszla `17/17`
- walidacja layoutu, koordynatora sesji i kontraktu rdzenia przeszla bez bledow
- zapisano:
  - `DOCS/80_PORTFOLIO_HEAT_GATE_V1.md`
  - `EVIDENCE/PORTFOLIO_HEAT_GATE_20260314.md`

## 2026-03-14 - runtime arbitrazu kandydatow `TOP-1` dla aktywnej rodziny

- wdrozono lekki arbitraz kandydatow oparty o zalozenie, ze w rdzeniowym oknie normalnie handluje jedna aktywna rodzina naraz
- nowy model nie robi globalnego turnieju calej floty, tylko:
  - mikro-bot publikuje lekki snapshot swojego kandydata
  - aktywna grupa wybiera `TOP-1`
  - guardy kapitalowe i wykonawcze dalej pilnuja dopuszczenia do wejscia
- arbiter dziala dla grup:
  - `FX_MAIN`
  - `FX_ASIA`
  - `FX_CROSS`
  - `METALS`
  - `INDEX_EU`
  - `INDEX_US`
- `METALS_SPOT_PM` i `METALS_FUTURES` zostaly celowo sklejone do jednej grupy arbitrazu `METALS`, aby w glownym oknie metalowym wybierac najlepszego zawodnika sposrod czterech metali
- rozstrzyganie:
  - `clear winner` -> wejscie moze isc dalej
  - `near tie` -> nadal wybierany jest `TOP-1`
  - `true tie` w `live` -> `skip`
  - `true tie` w `paper` -> naprzemienne rozstrzygniecie poznawcze
- stan arbitrazu jest lekki i nadpisywany:
  - snapshot kandydata per symbol
  - stan ostatniego wyboru per grupa
- kompilacja calej floty przeszla `17/17`
- walidacja layoutu i koordynatora sesji przeszla bez bledow
- zapisano:
  - `DOCS/79_FAMILY_CANDIDATE_ARBITRATION_RUNTIME_V1.md`
  - `EVIDENCE/FAMILY_CANDIDATE_ARBITRATION_RUNTIME_20260314.md`

## 2026-03-14 - plan migracji arbitrazu kandydatow i ciepla portfela

- po ponownym przegladzie starego `OANDA_MT5_SYSTEM` potwierdzono, ze ograniczanie wielu rownoczesnych wejsc nie wynikalo z jednego prostego bezpiecznika, tylko z kilku warstw naraz:
  - shortlisty kandydatow,
  - arbitrazu grup,
  - limitu pozycji na symbol,
  - limitu otwartego ryzyka portfela,
  - pacingu,
  - dedupe,
  - oraz `TOP_1` dla wybranych koszykow jak `JPY basket`.
- zapisano plan przeniesienia tych mechanizmow do `MAKRO_I_MIKRO_BOT` w postaci:
  - migracji `1:1` tego, co nadal ma sens,
  - uproszczenia tam, gdzie nowa architektura okien i domen juz przejela czesc odpowiedzialnosci,
  - oraz swiadomego niekopiowania starego monolitu.
- najwazniejsze zalozenie nowego modelu:
  - mikro-bot wystawia lekkiego kandydata,
  - aktywna rodzina wybiera `TOP_1`,
  - guard kapitalowy sprawdza portfelowe cieplo,
  - dopiero potem zwyciezca dostaje zgode na `live`.
- zapisano:
  - `DOCS/78_CANDIDATE_ARBITRATION_AND_PORTFOLIO_HEAT_MIGRATION_V1.md`
  - `CONFIG/candidate_arbitration_contract_v1.json`

## 2026-03-14 - notatka o narodzinach projektu

- zapisano ludzki dokument o pochodzeniu projektu:
  - nowy `MAKRO_I_MIKRO_BOT` nie powstal z niczego,
  - wyrosl z okolo `45 dni` pracy nad poprzednim systemem jednobotowym,
  - odziedziczyl po nim rytm sesji, ochrone kapitalu, logike brokera, rozgrzewki, okna czasowe i kulture ostroznosci.
- ta ciaglosc zostala zapisana w:
  - `DOCS/77_NARODZINY_MAKRO_I_MIKRO_BOTA.md`
  - `EVIDENCE/NARODZINY_MAKRO_I_MIKRO_BOTA_20260314.md`

## 2026-03-14 - runtime rollout domeny INDICES

- domena `INDICES` zostala aktywowana jako trzeci swiat runtime we wspolnym organizmie obok `FX` i `METALS`.
- do projektu i runtime dodano:
  - `DE30.pro` jako `INDEX_EU`
  - `US500.pro` jako `INDEX_US`
- powstaly:
  - profile indeksowe
  - strategie indeksowe
  - mikro-boty indeksowe
  - presety `Live`
- zaktualizowano:
  - `microbots_registry`
  - `strategy_variant_registry`
  - `family_policy_registry`
  - `family_reference_registry`
  - `tuning_fleet_registry`
  - `session_capital_coordinator`
  - `domain_architecture_registry`
- przebudowano seedy rodzin i koordynatora, a `INDEX_EU` i `INDEX_US` dostaly w `Common Files` swoje stany rodzinne i journale.
- kompilacja calej floty przeszla `17/17`.
- walidatory projektu, rodzin, hierarchii i koordynatora przeszly bez bledow.
- indeksy startuja uczciwie jako:
  - `trusted_data=0`
  - `freeze_new_changes=1`
  bo nie maja jeszcze lokalnej probki runtime do strojenia.

## 2026-03-14 - playbook pierwszej godziny dla INDICES

- dodano operatorski playbook pierwszej godziny dla domeny `INDICES`
- przygotowano osobne guardraile i kandydat ustawien poniedzialkowych dla:
  - `INDEX_EU`
  - `INDEX_US`
- zaktualizowano glowny monday playbook tak, aby obejmowal juz:
  - `FX_MAIN`
  - `FX_ASIA`
  - `FX_CROSS`
  - `INDICES`
- indeksy maja wejsc w poniedzialek obserwacyjnie, bez recznego odblokowywania strojenia po pojedynczym sukcesie paper

## 2026-03-13 EURUSD coherence audit

- wykonano audyt spójnosci `EURUSD` po wdrozeniu warstwy swiec + `Renko`
- potwierdzono, ze problem nie lezy w konflikcie warstw strategii, tylko w diagnostyce i starym sladowaniu uczenia
- dodano:
  - `learning_observations_v2.csv`
  - throttling powtarzalnych wpisow runtime
  - jawny slad `AUX` dla warstwy pomocniczej
- raport:
  - `EVIDENCE/EURUSD_COHERENCE_AUDIT_20260313.md`

## 2026-03-13 USDCHF context layer v1

- `USDCHF` zostal podniesiony na ten sam poziom paper/context-learning co `GBPUSD` i `USDCAD`.
- `MicroBot_USDCHF.mq5` zostal przepiety na nowy runtime z:
  - paper runtime override,
  - normalizacja permission flags,
  - AUX decision events,
  - `learning_observations_v2.csv`,
  - `learning_bucket_summary_v1.csv`.
- `Strategy_USDCHF.mqh` dostala warstwe:
  - `MbContextPolicy`
  - `MbCandleAdvisory`
  - `MbRenkoAdvisory`
  - `MbAuxSignalFusion`
  - `MbLearningContext`
- Po wdrozeniu `USDCHF` przeszedl pierwszy pelny cykl:
  - `PAPER_OPEN`
  - `PAPER_CLOSE`
  - zapis nowego rekordu `v2`
  - zapis pierwszego bucket summary
- Aktualny material `USDCHF` jest juz gotowy do dalszej obserwacji indywidualnej bez rozlewania zmian na cala rodzine.

## 2026-03-13 - indywidualne strojenie trojki FX_MAIN po EURUSD

- W jednej zamknietej rundzie dostrojono trzy kolejne pary z rodziny `FX_MAIN`:
  - `GBPUSD`
  - `USDCAD`
  - `USDCHF`
- Strojenie nie bylo kopia `EURUSD` 1:1. Zachowano genotyp kazdej pary i przeniesiono tylko wspolna warstwe:
  - kontekstu rynku
  - warstwy swiec
  - warstwy `Renko`
  - fuzji `AUX`
  - paper runtime
  - `learning_observations_v2`
  - `learning_bucket_summary_v1`
- `GBPUSD` zostal przycisniety w slabym `RANGE + CAUTION`.
- `USDCAD` zostal odsuniety od breakoutowego automatyzmu i skierowany bardziej w strone `SETUP_TREND`.
- `USDCHF` dostal najsilniejsze ograniczenia confidence i risk, bo byl najbardziej niebezpiecznie przestymulowany mimo slabego bucketowego materialu.
- Cala trojka:
  - kompiluje sie poprawnie
  - laduje sie poprawnie po restarcie `MT5`
  - ma `trade_permissions_ok=true`
  - ma aktywny `paper_runtime_override_active=true`
  - jest gotowa do dalszej spokojnej obserwacji indywidualnej

## 2026-03-14 - porzadki warstwy strojenia

- lokalny pomocnik techniczny dla strojenia przestal zapisywac powtarzalne wpisy bez zmian stanu; journaling zostaje tylko przy:
  - zmianie zaufania do danych,
  - zmianie liczby probek lub bucketow,
  - realnym rebuildzie summary,
  - przejsciu w nowy powod blokady / zaufania.
- audit runtime zostal nauczony nowych katalogow:
  - `state\\_families`
  - `state\\_coordinator`
  - `logs\\_families`
  - `logs\\_coordinator`
- dzieki temu narzedzie czyszczenia nie traktuje juz prawidlowej hierarchii strojenia jako brudu i nie daje falszywych alarmow.
- dodano bezpieczna rotacje przerosnietych logow runtime:
  - `incident_journal.jsonl`
  - `decision_events.csv`
  - `latency_profile.csv`
- rotacja archiwizuje stare pliki do `archive\\timestamp` i zostawia czysty plik roboczy, zamiast mieszac biezaca prace z historycznym balastem.

## 2026-03-14 - most lokalny -> rodzina -> flota dla strojenia

- dodano most hierarchii strojenia w `Core`, ktory sklada skuteczna polityke lokalna z:
  - lokalnego strojenia mikro-bota,
  - polityki rodziny,
  - polityki koordynatora floty.
- `EURUSD` zostal przepiety na nowy model:
  - rodzina i flota moga blokowac nowe lokalne zmiany przez `FAMILY_FREEZE` / `FREEZE_FLEET`,
  - strategia dostaje skuteczna polityke po kompozycji ograniczen,
  - skuteczna polityka jest zapisywana do `tuning_policy_effective.csv`.
- poprawiono narzedzie kompilacji tak, aby synchronizacja zrodel do katalogu terminala byla domyslna i zniknela mozliwosc kompilowania starego kodu z `MT5`.

## What Exists

- project root and target directories
- architecture docs
- deployment model doc for 11 bots
- Codex working prompt
- root manifest and config
- server profile manifest
- first PowerShell scaffold generator
- first `Core` bootstrap files
- first `EURUSD` profile and strategy stub
- first `MicroBot_EURUSD` reference expert
- first generated non-reference microbot scaffold: `AUDUSD`
- first symbol deployment registry
- full first batch of `11` microbot scaffolds generated from registry
- local market snapshot and tick freshness helpers added to `Core`
- generated MT5 chart attachment plan from registry
- exported first MT5 server profile package
- built first portable project ZIP package
- added first compile/verify tool for MicroBots
- confirmed MetaEditor compile for `MicroBot_EURUSD`
- confirmed MetaEditor compile for generated `MicroBot_AUDUSD`
- confirmed full MetaEditor compile for all 11 microbots from registry
- added local session/trade-window helper to `Core`
- added first mature observability migration from `EURUSD`: latency profile, broker profile plane, execution summary plane
- recompiled `MicroBot_EURUSD` successfully after the first real mature-module transplant
- added generic informational policy plane to `Core`
- added safe rebuild tool for generated microbots
- rebuilt all generated microbots from the latest scaffold and recompiled the full batch successfully
- added first mature market guard migration from `EURUSD` into `Core`
- added shared runtime fields for entry cooldown and daily/session equity anchors
- added shared market guard layer for spread, tick freshness, cooldown, margin and loss caps
- added shared low-level execution precheck for `OrderCalcMargin` / `OrderCheck`
- added shared local execution send/retry wrapper
- added shared local trade transaction journal helper
- added shared local closed-deal tracker for per-bot PnL/session feedback
- upgraded `Strategy_EURUSD` from stub to first real local indicator-based scoring pass
- upgraded `MicroBot_EURUSD` to full dry-run path: signal -> sizing -> execution precheck -> READY/BLOCK journaling
- upgraded `MicroBot_EURUSD` to controlled local live-send with default-safe switch `InpEnableLiveEntries=false`
- upgraded `EURUSD` with first local open-position management / trailing layer
- standardized local strategy hooks across the whole park: `Init / Deinit / ManagePosition`
- upgraded `GBPUSD` from pure scaffold to first real non-reference local strategy
- upgraded `GBPUSD` to full dry-run path: signal -> sizing -> execution precheck
- upgraded `GBPUSD` to controlled local live-send and first local trailing layer
- upgraded `USDJPY` to first real Asia-session local strategy with dry-run entry path
- upgraded `USDJPY` to controlled local live-send and first local trailing layer
- upgraded `NZDUSD` to second real Asia-session local strategy with dry-run entry path
- upgraded `NZDUSD` to controlled local live-send and first local trailing layer
- upgraded `USDCAD` to third main-session local strategy with dry-run entry path
- upgraded `USDCAD` to controlled local live-send and first local trailing layer
- upgraded `USDCHF` to fourth main-session local strategy with dry-run entry path
- upgraded `USDCHF` to controlled local live-send and first local trailing layer
- upgraded `AUDUSD` to third Asia-oriented local strategy with dry-run entry path
- upgraded `AUDUSD` to controlled local live-send and first local trailing layer
- upgraded `EURJPY` to first cross-session local strategy with dry-run entry path
- upgraded `EURJPY` to controlled local live-send and first local trailing layer
- upgraded `GBPJPY` to second cross-session local strategy with dry-run entry path
- upgraded `GBPJPY` to controlled local live-send and first local trailing layer
- upgraded `EURAUD` to third cross-session local strategy with dry-run entry path
- upgraded `EURAUD` to controlled local live-send and first local trailing layer
- rebuilt generated experts with the new guard layer and recompiled the full batch successfully again
- completed the first `11/11` pass with no pure scaffold-only strategy left in the park
- assigned unique `magic numbers` to the whole `11` bot batch and regenerated the MT5 chart attachment plan
- aligned the `kill-switch` runtime model with the mature `EURUSD` pattern, including cached state and token refresh scripts
- added deployment readiness validation for registry/preset/expert magic consistency and token freshness
- added one-command rollout preflight that syncs tokens, builds, validates, regenerates chart plan, exports server profile and writes a ZIP backup
- added `RUN` wrapper for operator-facing rollout entrypoint
- added dedicated operator rollout checklist for morning attach workflow
- added conscious generator of `ACTIVE` presets with `InpEnableLiveEntries=true` outside the default-safe repo presets
- added preset safety validation to ensure repo presets stay safe and generated active presets stay truly live-enabled
- added operator `HANDOFF` export with chart plan, rollout checklist and latest readiness reports next to the MT5 server package
- added transfer-package validation for the combined `PACKAGE + HANDOFF` delivery set
- added dedicated ZIP packaging for the `HANDOFF` operator bundle
- added remote-install scripts for unpacking the server package into a target `MT5` data directory
- added validation of the target `MT5` installation layout
- added automated simulation of remote `MT5` installation as part of rollout preflight
- added first strategy-variant audit and registry generator for separating shared flow from per-symbol overrides
- added first propagation-model document for future common-change rollout across the 11 microbots
- extracted the first real shared strategy helper module for indicator-copy, risk/lot computation and shared risk-plan building
- refactored all `11/11` strategy files to use the first shared strategy helper for indicator-copy and risk/lot computation
- refactored all `11/11` strategy files to use the shared risk-plan builder while keeping symbol-specific multipliers and risk-model genes local
- refactored all `11/11` strategy files to use the shared trailing/position-management helper while keeping local trail multipliers and pressure-step scales local
- refactored all `11/11` strategy files to use the shared new-bar gate helper while keeping local setup logic and trigger thresholds local
- refactored all `11/11` strategy files to use the shared indicator init/deinit helper while keeping local EMA/ATR/RSI periods local
- refactored all `11/11` strategy files to use the shared setup-winner helper while keeping local scoring formulas and setup labels local
- refactored all `11/11` strategy files to use the shared final trigger-gate helper while keeping local trigger thresholds and setup reasons local
- fixed `COMPILE_MICROBOT.ps1` so symbol-targeted compilation resolves the correct expert from registry and copies `Strategies/Common`
- documented explicit split between shared hard-risk guards and local per-symbol risk genes
- added policy-consistency validation between deployment registry and real symbol profiles/strategy variants
- added family-policy registry and bounds validation for `FX_MAIN` / `FX_ASIA` / `FX_CROSS`
- added family propagation matrix and per-family source plans for `EURUSD -> FX_MAIN`, `USDJPY -> FX_ASIA`, `EURJPY -> FX_CROSS`
- added explicit family reference registry for source bots per family

## What Is Intentionally Minimal

The current MQL5 scaffold is not a migrated live trading bot yet.
It is a safe structural starting point that preserves the new autonomy-first model:

- local runtime per bot
- local chart ownership
- local symbol profile
- shared code only as library

## Next Engineering Targets

1. Continue extracting only safe common strategy flow from the `11` local strategies without touching setup-specific genes.
2. Continue enriching `EURUSD` local strategy toward the mature reference bot.
3. Continue mapping mature `EURUSD` modules into compatible `Core`/`Profile`/`Strategy` slices.
4. Harden presets, rollout docs and MT5-only deployment flows for the completed `11` bot batch.
5. Keep the shared `Core` limited to reusable contracts, journaling and low-level helpers.
6. Grow symbol intelligence locally instead of centralizing execution ownership.
## 2026-03-12 - EURUSD journaling hot-path trim

- `MicroBot_EURUSD` został przepięty na cache ścieżek logów zamiast wielokrotnego budowania ścieżek w `OnTick`.
- `MbDecisionJournal.mqh` dostał buforowanie zdarzeń decyzji w pamięci z flush na timerze albo po przekroczeniu progu kolejki.
- `MbExecutionTelemetry.mqh` dostał ten sam model buforowania telemetryki wykonania.
- `MbIncidentJournal.mqh` i `MbTradeTransactionJournal.mqh` dostały ten sam model buforowania, tak aby guardy i `OnTradeTransaction` nie otwierały plików przy każdym zdarzeniu.
- `MbHasPosition()` dostał szybki `PositionSelect(symbol)` jako fast-path przed pełnym skanowaniem pozycji.
- `MicroBot_EURUSD` używa jednego `now = TimeCurrent()` dla całego cyklu decyzji w `OnTick`, zamiast wielokrotnych odczytów czasu.
- `MbLatencyProfile` i `execution_summary.json` zostały rozszerzone o lekkie metryki jakości wykonania: liczba prób, liczba udanych wejść, średnia retry i średni/maksymalny slippage.
- Na razie te metryki są aktywnie zasilane w `EURUSD`, aby sprawdzić kierunek bez ryzykownego przepinania całego parku naraz.
- `EURUSD` dostał lokalny `execution quality guard`, który na podstawie świeżych metryk wykonania wprowadza `CAUTION` albo blokuje nowe wejście przy wyraźnej degradacji jakości.
- `MbClosedDealTracker` aktualizuje teraz lekką pamięć świeżych wyników (`learning_bias`, `adaptive_risk_scale`) bez czytania ciężkiej historii.
- `MbStrategyCommon` używa `adaptive_risk_scale` do miękkiego dostrajania ryzyka po świeżych wynikach.
- Dodano formalny kontrakt `learning / anti-overfit`:
  - minimalna próbka przed aktualizacją biasu (`3`),
  - minimalna próbka przed aktualizacją miękkiego ryzyka (`5`),
  - `learning_confidence` rosnące do pełnego wpływu dopiero po `12` zamkniętych dealach,
  - tłumienie wpływu pojedynczego wyniku i powrót parametrów do neutralności po każdym zamkniętym dealu.
- Stan tej warstwy jest walidowany przez `TOOLS/VALIDATE_LEARNING_POLICY.ps1` i zapisany w `EVIDENCE/learning_policy_validation_report.json`.
- Dodano lekką warstwę testów kontraktowych `TESTS/RUN_CONTRACT_TESTS.ps1`.
- Dodano formalną bramkę `prelive / go-no-go` w `TOOLS/VALIDATE_PRELIVE_GONOGO.ps1`.
- Dodano lekkie drille odporności operacyjnej w `TOOLS/RUN_RESILIENCE_DRILLS.ps1`.
- Obie warstwy działają poza hot-path i są uruchamiane przez `PREPARE_MT5_ROLLOUT.ps1`.
- Drille sprawdzają: obecność runtime state, ciągłość tokenów, komplet recovery artefaktów, poprawne ładowanie ekspertów po restarcie oraz obecność runtime summary per symbol.
- Dodano scenariuszowe testy rodzin w `TESTS/RUN_FAMILY_SCENARIO_TESTS.ps1`.
- Dodano operator-grade raport rodzin w `TOOLS/GENERATE_FAMILY_OPERATOR_REPORT.ps1`.
- Raport rodzin agreguje runtime mode, latencję, execution pressure, learning confidence i spread per rodzina.
- Dodano dzienne raporty systemowe po polsku oraz dashboard HTML przez `TOOLS/GENERATE_DAILY_SYSTEM_REPORTS.ps1`.
- Dodano runner `RUN/GENERATE_DAILY_REPORTS_NOW.ps1` oraz rejestrację zadania `TOOLS/REGISTER_DAILY_REPORT_TASK.ps1` dla codziennego uruchamiania około `20:30`.
- Dashboard dzienny został rozbudowany do wersji operatorskiej z sekcjami rodzin, liderami `READY`, latencją, execution pressure oraz kartami akcji operatora.
- Dodano osobny raport wieczorny dla wlasciciela systemu przez `TOOLS/GENERATE_EVENING_OWNER_REPORT.ps1`.
- Dodano runner `RUN/GENERATE_EVENING_REPORT_NOW.ps1` oraz opcjonalna rejestracje zadania `TOOLS/REGISTER_EVENING_REPORT_TASK.ps1` dla wieczornego raportu `20:30`.
- Dodano polska warstwe pol-interaktywnego sterowania operatora:
  - `RUN/WLACZ_TRYB_NORMALNY_SYSTEMU.ps1`
  - `RUN/WLACZ_CLOSE_ONLY_SYSTEMU.ps1`
  - `RUN/ZATRZYMAJ_SYSTEM.ps1`
  - `TOOLS/SET_RUNTIME_CONTROL_PL.ps1`
  - `TOOLS/GENERATE_RUNTIME_CONTROL_SUMMARY.ps1`
- Dashboard dzienny pokazuje teraz takze biezace sterowanie operatorskie per para.
- Handoff i transfer package zawieraja teraz nie tylko generatory raportow, ale tez aktualne pliki:
  - `EVIDENCE/DAILY/raport_dzienny_latest.*`
  - `EVIDENCE/DAILY/dashboard_dzienny_latest.html`
  - `EVIDENCE/DAILY/raport_wieczorny_latest.*`
  - `EVIDENCE/DAILY/dashboard_wieczorny_latest.html`
- Pozostałe `10` ekspertów zostało przebudowanych z nowego wzorca runtime i dostało te same mechanizmy operacyjne co `EURUSD`.
- Audyt parytetu runtime po propagacji jest zapisany w `EVIDENCE/microbot_runtime_parity_report.json`.
- Ciezki audyt krzyzowy calego systemu jest zapisany w `EVIDENCE/full_system_cross_audit_report.json` oraz `.txt`.
- Podczas audytu wykryto i naprawiono:
  - rozjazd `InpMagic` po przebudowie expert-only,
  - przeterminowane tokeny `kill-switch`.
- Zmiana została zweryfikowana kompilacją `EURUSD`, kompilacją całego parku `11/11` i walidacją layoutu projektu.
- Kierunek: mniejszy narzut I/O w hot-path, brak zmiany genów strategii i gotowy mechanizm do propagacji na resztę botów.
## 2026-03-12 20:48 CET

- Wlaczono lekki `paper-trading` z wirtualna pozycja i syntetycznym domknieciem bez ruszania logiki live.
- Poluzowano wyłącznie `paper mode`:
  - `PAPER_SCORE_GATE` obnizono do `0.20`
  - timeout wirtualnej pozycji skrocono do `300` sekund
- Po restarcie lokalnego `OANDA MT5` wykonano 10-minutowy pomiar pracy systemu.
- Wynik:
  - `11/11` par wygenerowalo `PAPER_OPEN`
  - `10/11` par wygenerowalo `PAPER_CLOSE`
  - lacznie `42` otwarcia i `22` zamkniecia w oknie 10 minut
  - latencja srednia systemowa `0.0908 ms`
  - latencja maksymalna `8.998 ms`
- Raport:
  - `EVIDENCE/paper_trade_latency_10m_report.json`
  - `EVIDENCE/paper_trade_latency_10m_report.txt`
- Wiele par zapisuje juz:
  - `learning_sample_count`
  - `learning_win_count`
  - `learning_loss_count`
  - `realized_pnl_day`
## 2026-03-12 22:05 CET

- `EURUSD` dostal pierwsza lekka warstwe `context layer v1`, inspirowana dawnym `SafetyBot`, ale zapisana juz w czystym `MQL5`.
- Dodano wspolne pliki:
  - `MQL5/Include/Core/MbContextPolicy.mqh`
  - `MQL5/Include/Core/MbLearningContext.mqh`
- `EURUSD` klasyfikuje teraz:
  - `market_regime`
  - `spread_regime`
  - `execution_regime`
  - `confidence_bucket`
  - `signal_confidence`
  - `signal_risk_multiplier`
- `EURUSD` zapisuje kontekst paper/live do `learning_observations.csv`.
- `informational_policy.json` i `execution_summary.json` zostaly rozszerzone o nowa warstwe kontekstowa.
- Zachowano kompatybilnosc calego parku przez przeciazona wersje `MbPaperOpenPosition(...)`, tak aby pozostale boty nie wymagaly natychmiastowej migracji.
- Kompilacja `MicroBot_EURUSD` przechodzi poprawnie po wdrozeniu tej warstwy.
- Pelna kompilacja `11/11` botow po przywroceniu kompatybilnosci przechodzi poprawnie.
## 2026-03-13 09:25 CET

- Poranna analiza pokazala, ze nowa warstwa `EURUSD` byla realnie uruchamiana, ale:
  - `TRADE_DISABLED` odcinal `paper mode` zanim sygnal dochodzil do pelnej oceny,
  - kolejne ticki z `WAIT_NEW_BAR` nadpisywaly ostatni poprawny kontekst wartosciami `UNKNOWN/NONE`.
- Naprawiono oba miejsca tylko dla `EURUSD`:
  - `paper mode` obchodzi juz `TRADE_DISABLED` tak samo, jak wczesniej obchodzil sztywne okna i margin guard,
  - runtime zachowuje ostatni poprawny kontekst i nie kasuje go przy pustym cyklu bez nowego bara.
- Po restarcie `MT5` `EURUSD` utrzymuje juz sensowny stan kontekstowy:
  - `market_regime=BREAKOUT`
  - `spread_regime=GOOD`
  - `execution_regime=GOOD`
  - `confidence_bucket=HIGH`
  - `last_setup_type=SETUP_TREND`
- Latencja lokalna `EURUSD` po poprawce pozostaje niska i nie wskazuje na drastyczny koszt nowej warstwy.
- Zapisano raport walidacyjny:
  - `EVIDENCE/eurusd_context_validation_latest.json`
  - `EVIDENCE/eurusd_context_validation_latest.txt`

## 2026-03-13 09:50 CET

- Do `EURUSD` wdrozono dodatkowa warstwe inteligencji pomocniczej wzorowana na starym `SafetyBocie`, ale juz w czystym `MQL5`:
  - adapter swiec japonskich,
  - adapter `Renko`,
  - warstwe fuzji pomocniczej nad sygnalem bazowym.
- Dodano moduly:
  - `MQL5/Include/Core/MbCandleAdvisory.mqh`
  - `MQL5/Include/Core/MbRenkoAdvisory.mqh`
  - `MQL5/Include/Core/MbAuxSignalFusion.mqh`
- Warstwa nie zastapila bazowej strategii `EURUSD`. Zostala dodana jako:
  - wzmacniacz sygnalu,
  - oslabienie sygnalu przy konflikcie,
  - blokada tylko przy mocnym podwojnym konflikcie.
- Dodatkowy kontekst jest juz zapisywany do runtime:
  - `candle_bias`
  - `candle_quality_grade`
  - `candle_score`
  - `renko_bias`
  - `renko_quality_grade`
  - `renko_score`
  - `renko_run_length`
  - `renko_reversal_flag`
- Po wdrozeniu:
  - `MicroBot_EURUSD` kompiluje sie poprawnie
  - caly park `11/11` nadal kompiluje sie poprawnie
  - layout projektu nadal przechodzi walidacje
- Szczegoly:
  - `DOCS/29_EURUSD_AUXILIARY_INTELLIGENCE_V1.md`

## 2026-03-13 - EURUSD learning path stabilization

- `EURUSD` pozostaje jedynym instrumentem z rozszerzona warstwa:
  - reżim rynku
  - świece
  - `Renko`
  - fuzja pomocnicza
  - kontekstowe uczenie `v2`
- wykryto i naprawiono blad, przez ktory paper close resetowal stan pozycji przed zapisem uczenia
- po poprawce `learning_observations_v2.csv` zaczal zapisywac poprawne rekordy kontekstowe
- `EURUSD` otwiera i zamyka paper-pozycje z nowa warstwa aktywna
- szum w `decision_events.csv` zostal ograniczony przez throttling wpisow `AUX`
- nowa warstwa nie zostala jeszcze rozlana na `FX_MAIN`; nadal trwa strojenie tylko na `EURUSD`

## 2026-03-13 - EURUSD noise reduction and paper coherence

- warstwa `AUX` zostala zregulowana tak, aby:
  - ignorowac slabe, nieakcyjne sygnaly pomocnicze,
  - traktowac je jako `AUX_MIXED` lub `AUX_INCONCLUSIVE`,
  - blokowac lub ostrzegac tylko przy realnym konflikcie
- przy otwartej paper-pozycji `EURUSD` nie miele juz pelnej sciezki wejscia bez potrzeby
- log `SCAN` zostal odchudzony przez throttling `SCORE_BELOW_TRIGGER`
- po tych zmianach w czystym oknie kontrolnym:
  - `PAPER_CLOSE` i `PAPER_OPEN` nadal zachodza
  - `AUX_CONFLICT_CAUTION` spadl do zdrowego poziomu
  - kolejne obserwacje runtime staly sie czytelniejsze

## 2026-03-13 - EURUSD recurrent-noise hardening

- dodatkowo ograniczono nawracajacy halas runtime dla `EURUSD`:
  - `AUX_INCONCLUSIVE` nie jest juz logowane jako wpis o niskiej wartosci diagnostycznej
  - `AUX_MIXED` jest pomijane przy slabym sygnale bazowym
  - `POSITION_ALREADY_OPEN` zostalo mocniej throttlowane
  - `PAPER_IGNORE_OUTSIDE_TRADE_WINDOW` i `PAPER_IGNORE_TRADE_DISABLED` dostaly dluzszy throttle
- wykonano dedykowany raport latencji tylko dla `EURUSD`:
  - srednia `0.0126 ms`
  - maksimum `1.095 ms`
- po wdrozeniu i restarcie `MT5`:
  - `MicroBot_EURUSD` laduje sie poprawnie
  - nowa regulacja nie pokazala regresji szybkosci
  - `learning_observations_v2.csv` pozostaje czystym zrodlem nowej nauki
## 2026-03-13 - EURUSD permissions and bucket cleanup

- rozdzielono w runtime `trade_permissions_ok` od surowych flag `raw_trade_permissions_ok`
- dodano `paper_runtime_override_active` do stanu i raportow `EURUSD`
- `learning_bucket_summary_v1.csv` ignoruje juz bucketowe smieci typu `NONE/UNKNOWN`
- kompilacja `11/11` po zmianie: `OK`
- restart `MT5` i ponowne zaladowanie `MicroBot_EURUSD`: `OK`

## 2026-03-13 - Shared propagation package

- dodano praktyczna warstwe pomiedzy planem propagacji a pozniejszym wdrozeniem wspolnych zmian
- powstaly narzedzia:
  - `TOOLS/PREPARE_SHARED_PROPAGATION_PACKAGE.ps1`
  - `TOOLS/VALIDATE_PROPAGATION_PACKAGE.ps1`
- pakiet wspolnej propagacji dla `FX_MAIN` z `EURUSD` zostal wygenerowany do:
  - `EVIDENCE/PROPAGATION_PACKAGE/PACKAGE_FX_MAIN_EURUSD`
- walidacja pakietu przeszla `ok=true`
- pakiet zawiera tylko wspolne pliki `Core`, helpery strategii oraz wybrane narzedzia i dokumentacje
- pakiet nie zawiera:
  - lokalnych strategii symbolowych
  - lokalnych profili
  - eksperta `EURUSD`
  - eksperymentalnej prywatnej warstwy kontekstowej `EURUSD`
- celem pakietu jest przygotowanie bezpiecznego zrodla wspolnych zmian bez naruszania genotypu innych mikro-botow

## 2026-03-13 - EURUSD gentle bucket tuning

- po analizie bucketow uczenia `EURUSD` stwierdzono, ze:
  - `SETUP_BREAKOUT` pozostaje najslabszym wzorcem,
  - `SETUP_REJECTION` w `RANGE` pozostaje najlepszym dodatnim bucketem
- wdrozono delikatne strojenie tylko dla `EURUSD`:
  - lekki globalny hamulec dla `SETUP_BREAKOUT`
  - dodatkowe przyciecie breakoutow w `CHAOS`, `RANGE` i przy konflikcie `AUX`
  - lekka premia dla `SETUP_REJECTION` w `RANGE`
- zmiana zostala poprawnie skompilowana, skopiowana do terminala i zaladowana po restarcie `MT5`
- nie zaobserwowano regresji kompilacji ani ladowania ekspertow
- pelny efekt runtime wymaga jeszcze kolejnego swiezego cyklu paper po restarcie
## 2026-03-13 - GBPUSD context layer v1

- `Strategy_GBPUSD.mqh` zostala dopieta do `MbFamilyStrategyCommon`, co zamknelo blad kompilacji i pozwolilo uruchomic pelny runtime `GBPUSD`.
- `MicroBot_GBPUSD.mq5` wszedl na nowa sciezke paper/context learning zgodna z dopracowanym wzorcem `EURUSD`, ale z zachowaniem lokalnego genotypu `GBPUSD`.
- Potwierdzony zostal pierwszy pelny cykl:
  - `PAPER_OPEN`
  - `PAPER_CLOSE`
  - zapis `learning_observations_v2.csv`
  - zapis `learning_bucket_summary_v1.csv`
- Runtime `GBPUSD` po wdrozeniu:
  - `trade_permissions_ok=true`
  - `paper_runtime_override_active=true`
  - `market_regime=BREAKOUT`
  - `last_setup_type=SETUP_TREND`
- Lokalna latencja pozostala bardzo niska:
  - avg `5 us`
  - max `13 us`

## 2026-03-13 - USDCAD context layer v1

- `Strategy_USDCAD.mqh` i `MicroBot_USDCAD.mq5` zostaly dopiete do nowej sciezki paper/context learning zgodnej z wzorcem `EURUSD`, ale z zachowaniem lokalnego genotypu `USDCAD`.
- Potwierdzony zostal pierwszy pelny cykl:
  - `PAPER_OPEN`
  - `PAPER_CLOSE`
  - zapis `learning_observations_v2.csv`
  - zapis `learning_bucket_summary_v1.csv`
- Potwierdzone rekordy `v2` zawieraja juz pelny kontekst:
  - `SETUP_BREAKOUT`
  - `market_regime=BREAKOUT`
  - `spread_regime=CAUTION`
  - `execution_regime=GOOD`
  - `confidence_bucket=HIGH`
  - `close_reason=PAPER_TIMEOUT`
- Runtime `USDCAD` po wdrozeniu:
  - `trade_permissions_ok=true`
  - `paper_runtime_override_active=true`
  - `market_regime=BREAKOUT`
  - `last_setup_type=SETUP_BREAKOUT`
- Pierwszy bucket summary dla `USDCAD`:
  - `SETUP_BREAKOUT / BREAKOUT`
  - `samples=2`
  - `wins=1`
  - `losses=1`
  - `pnl_sum=-0.22`
- Lokalna latencja pozostala bardzo niska:
  - avg `7 us`
  - max `15 us`

## 2026-03-13 - NZDUSD context layer v1

- `Strategy_NZDUSD.mqh` i `MicroBot_NZDUSD.mq5` zostaly dopiete do nowej sciezki paper/context learning zgodnej z wzorcem `EURUSD`, ale z zachowaniem lokalnego genotypu `NZDUSD`.
- Potwierdzony zostal pierwszy pelny cykl:
  - `PAPER_OPEN`
  - `PAPER_CLOSE`
  - zapis `learning_observations_v2.csv`
  - zapis `learning_bucket_summary_v1.csv`
- Potwierdzony rekord `v2` zawiera juz pelny kontekst:
  - `SETUP_RANGE`
  - `market_regime=TREND`
  - `spread_regime=CAUTION`
  - `execution_regime=GOOD`
  - `confidence_bucket=LOW`
  - `close_reason=PAPER_SL`
- Runtime `NZDUSD` po wdrozeniu:
  - `trade_permissions_ok=true`
  - `paper_runtime_override_active=true`
  - `market_regime=TREND`
  - `last_setup_type=SETUP_RANGE`
- Pierwszy bucket summary dla `NZDUSD`:
  - `SETUP_RANGE / TREND`
  - `samples=1`
  - `wins=0`
  - `losses=1`
  - `pnl_sum=-2.17`

## 2026-03-13 - USDJPY context layer v1

- `Strategy_USDJPY.mqh` i `MicroBot_USDJPY.mq5` zostaly dopiete do nowej sciezki paper/context learning zgodnej ze wzorcem `EURUSD`, ale z zachowaniem genotypu rodziny `FX_ASIA`.
- Usunieto techniczny blad po starszej nazwie funkcji summary; `MbAppendLearningObservationV2(...)` zostalo pozostawione jako jedyne zrodlo aktualizacji bucket summary.
- Potwierdzony zostal pierwszy pelny cykl:
  - `PAPER_OPEN`
  - `PAPER_CLOSE`
  - zapis `learning_observations_v2.csv`
  - zapis `learning_bucket_summary_v1.csv`
- Potwierdzony rekord `v2` zawiera juz pelny kontekst:
  - `SETUP_BREAKOUT`
  - `market_regime=TREND`
  - `spread_regime=CAUTION`
  - `execution_regime=GOOD`
  - `confidence_bucket=LOW`
  - `close_reason=PAPER_TIMEOUT`
- Runtime `USDJPY` po wdrozeniu:
  - `trade_permissions_ok=true`
  - `paper_runtime_override_active=true`
  - `market_regime=TREND`
  - `last_setup_type=SETUP_BREAKOUT`
- Pierwszy bucket summary dla `USDJPY`:
  - `SETUP_BREAKOUT / TREND`
  - `samples=1`
  - `wins=1`
  - `losses=0`
  - `pnl_sum=0.00`

## 2026-03-13 - indywidualne strojenie GBPUSD, USDCAD i USDCHF

- Na bazie wnioskow z dojrzalego `EURUSD` wykonano pierwsze, juz indywidualne strojenie trzech kolejnych par:
  - `GBPUSD`
  - `USDCAD`
  - `USDCHF`
- Zmiany byly prowadzone sekwencyjnie, bez ruszania `EURUSD` i bez rozlewania eksperymentu na cala rodzine.
- Wspolna zasada byla jedna:
  - zachowac genotyp pary
  - przyciac te miejsca, ktore bucketowe uczenie i biezacy runtime pokazaly jako najslabsze

### GBPUSD
- wzmocniono ostroznosc przy `spread_regime=CAUTION`
- przycieto `SETUP_TREND` w `RANGE`
- `SETUP_REJECTION` w `RANGE` dostaje premie tylko przy realnym wsparciu `AUX`
- aktualnie:
  - `signal_confidence=0.1240`
  - `signal_risk_multiplier=0.6000`
  - `wins/losses=5/32`

### USDCAD
- breakout zostal przyciety globalnie i dodatkowo w:
  - `CHAOS`
  - `TREND`
  - `spread_regime=CAUTION`
- dodano mocniejsze znaczenie warstwy `AUX`
- aktualnie:
  - `signal_confidence=0.0000`
  - `signal_risk_multiplier=0.5500`
  - `wins/losses=7/27`

### USDCHF
- wykonano najmocniejsze dostrojenie defensywne:
  - breakout tax
  - caps dla confidence/risk przy serii strat
  - caps przy negatywnym `learning_bias`
  - caps przy slabym sygnale swiec i bez mocnego `AUX`
- aktualnie:
  - `signal_confidence=0.5200`
  - `signal_risk_multiplier=0.7800`
  - `wins/losses=2/26`
- najwazniejsze: zlamano dawny problem nadmiernej pewnosci siebie przy bardzo slabych bucketach

## 2026-03-13 - indywidualne strojenie USDJPY, AUDUSD i NZDUSD

- Po domknieciu pierwszej trojki `FX_MAIN` wykonano kolejny blok prac sekwencyjnych na:
  - `USDJPY`
  - `AUDUSD`
  - `NZDUSD`
- Zmiany byly prowadzone pojedynczo, bez ruszania `EURUSD` i bez rozlewania eksperymentu na cala rodzine.
- Zasada pozostala ta sama:
  - zachowac genotyp instrumentu
  - wdrozyc tylko te korekty, ktore maja silne uzasadnienie w bucketach, runtime i dotychczasowych porazkach zwyciestwach wzorca `EURUSD`

### USDJPY
- breakout zostal przytemperowany przy:
  - `CHAOS`
  - konflikcie swiec i `Renko`
  - dluzszej serii strat albo negatywnym `learning_bias`
- zachowano genotyp `FX_ASIA` i lokalna role breakoutu

### AUDUSD
- `SETUP_RANGE` zostal oslabiony przy:
  - slabej swiecy
  - pustym lub nieczytelnym `Renko`
  - dluzszej serii strat
- zachowano lokalna range-aware nature `AUDUSD`

### NZDUSD
- wykonano najmocniejsze strojenie defensywne z calej trojki:
  - dodatkowe kary dla `SETUP_RANGE` w zlym srodowisku
  - silniejsze capy przy bardzo negatywnym `learning_bias`
  - silniejsze capy przy dlugim `loss_streak`
- celem bylo zahamowanie bardzo slabej, historycznie przegrywajacej sciezki range

Najuczciwszy wniosek:

- `USDJPY`, `AUDUSD` i `NZDUSD` sa juz na nowej sciezce paper/context learning
- kazda z tych par dostala lokalne strojenie pod swoj genotyp
- etap zostal domkniety technicznie, ale wymaga spokojnej obserwacji runtime przed kolejna ingerencja


- Domknieto ostatnia czworke par w modelu pojedynczego strojenia bez ruszania `EURUSD`.
- Kazda para zostala potraktowana osobno:
  - `EURJPY`
  - `GBPJPY`
  - `EURAUD`
- Wspolna zasada pozostala taka sama:
  - zachowac genotyp
  - wdrozyc nowa sciezke context/paper/learning
  - przyciac najbardziej kosztowne i historycznie przegrywajace zachowania

### EURJPY
- breakout zostal ograniczony w `CHAOS`, `RANGE` i przy `BAD spread`
- dodano lekka preferencje dla `SETUP_PULLBACK` w `TREND`
- aktualny obraz po wdrozeniu:
  - `market_regime=CHAOS`
  - `spread_regime=BAD`
  - `signal_confidence=0.2300`
  - `signal_risk_multiplier=0.5500`

### GBPJPY
- najmocniej dociagnieto filtry dla crossa JPY:
  - breakout tax
  - range penalties w slabym srodowisku
  - tylko selektywne wsparcie trendu
- aktualny obraz po wdrozeniu:
  - `market_regime=CHAOS`
  - `spread_regime=BAD`
  - `signal_confidence=0.0474`
  - `signal_risk_multiplier=0.6000`
- to jedyna para z tej czworki, ktora po wdrozeniu nadal handlowala wyrazniej na paper

### EURAUD
- zachowano range-aware genotyp crossa AUD
- breakout zostal przycisniety przy zlym spreadzie i slabym `Renko`
- range dostal premie tylko w zdrowym `RANGE`
- aktualny obraz po wdrozeniu:
  - `market_regime=CHAOS`
  - `spread_regime=BAD`
  - `signal_confidence=0.4545`
  - `signal_risk_multiplier=0.5733`

- dostal najmocniejsze defensywne filtrowanie z calej czworki
- szczegolnie przy:
  - `BAD spread`
  - `CHAOS`
  - slabszym `Renko`
- aktualny obraz po wdrozeniu:
  - `market_regime=CHAOS`
  - `spread_regime=BAD`
  - `signal_confidence=0.4226`
  - `signal_risk_multiplier=0.5500`

Najuczciwszy wniosek:

- cala jedenastka ma juz nowa sciezke context/paper/learning
- `EURUSD` pozostaje najbardziej dojrzalym wzorcem
- ostatnia czworka zostala wdrozona poprawnie technicznie, ale wymaga dluzszej obserwacji, bo obecnie blokuje ja glownie koszt i niski confidence, a nie bledy architektoniczne
## 2026-03-13 - EURUSD plan kolejnych zmian

Po ciężkim audycie krzyżowym dla `EURUSD` przygotowano osobny plan dalszego strojenia:
- [41_EURUSD_NEXT_CHANGE_PLAN.md](C:\MAKRO_I_MIKRO_BOT\DOCS\41_EURUSD_NEXT_CHANGE_PLAN.md)

Plan zakłada dalszą pracę wyłącznie na `EURUSD` w trybie sekwencyjnym:
- jedna zmiana,
- obserwacja,
- kolejna zmiana.

Najważniejsze obszary do dalszej regulacji:
- ograniczenie stratnych wejść `TREND/BREAKOUT`,
- zmniejszenie liczby `PAPER_TIMEOUT`,
- osłabienie nadmiernej pewności siebie przy słabym wyniku netto,
- lepsze wykorzystanie warstw świec i `Renko`,
- uczciwsza diagnostyka latencji.

## 2026-03-13 - EURUSD Krok 1 wdrozony

- Wdrożono pierwszy krok planu z [41_EURUSD_NEXT_CHANGE_PLAN.md](C:\MAKRO_I_MIKRO_BOT\DOCS\41_EURUSD_NEXT_CHANGE_PLAN.md).
- Zmiana dotyczy tylko `EURUSD`.
- `SETUP_TREND` zostal lekko przyciety w:
  - `BREAKOUT`
  - `CHAOS`
  - `spread_regime=CAUTION`
  - sytuacji bez wsparcia `AUX`
- Charakter zmiany:
  - delikatny, sekwencyjny, bez ruszania innych par i bez dokładania kolejnych regulacji jednocześnie
- Cel:
  - poprawic jakosc wejsc bez utraty lekkosci runtime i bez zacierania relacji przyczyna-skutek

## 2026-03-14 - ciezki audyt i sprzatanie systemowe

- Wykonano pelny audyt projektu:
  - walidacja layoutu `OK`
  - testy kontraktowe `OK`
  - testy scenariuszy rodzin `OK`
  - kompilacja `11/11` mikro-botow `OK`
- Dodano narzedzie:
  - [AUDIT_AND_CLEAN_RUNTIME_ARTIFACTS.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\AUDIT_AND_CLEAN_RUNTIME_ARTIFACTS.ps1)
- Uporzadkowano artefakty runtime:
  - usunieto osierocone katalogi `true` z `state`, `logs`, `run`, `key`
  - usunieto tymczasowy katalog `_restore_tmp_101302`
- Raport audytu:
  - [SYSTEM_HEAVY_AUDIT_AND_CLEANUP_20260314.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\SYSTEM_HEAVY_AUDIT_AND_CLEANUP_20260314.md)

## 2026-03-14 - Lokalny Agent Strojenia V1

- Dodano pierwszy praktyczny `v1` lokalnego Agenta Strojenia dla `EURUSD`.
- Agent zostal zbudowany jako duet:
  - kapitan strojenia:
    - [MbTuningLocalAgent.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningLocalAgent.mqh)
  - techniczny pomocnik danych:
    - [MbTuningDeckhand.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningDeckhand.mqh)
- Stan i journale:
  - [MbTuningTypes.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningTypes.mqh)
  - [MbTuningStorage.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningStorage.mqh)
- Integracja aktywna:
  - [MicroBot_EURUSD.mq5](C:\MAKRO_I_MIKRO_BOT\MQL5\Experts\MicroBots\MicroBot_EURUSD.mq5)
  - [Strategy_EURUSD.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Strategies\Strategy_EURUSD.mqh)
- Agent dziala:
  - na `OnTimer`
  - poza hot-path
  - w cyklu serwisowym `300s` lub po zmianie liczby probek uczenia
  - na lokalnych danych `learning_observations_v2`, `learning_bucket_summary_v1`, `runtime_state`
  - w granicach bezpiecznych, malych zmian parametrow
- Dokument referencyjny:
  - [42_LOCAL_TUNING_AGENT_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\42_LOCAL_TUNING_AGENT_V1.md)
  - [43_TUNING_AGENT_ARCHITECTURE_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\43_TUNING_AGENT_ARCHITECTURE_V1.md)
- Raport wdrozenia i runtime:
  - [LOCAL_TUNING_AGENT_V1_IMPLEMENTATION_20260314.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\LOCAL_TUNING_AGENT_V1_IMPLEMENTATION_20260314.md)

## 2026-03-14 - Baza pod agentow rodzinnych i koordynatora

- Dodano kod warstw wyzszych strojenia:
  - [MbTuningFamilyAgent.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningFamilyAgent.mqh)
  - [MbTuningCoordinator.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningCoordinator.mqh)
- Rozszerzono typy i storage:
  - [MbTuningTypes.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningTypes.mqh)
  - [MbTuningStorage.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningStorage.mqh)
- Dodano lokalne narzedzie budowy seedow floty strojenia:
  - [BUILD_TUNING_FLEET_BASELINE.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\BUILD_TUNING_FLEET_BASELINE.ps1)
- Dokumentacja:
  - [44_FAMILY_TUNING_AGENT_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\44_FAMILY_TUNING_AGENT_V1.md)
  - [45_TUNING_COORDINATOR_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\45_TUNING_COORDINATOR_V1.md)
  - [46_TUNING_FLEET_BASELINE_TOOL.md](C:\MAKRO_I_MIKRO_BOT\DOCS\46_TUNING_FLEET_BASELINE_TOOL.md)
  - [47_TUNING_HIERARCHY_APPLY_AND_VALIDATE.md](C:\MAKRO_I_MIKRO_BOT\DOCS\47_TUNING_HIERARCHY_APPLY_AND_VALIDATE.md)
- Raport wdrozenia:
  - [TUNING_HIERARCHY_IMPLEMENTATION_20260314.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\TUNING_HIERARCHY_IMPLEMENTATION_20260314.md)

## 2026-03-14 - Rollout mostu strojenia na dojrzale FX_MAIN

- Most `lokalny -> rodzina -> flota` zostal rozszerzony z `EURUSD` na:
  - `GBPUSD`
  - `USDCAD`
  - `USDCHF`
- Strategie tych par dostaly warstwe polityki strojenia:
  - setter polityki lokalnej,
  - overlay breakout/trend/rejection,
  - limity `confidence_cap` i `risk_cap`
- Mikro-boty tych par dostaly:
  - serwis strojenia na `OnTimer`,
  - polityke skuteczna `tuning_policy_effective.csv`,
  - podpiecie do rodziny `FX_MAIN` i koordynatora floty,
  - deckhanda technicznego i stan lokalnego strojenia
- Potwierdzony runtime:
  - po restarcie `MT5` cala jedenastka zaladowala sie poprawnie,
  - `GBPUSD`, `USDCAD` i `USDCHF` zapisaly skuteczna polityke strojenia
- Dokumentacja:
  - [50_FX_MAIN_TUNING_BRIDGE_ROLLOUT_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\50_FX_MAIN_TUNING_BRIDGE_ROLLOUT_V1.md)
- Raport runtime:
  - [FX_MAIN_TUNING_BRIDGE_RUNTIME_20260314.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\FX_MAIN_TUNING_BRIDGE_RUNTIME_20260314.md)

## 2026-03-14 - Offline analiza kontrfaktyczna strojenia

- Dodano narzedzie:
  - [ANALYZE_COUNTERFACTUAL_TUNING.py](C:\MAKRO_I_MIKRO_BOT\TOOLS\ANALYZE_COUNTERFACTUAL_TUNING.py)
- Narzedzie analizuje dane historyczne `learning_observations_v2.csv` i szuka:
  - filtrow blokujacych najbardziej toksyczne wejscia,
  - kandydatow na `confidence gate`,
  - sytuacji, gdzie lepiej scisnac ryzyko niz twardo blokowac
- Dokumentacja:
  - [51_COUNTERFACTUAL_TUNING_ANALYZER.md](C:\MAKRO_I_MIKRO_BOT\DOCS\51_COUNTERFACTUAL_TUNING_ANALYZER.md)
- Raport dla `FX_MAIN`:
  - [COUNTERFACTUAL_TUNING_FX_MAIN_20260314_111929.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\COUNTERFACTUAL_TUNING_FX_MAIN_20260314_111929.md)
  - [COUNTERFACTUAL_TUNING_FX_MAIN_20260314_111929.json](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\COUNTERFACTUAL_TUNING_FX_MAIN_20260314_111929.json)
- Najwazniejszy wniosek:
  - problemem nie jest jedna liczba, tylko cale klasy toksycznych wejsc,
  - weekend jest dobry na budowe hipotez,
  - wdrozenia trzeba dalej prowadzic sekwencyjnie po otwarciu rynku

## 2026-03-14 - Profil zwyciestw i playbook na otwarcie

- Dodano drugie narzedzie offline:
  - [ANALYZE_WIN_LOSS_PROFILES.py](C:\MAKRO_I_MIKRO_BOT\TOOLS\ANALYZE_WIN_LOSS_PROFILES.py)
- Narzedzie odroznia:
  - co bylo toksyczne,
  - co bylo zwycieskie,
  - co warto chronic,
  - co warto tylko docisnac,
  - a czego obecny jezyk strojenia jeszcze nie umie wyrazic
- Raport:
  - [WIN_LOSS_PROFILE_FX_MAIN_20260314_112636.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\WIN_LOSS_PROFILE_FX_MAIN_20260314_112636.md)
  - [WIN_LOSS_PROFILE_FX_MAIN_20260314_112636.json](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\WIN_LOSS_PROFILE_FX_MAIN_20260314_112636.json)
- Zlozono tez weekendowy playbook dla `FX_MAIN`:
  - [FX_MAIN_WEEKEND_TUNING_PLAYBOOK_20260314.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\FX_MAIN_WEEKEND_TUNING_PLAYBOOK_20260314.md)
- Zapisano kandydat ustawien na poniedzialek:
  - [monday_candidate_fx_main_20260314.json](C:\MAKRO_I_MIKRO_BOT\RUN\TUNING\monday_candidate_fx_main_20260314.json)

## 2026-03-14 - Rozszerzenie jezyka strojenia i playbook pierwszej godziny

- Lokalny jezyk strojenia rozszerzono o trzy nowe pojecia:
  - `require_support_for_rejection`
  - `require_non_poor_renko_for_breakout`
  - `require_non_poor_candle_for_trend`
- Nowe filtry zostaly wdrozone dla:
  - `EURUSD`
  - `GBPUSD`
  - `USDCAD`
  - `USDCHF`
- Po rozszerzeniu schematu stary journal `tuning_actions.csv` dla `EURUSD` zostal odlozony do archiwum, aby nie mieszac starego i nowego ukladu kolumn
- Dokumentacja:
  - [52_TUNING_LANGUAGE_EXTENSIONS_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\52_TUNING_LANGUAGE_EXTENSIONS_V1.md)
- Przygotowano tez playbook pierwszej godziny po ponownym otwarciu rynku dla `FX_MAIN`:
  - [53_FIRST_HOUR_REOPEN_PLAYBOOK_FX_MAIN.md](C:\MAKRO_I_MIKRO_BOT\DOCS\53_FIRST_HOUR_REOPEN_PLAYBOOK_FX_MAIN.md)
  - [first_hour_guardrails_fx_main_20260314.json](C:\MAKRO_I_MIKRO_BOT\RUN\TUNING\first_hour_guardrails_fx_main_20260314.json)

## 2026-03-14 - Rollout mostu strojenia na FX_ASIA i analiza weekendowa

- Most `lokalny -> rodzina -> flota` rozszerzono na:
  - `USDJPY`
  - `AUDUSD`
  - `NZDUSD`
- Mikro-boty tej rodziny dostaly:
  - lokalna polityke strojenia,
  - polityke skuteczna `tuning_policy_effective.csv`,
  - deckhanda technicznego,
  - serwis `OnTimer` dla lokalnego strojenia,
  - most do rodziny `FX_ASIA` i koordynatora floty
- Strategie tej rodziny dostaly:
  - setter polityki strojenia,
  - filtry breakout/trend po lokalnej polityce,
  - nowe bramki `Renko` i swiecy tam, gdzie maja sens
- Dokumentacja:
  - [54_FX_ASIA_TUNING_BRIDGE_ROLLOUT_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\54_FX_ASIA_TUNING_BRIDGE_ROLLOUT_V1.md)
- Raporty offline:
  - [COUNTERFACTUAL_TUNING_FX_ASIA_20260314_122835.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\COUNTERFACTUAL_TUNING_FX_ASIA_20260314_122835.md)
  - [WIN_LOSS_PROFILE_FX_ASIA_20260314_122835.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\WIN_LOSS_PROFILE_FX_ASIA_20260314_122835.md)
  - [FX_ASIA_WEEKEND_TUNING_PLAYBOOK_20260314.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\FX_ASIA_WEEKEND_TUNING_PLAYBOOK_20260314.md)
- Zapisano kandydat ustawien na otwarcie:
  - [monday_candidate_fx_asia_20260314.json](C:\MAKRO_I_MIKRO_BOT\RUN\TUNING\monday_candidate_fx_asia_20260314.json)

## 2026-03-14 - Candidate signal journal i guardraile otwarcia dla FX_ASIA

- Dodano nowy journal diagnostyczny:
  - `candidate_signals.csv`
- Journal zostal wpiety do dostrojonych mikro-botow rodzin:
  - `FX_MAIN`
  - `FX_ASIA`
- Journal zapisuje kandydatow na etapach:
  - `EVALUATED`
  - `SIZE_BLOCK`
  - `PRECHECK_BLOCK`
  - `PAPER_OPEN`
  - `EXEC_SEND_OK`
  - `EXEC_SEND_ERROR`
- Majtek techniczny zostal rozszerzony o:
  - zliczanie kandydatow,
  - wykrywanie zbyt zaszumionego `candidate_signals.csv`,
  - dopisywanie tych danych do wlasnego journala i stanu lokalnego
- Dokumentacja:
  - [55_CANDIDATE_SIGNAL_JOURNAL_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\55_CANDIDATE_SIGNAL_JOURNAL_V1.md)
  - [56_FIRST_HOUR_REOPEN_PLAYBOOK_FX_ASIA.md](C:\MAKRO_I_MIKRO_BOT\DOCS\56_FIRST_HOUR_REOPEN_PLAYBOOK_FX_ASIA.md)
- Przygotowano tez guardraile pierwszej godziny dla `FX_ASIA`:
  - [first_hour_guardrails_fx_asia_20260314.json](C:\MAKRO_I_MIKRO_BOT\RUN\TUNING\first_hour_guardrails_fx_asia_20260314.json)

## 2026-03-14 - Schema reset journali runtime i domkniecie candidate journal

- Dodano narzedzie:
  - [RESET_RUNTIME_JOURNAL_SCHEMA.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\RESET_RUNTIME_JOURNAL_SCHEMA.ps1)
- Narzedzie zostalo uzyte do archiwizacji starego `tuning_deckhand.csv` dla siedmiu dostrojonych symboli
- Lokalny serwis strojenia wymusza teraz odtworzenie journala deckhanda, jesli plik zniknal po schema reset
- `candidate_signals.csv` zostal domkniety tak, aby tworzyc pusty plik z naglowkiem juz przy inicjalizacji eksperta
- Dokumentacja:
  - [57_RUNTIME_JOURNAL_SCHEMA_RESET.md](C:\MAKRO_I_MIKRO_BOT\DOCS\57_RUNTIME_JOURNAL_SCHEMA_RESET.md)
- Evidence:
  - [CANDIDATE_SIGNAL_JOURNAL_ROLLOUT_20260314.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\CANDIDATE_SIGNAL_JOURNAL_ROLLOUT_20260314.md)

## 2026-03-14 - Rollout mostu strojenia na FX_CROSS i analiza weekendowa

- Most `lokalny -> rodzina -> flota` rozszerzono na:
  - `EURJPY`
  - `GBPJPY`
  - `EURAUD`
- Mikro-boty tej rodziny dostaly:
  - lokalna polityke strojenia,
  - polityke skuteczna `tuning_policy_effective.csv`,
  - deckhanda technicznego,
  - serwis `OnTimer` dla lokalnego strojenia,
  - journal `candidate_signals.csv`,
  - most do rodziny `FX_CROSS` i koordynatora floty
- Strategie tej rodziny dostaly:
  - setter polityki strojenia,
  - mapowanie `SETUP_PULLBACK` jako trend-like,
  - mapowanie `SETUP_RANGE` jako mean-reversion-like,
  - filtry breakout/trend-like po lokalnej polityce,
  - nowe bramki `Renko` i swiecy tam, gdzie maja sens
- Dokumentacja:
  - [58_FX_CROSS_TUNING_BRIDGE_ROLLOUT_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\58_FX_CROSS_TUNING_BRIDGE_ROLLOUT_V1.md)
  - [59_FIRST_HOUR_REOPEN_PLAYBOOK_FX_CROSS.md](C:\MAKRO_I_MIKRO_BOT\DOCS\59_FIRST_HOUR_REOPEN_PLAYBOOK_FX_CROSS.md)
  - [60_FX_CROSS_TUNING_LANGUAGE_MAPPING_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\60_FX_CROSS_TUNING_LANGUAGE_MAPPING_V1.md)
- Raport runtime:
  - [FX_CROSS_TUNING_BRIDGE_RUNTIME_20260314.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\FX_CROSS_TUNING_BRIDGE_RUNTIME_20260314.md)
- Raporty offline:
  - [COUNTERFACTUAL_TUNING_FX_CROSS_20260314_131720.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\COUNTERFACTUAL_TUNING_FX_CROSS_20260314_131720.md)
  - [WIN_LOSS_PROFILE_FX_CROSS_20260314_131720.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\WIN_LOSS_PROFILE_FX_CROSS_20260314_131720.md)
  - [FX_CROSS_WEEKEND_TUNING_PLAYBOOK_20260314.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\FX_CROSS_WEEKEND_TUNING_PLAYBOOK_20260314.md)
- Zapisano kandydat ustawien na otwarcie:
  - [monday_candidate_fx_cross_20260314.json](C:\MAKRO_I_MIKRO_BOT\RUN\TUNING\monday_candidate_fx_cross_20260314.json)
- Dodano guardraile pierwszej godziny dla `FX_CROSS`:
  - [first_hour_guardrails_fx_cross_20260314.json](C:\MAKRO_I_MIKRO_BOT\RUN\TUNING\first_hour_guardrails_fx_cross_20260314.json)

## 2026-03-14 - Przygotowanie nienaruszalnego kontraktu ryzyka kapitalu

- Przygotowano wspolny kontrakt kapitalowy dla dwoch trybow:
  - `paper`
  - `live`
- Kontrakt rozdziela:
  - twarde limity kapitalowe,
  - lokalne geny symboli,
  - adaptacyjne strojenie agentow
- Dokumentacja:
  - [61_IMMUTABLE_CAPITAL_RISK_CONTRACT_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\61_IMMUTABLE_CAPITAL_RISK_CONTRACT_V1.md)
- Kandydat maszynowy:
  - [capital_risk_contract_v1.json](C:\MAKRO_I_MIKRO_BOT\CONFIG\capital_risk_contract_v1.json)
- Najwazniejsza decyzja projektowa:
  - agenci i runtime moga tylko obnizac ryzyko w granicach kontraktu,
  - ale nie moga zmieniac samych wartosci kontraktu bez recznej decyzji

## 2026-03-14 - Wdrozenie egzekwowania kontraktu ryzyka kapitalu

- Dodano warstwe runtime:
  - [MbCapitalRiskContract.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbCapitalRiskContract.mqh)
- Guardy rynku zostaly rozszerzone tak, aby:
  - `paper` liczyl hard loss z `realized_pnl_day/session`,
  - `live` liczyl hard loss z realnego `equity`,
  - symbol mial dodatkowy twardy limit dziennej straty
- Sizing strategii zostal podpiety pod immutable kontrakt:
  - bazowe ryzyko na trade jest clamped przed wyliczeniem lota,
  - `soft daily loss` automatycznie redukuje ryzyko
- Wszystkie `11` mikro-botow dostaly:
  - jawny stan `paper/live` w runtime,
  - bezpieczne post-scaling po `signal_risk_multiplier`,
  - blokade wejscia, jesli kontrakt lub hierarchia zetna ryzyko do zera
- Rodzina i flota licza teraz laczna dzienna strate i potrafia przejsc w twardy freeze po przekroczeniu limitu
- Dokumentacja:
  - [62_CAPITAL_RISK_CONTRACT_ENFORCEMENT_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\62_CAPITAL_RISK_CONTRACT_ENFORCEMENT_V1.md)
- Kontrakt maszynowy:
  - [capital_risk_contract_v1.json](C:\MAKRO_I_MIKRO_BOT\CONFIG\capital_risk_contract_v1.json)
- Swiadomie odlozone na osobny etap:
  - pelne egzekwowanie `max_open_risk_pct` w skali calej floty

## 2026-03-14 - Jeden wspolny playbook operacyjny na poniedzialek

- Przygotowano jeden dokument nadrzedny na poniedzialek `16 marca 2026`:
  - [63_MONDAY_2026_03_16_SESSION_MASTER_PLAYBOOK.md](C:\MAKRO_I_MIKRO_BOT\DOCS\63_MONDAY_2026_03_16_SESSION_MASTER_PLAYBOOK.md)
- Dokument scala:
  - `FX_MAIN`
  - `FX_ASIA`
  - `FX_CROSS`
  - zasady kontraktu kapitalowego
  - kolejnosc obserwacji i interwencji
- Celem tego playbooka jest zastapienie rozproszonych instrukcji jednym spokojnym planem na pierwszy wazny dzien pracy po weekendzie

## 2026-03-14 - Research rodziny METALS pod OANDA MT5

- Przygotowano research metalowej rodziny pod przyszly rollout:
  - [64_OANDA_MT5_METALS_FAMILY_RESEARCH_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\64_OANDA_MT5_METALS_FAMILY_RESEARCH_V1.md)
- Potwierdzono brokerowo i lokalnie:
  - `GOLD.pro`
  - `SILVER.pro`
  - `PALLAD.pro`
  - `COPPER-US.pro / XCUUSD`
- Rekomendowana pierwsza czworka do wdrozenia:
  - `GOLD.pro`
  - `SILVER.pro`
  - `COPPER-US.pro / XCUUSD`
- Rekomendowana architektura:
  - nadrzedna rodzina `METALS`
  - podrodziny:
    - `METALS_SPOT_PM`
    - `METALS_FUTURES`
- `PALLAD.pro` zostal oznaczony jako kandydat `phase 2`, a nie pierwszy rollout

## 2026-03-14 - Architektura czasu i blueprint projektu METALS

- Dopięto drugi dokument scalajacy:
  - oficjalne godziny OANDA/TMS,
  - stare okna i rozgrzewki `OANDA_MT5_SYSTEM`,
  - kotwice czasowe `Europe/Warsaw` / `Asia/Tokyo`,
  - propozycje nienakladajacego sie rytmu rodzin.
- Nowe artefakty:
  - [65_METALS_SESSION_AND_TIME_ARCHITECTURE_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\65_METALS_SESSION_AND_TIME_ARCHITECTURE_V1.md)
  - [metals_family_blueprint_v1.json](C:\MAKRO_I_MIKRO_BOT\CONFIG\metals_family_blueprint_v1.json)
  - [METALS_MAKRO_I_MIKRO_BOT\README.md](C:\MAKRO_I_MIKRO_BOT\METALS_MAKRO_I_MIKRO_BOT\README.md)
- Potwierdzono jako kanoniczna nazwe miedzi:
  - `COPPER-US.pro`
- Przyjeto szkic sesji:
  - `FX_ASIA` skracane do `09:00-16:00` Tokio,
  - `FX_AM` `09:00-12:00` PL,
  - `INDEX_EU` `12:00-14:00` PL,
  - `METALS_PM_PREWARM` `13:45-14:00` PL,
  - `METALS_PM_CORE` `14:00-17:00` PL,
  - `METALS_PM_EXT_SHADOW` `17:00-19:00` PL,
  - `INDEX_US` `17:00-20:00` PL.
- Ustalono, ze kolejna rodzina po forexie i metalach bardziej naturalnie wyglada jako `INDEX` / `EQUITY_US`, a nie `ETF` jako pierwszy rollout.

## 2026-03-14 - Macierz okien dla 5 grup i doprecyzowanie ETF

- Dopięto osobny dokument z macierza okien w czasie polskim:
  - [66_SESSION_WINDOW_MATRIX_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\66_SESSION_WINDOW_MATRIX_V1.md)
- Dopięto maszynowy szkic macierzy:
  - [session_window_matrix_v1.json](C:\MAKRO_I_MIKRO_BOT\CONFIG\session_window_matrix_v1.json)
- Wyjasniono, ze:
  - `FX_ASIA 09:00-16:00` dotyczy czasu `Asia/Tokyo`,
  - co daje w Polsce mniej wiecej `01:00-08:00` zima i `02:00-09:00` lato.
- Potwierdzono rozdzial:
  - brokerowo ETF/ETF CFD sa w OANDA UE dostepne,
  - ale dawny system celowo blokowal automatyczne wejscia na `ETF/ETN/EQUITY`.
- Przyjeto operacyjny rytm dnia:
  - `FX_ASIA`
  - `FX_AM`
  - `INDEX_EU`
  - `METALS`
  - `INDEX_US`
- Zapisano tez drugie naturalne "gorki" dla:
  - `FX_ASIA`
  - `METALS`
  - `INDEX_EU`
  - `INDEX_US`
  ale bez natychmiastowego przyznania im prawa do nowych wejsc.

## 2026-03-14 - Brokerowe budzety i limity okien ze starego OANDA_MT5_SYSTEM

- Przygotowano dokument wyciagajacy mechanike budzetow `PRICE / SYS / ORDER`:
  - [67_OANDA_BROKER_BUDGETS_AND_WINDOW_LIMITS_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\67_OANDA_BROKER_BUDGETS_AND_WINDOW_LIMITS_V1.md)
- Potwierdzono, ze stary system nie mial prostych "sztywnych limitow na okno", tylko:
  - dobowe budzety,
  - udzialy per grupa,
  - stopniowe odblokowanie wraz z postepem okna,
  - kontrolowane pozyczanie niewykorzystanego budzetu z innych grup,
  - pacing w oknach dla `FX` i `METAL`.
- Najwazniejsze liczby z dawnego systemu:
  - `price_budget_day = 900`
  - `order_budget_day = 700`
  - `sys_budget_day = 6500`
  - `group_borrow_fraction = 0.65`
  - `group_borrow_unlock_power = 1.2`
- Potwierdzono tez jawne limity z kontraktu audytowego:
  - `PRICE warning = 1000/day`
  - `PRICE cut-off = 5000/day`
  - `MARKET ORDERS = 50/s`
  - `POSITIONS + PENDING = 500`

## 2026-03-14 - Architektura domen wspolnego organizmu: FX, METALS, INDICES

- Ustalono formalnie, ze `MAKRO_I_MIKRO_BOT` nie bedzie rozbijany na osobne systemy dla `FX`, `METALS` i `INDICES`.
- Przyjeto model:
  - jeden wspolny organizm,
  - jeden globalny koordynator sesji i kapitalu,
  - trzy domeny:
    - `FX`
    - `METALS`
    - `INDICES`
- Domena `METALS` zostala podniesiona z roli luźnej rezerwy do roli katalogu domenowego wewnatrz wspolnego organizmu:
  - [METALS_MAKRO_I_MIKRO_BOT\README.md](C:\MAKRO_I_MIKRO_BOT\METALS_MAKRO_I_MIKRO_BOT\README.md)
- Dodano nowy katalog domenowy dla `INDICES`:
  - [INDICES_MAKRO_I_MIKRO_BOT\README.md](C:\MAKRO_I_MIKRO_BOT\INDICES_MAKRO_I_MIKRO_BOT\README.md)
- Dodano wspolny rejestr architektury domen:
  - [domain_architecture_registry_v1.json](C:\MAKRO_I_MIKRO_BOT\CONFIG\domain_architecture_registry_v1.json)
- Dodano blueprint architektury dla przyszlej domeny indeksowej:
  - [indices_family_blueprint_v1.json](C:\MAKRO_I_MIKRO_BOT\CONFIG\indices_family_blueprint_v1.json)
- Dodano dokument scalajacy caly ustr oj:
  - [68_DOMAIN_ARCHITECTURE_FX_METALS_INDICES_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\68_DOMAIN_ARCHITECTURE_FX_METALS_INDICES_V1.md)
- Zaktualizowano:
  - [CONFIG\project_config.json](C:\MAKRO_I_MIKRO_BOT\CONFIG\project_config.json)
  - [README.md](C:\MAKRO_I_MIKRO_BOT\README.md)
  - [TOOLS\VALIDATE_PROJECT_LAYOUT.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\VALIDATE_PROJECT_LAYOUT.ps1)

## 2026-03-14 - Kapital rdzeniowy, bufor zysku i dynamiczny risk base

- Rozszerzono kontrakt kapitalowy o rozroznienie:
  - `capital_core_anchor`
  - `realized_pnl_lifetime`
  - `effective_profit_buffer`
  - `effective_risk_base`
- Przyjeto i wdrozono zasade:
  - `risk_base = core_capital + 0.5 * profit_buffer`
- Dodano ograniczone luzowanie dziennych i sesyjnych limitow `live`:
  - bez luzowania do `10%` bufora,
  - dojscie do `1.25x` przy srednim buforze,
  - dojscie maksymalnie do `1.50x` przy duzym buforze.
- Dodano dodatkowy twardy sygnal ochrony:
  - `CORE_CAPITAL_FLOOR`
- Zaktualizowano:
  - [CONFIG\capital_risk_contract_v1.json](C:\MAKRO_I_MIKRO_BOT\CONFIG\capital_risk_contract_v1.json)
  - [MQL5\Include\Core\MbCapitalRiskContract.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbCapitalRiskContract.mqh)
  - [MQL5\Include\Core\MbRuntimeTypes.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbRuntimeTypes.mqh)
  - [MQL5\Include\Core\MbStorage.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbStorage.mqh)
  - [MQL5\Include\Core\MbClosedDealTracker.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbClosedDealTracker.mqh)
  - [MQL5\Include\Core\MbMarketGuards.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbMarketGuards.mqh)
  - [MQL5\Include\Strategies\Common\MbStrategyCommon.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Strategies\Common\MbStrategyCommon.mqh)
  - [61_IMMUTABLE_CAPITAL_RISK_CONTRACT_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\61_IMMUTABLE_CAPITAL_RISK_CONTRACT_V1.md)
  - [62_CAPITAL_RISK_CONTRACT_ENFORCEMENT_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\62_CAPITAL_RISK_CONTRACT_ENFORCEMENT_V1.md)
  - [69_CORE_CAPITAL_AND_PROFIT_BUFFER_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\69_CORE_CAPITAL_AND_PROFIT_BUFFER_V1.md)

## 2026-03-14 - Reczny kontrakt core capital

- Dodano wspolny, globalny kontrakt recznego rdzenia kapitalu:
  - [CONFIG\core_capital_contract_v1.json](C:\MAKRO_I_MIKRO_BOT\CONFIG\core_capital_contract_v1.json)
- Dodano runtime reader kontraktu:
  - [MbCoreCapitalContract.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbCoreCapitalContract.mqh)
- Dodano support dla globalnego katalogu stanu:
  - [MbStoragePaths.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbStoragePaths.mqh)
- Dodano zapis i odczyt dodatkowych pol obserwacyjnych kontraktu kapitalowego:
  - [MbRuntimeTypes.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbRuntimeTypes.mqh)
  - [MbStorage.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbStorage.mqh)
- Dodano narzedzia operatorskie:
  - [APPLY_CORE_CAPITAL_CONTRACT.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\APPLY_CORE_CAPITAL_CONTRACT.ps1)
  - [VALIDATE_CORE_CAPITAL_CONTRACT.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\VALIDATE_CORE_CAPITAL_CONTRACT.ps1)
- Dodano dokument operatora:
  - [70_MANUAL_CORE_CAPITAL_CONTRACT_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\70_MANUAL_CORE_CAPITAL_CONTRACT_V1.md)

## 2026-03-14 - Globalny koordynator sesji i kapitalu v1

- Dodano pierwszy wspolny kontrakt rytmu dnia:
  - [CONFIG\session_capital_coordinator_v1.json](C:\MAKRO_I_MIKRO_BOT\CONFIG\session_capital_coordinator_v1.json)
- Dodano narzedzie rozkladania stanu koordynatora do `Common Files`:
  - [APPLY_SESSION_CAPITAL_COORDINATOR.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\APPLY_SESSION_CAPITAL_COORDINATOR.ps1)
- Dodano walidator koordynatora:
  - [VALIDATE_SESSION_CAPITAL_COORDINATOR.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\VALIDATE_SESSION_CAPITAL_COORDINATOR.ps1)
- Mikro-boty zostaly podpiete do sterowania domenowego przez:
  - [MbRuntimeControl.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbRuntimeControl.mqh)
- Rozszerzono wspolne sciezki stanu o:
  - `state\_domains`
  - [MbStoragePaths.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbStoragePaths.mqh)
  - [MbStorage.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbStorage.mqh)
- Dodano dokument architektoniczny:
  - [71_GLOBAL_SESSION_CAPITAL_COORDINATOR_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\71_GLOBAL_SESSION_CAPITAL_COORDINATOR_V1.md)

## 2026-03-14 - Polityka trwałości runtime i rotacja logow

- Rozszerzono rotacje logow runtime o dodatkowe dzienniki telemetryczne i strojenia:
  - `candidate_signals.csv`
  - `execution_telemetry.csv`
  - `trade_transactions.jsonl`
  - `tuning_actions.csv`
  - `tuning_deckhand.csv`
  - `tuning_family_actions.csv`
  - `tuning_coordinator_actions.csv`
- Dodano audit trwałości danych runtime:
  - [AUDIT_RUNTIME_PERSISTENCE.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\AUDIT_RUNTIME_PERSISTENCE.ps1)
- Dookreslono polityke:
  - stan nadpisywany,
  - dzienniki rotowane,
  - pamiec uczenia zachowywana,
  - legacy do sprzatania.
- Dodano dokument:
  - [72_RUNTIME_PERSISTENCE_AND_LOG_ROTATION_POLICY_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\72_RUNTIME_PERSISTENCE_AND_LOG_ROTATION_POLICY_V1.md)
- Zaktualizowano audit artefaktow runtime pod nowe katalogi:
  - `_global`
  - `_domains`

## 2026-03-14 - Domain paper, reserve i reentry v1

- Rozszerzono runtime control o pierwszy pelnoprawny tryb:
  - `PAPER_ONLY`
- Ustalono priorytet nakladania sterowania:
  - `HALT`
  - `PAPER_ONLY`
  - `CLOSE_ONLY`
- Koordynator sesji i kapitalu zaczal czytac stan rodzin i floty z `Common Files`:
  - `state\_families\*\tuning_family_policy.csv`
  - `state\_coordinator\tuning_coordinator_state.csv`
- Dodano pierwsze warunki:
  - blokady rodzinnej,
  - blokady flotowej,
  - same-day `reentry`,
  - oznaczania domeny rezerwowej.
- Wszystkie `15/15` mikro-botow dostaly lokalny helper:
  - `IsLocalPaperModeActive()`
  - dzieki temu `paper` moze byc wymuszony domenowo bez lepkiego stanu po poprzednim dniu.
- Zaktualizowano:
  - [MQL5\Include\Core\MbRuntimeControl.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbRuntimeControl.mqh)
  - [CONFIG\session_capital_coordinator_v1.json](C:\MAKRO_I_MIKRO_BOT\CONFIG\session_capital_coordinator_v1.json)
  - [TOOLS\APPLY_SESSION_CAPITAL_COORDINATOR.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\APPLY_SESSION_CAPITAL_COORDINATOR.ps1)
  - [TOOLS\VALIDATE_SESSION_CAPITAL_COORDINATOR.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\VALIDATE_SESSION_CAPITAL_COORDINATOR.ps1)
  - [TOOLS\NEW_MICROBOT_SCAFFOLD.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\NEW_MICROBOT_SCAFFOLD.ps1)
  - [MQL5\Experts\MicroBots](C:\MAKRO_I_MIKRO_BOT\MQL5\Experts\MicroBots)
- Dodano dokument:
  - [73_DOMAIN_PAPER_RESERVE_REENTRY_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\73_DOMAIN_PAPER_RESERVE_REENTRY_V1.md)

## 2026-03-14 - Session capital defensive i reentry v2

- Dodano domenowy `risk_cap` rozkladany przez koordynatora do `runtime_control.csv`
- Wprowadzono operacyjne stany:
  - `LIVE_DEFENSIVE`
  - `REENTRY_PROBATION`
  - `PAPER_ACTIVE`
- Rezerwa moze zostac awansowana z `RESERVE_RESEARCH` do `RUN`, ale tylko w swoim sensownym oknie i tylko z przycietym ryzykiem.
- `MbStrategyCommon.mqh` respektuje juz domenowy kaganiec ryzyka bez dokladania ciezkiej logiki do hot-path.
- Dodatkowe pola obserwacyjne trafiaja do:
  - `runtime_state.csv`
  - `execution_summary.json`
  - `informational_policy.json`
  - `session_capital_state.csv`
- Zaktualizowano:
  - [CONFIG\session_capital_coordinator_v1.json](C:\MAKRO_I_MIKRO_BOT\CONFIG\session_capital_coordinator_v1.json)
  - [TOOLS\APPLY_SESSION_CAPITAL_COORDINATOR.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\APPLY_SESSION_CAPITAL_COORDINATOR.ps1)
  - [TOOLS\VALIDATE_SESSION_CAPITAL_COORDINATOR.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\VALIDATE_SESSION_CAPITAL_COORDINATOR.ps1)
  - [MQL5\Include\Core\MbRuntimeTypes.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbRuntimeTypes.mqh)
  - [MQL5\Include\Core\MbRuntimeControl.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbRuntimeControl.mqh)
  - [MQL5\Include\Core\MbStorage.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbStorage.mqh)
  - [MQL5\Include\Strategies\Common\MbStrategyCommon.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Strategies\Common\MbStrategyCommon.mqh)
  - [MQL5\Include\Core\MbExecutionSummaryPlane.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbExecutionSummaryPlane.mqh)
  - [MQL5\Include\Core\MbInformationalPolicyPlane.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbInformationalPolicyPlane.mqh)
- Dodano dokument:
  - [74_SESSION_CAPITAL_DEFENSIVE_AND_REENTRY_V2.md](C:\MAKRO_I_MIKRO_BOT\DOCS\74_SESSION_CAPITAL_DEFENSIVE_AND_REENTRY_V2.md)

## 2026-03-15 - Matryca kosztu i okna dla agenta strojenia

- Dodano warstwe interpretacyjna dla agenta strojenia, agenta rodzinnego i koordynatora sesji:
  - koszt okna
  - ryzyko szybkiego zgaszenia scalpingu
  - minimalny "oddech" potrzebny po wejsciu
  - blokada nowych wejsc live blisko konca okna
- Matryca nie sluzy do prognozy zysku.
  Sluzy do tego, aby agent:
  - nie otwieral live na zamknietej rodzinie
  - nie otwieral live w `OBSERVATION_ONLY` i `SHADOW`
  - szybciej wybieral `paper` zamiast slabego live
  - wczesniej podnosil prog pewnosci i obcinal `risk_cap`
- Dodano dokument:
  - [84_TUNING_COST_WINDOW_GUARD_MATRIX_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\84_TUNING_COST_WINDOW_GUARD_MATRIX_V1.md)
- Dodano maszynowa wersje matrycy:
  - [tuning_cost_window_guard_matrix_v1.json](C:\MAKRO_I_MIKRO_BOT\CONFIG\tuning_cost_window_guard_matrix_v1.json)

## 2026-03-15 - Runtime integration guard matrix

- Matryca kosztu i okna zostala wpieta do runtime strojenia jako lekka warstwa clampow rodzinnych.
- Dodano wspolny helper:
  - [MbTuningGuardMatrix.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningGuardMatrix.mqh)
- Lokalny agent strojenia respektuje teraz rodzinne sufity ostroznosci dla:
  - `confidence_cap`
  - `risk_cap`
- Agent rodzinny nie moze juz wypchnac dominujacych capow ponad guard rodziny.
- Most polityki skutecznej klamruje guard raz jeszcze po nalozeniu rodziny i koordynatora.
- Do wspolnej listy rodzin strojenia dolaczono:
  - `INDEX_EU`
  - `INDEX_US`
- Zaktualizowano:
  - [MQL5\Include\Core\MbTuningLocalAgent.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningLocalAgent.mqh)
  - [MQL5\Include\Core\MbTuningFamilyAgent.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningFamilyAgent.mqh)
  - [MQL5\Include\Core\MbTuningHierarchyBridge.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningHierarchyBridge.mqh)
- Kompilacja floty:
  - `17/17 compile_ok=true`
- Walidacje:
  - `VALIDATE_TUNING_HIERARCHY.ps1 -> ok=true`
  - `VALIDATE_PROJECT_LAYOUT.ps1 -> ok=true`
- Dodano dokument:
  - [85_TUNING_GUARD_MATRIX_RUNTIME_INTEGRATION_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\85_TUNING_GUARD_MATRIX_RUNTIME_INTEGRATION_V1.md)

## 2026-03-15 - Rollover guard z mostem ze starego systemu

- Nowy system odziedziczyl ze starego `OANDA_MT5_SYSTEM` jawny guard rollover osadzony w warstwie koordynatora, a nie w hot-path kazdego bota.
- Dodano:
  - dzienny guard `17:00 America/New_York`
  - symbolowe guardy kwartalne/manualne dla indeksow
  - wspolne pole `force_flatten` rozumiane przez runtime i wspolne zarzadzanie pozycja
- Najwazniejsza roznica wzgledem starego systemu:
  - dzienny rollover blokuje domenowo
  - kwartalne/manualne rollover indeksow blokuja symbolowo
- Zaktualizowano:
  - [CONFIG\rollover_guard_v1.json](C:\MAKRO_I_MIKRO_BOT\CONFIG\rollover_guard_v1.json)
  - [TOOLS\APPLY_SESSION_CAPITAL_COORDINATOR.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\APPLY_SESSION_CAPITAL_COORDINATOR.ps1)
  - [TOOLS\VALIDATE_SESSION_CAPITAL_COORDINATOR.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\VALIDATE_SESSION_CAPITAL_COORDINATOR.ps1)
  - [MQL5\Include\Core\MbRuntimeControl.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbRuntimeControl.mqh)
  - [MQL5\Include\Core\MbStorage.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbStorage.mqh)
  - [MQL5\Include\Strategies\Common\MbStrategyCommon.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Strategies\Common\MbStrategyCommon.mqh)
- Dodano dokument:
  - [86_ROLLOVER_GUARD_MIGRATION_FROM_OANDA_MT5_SYSTEM_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\86_ROLLOVER_GUARD_MIGRATION_FROM_OANDA_MT5_SYSTEM_V1.md)
- dograno brakujacy jezyk lokalnego strojenia po pierwszej godzinie rynku dla `FX_ASIA`, `FX_CROSS` i indeksow:
  - `range_chaos_tax`
  - `range_trend_tax`
  - `range_confidence_floor`
  - filtry swiecy/Renko dla `RANGE`
  - filtr swiecy dla breakoutu
  - lekkie podatki indeksowe dla startu i konca okna
- kompilacja floty po zmianie: `17/17 compile_ok=true`

## 2026-03-16 - Deckhand czyści przedpole strojenia semantycznie

- Deckhand lokalnego strojenia przestal oceniac tylko strukture plikow i dostal kontrole semantyczne przedpola.
- Dodano liczenie:
  - blokad ryzyka na kandydacie,
  - kandydatow przepuszczanych przez `PAPER_SCORE_GATE`,
  - kandydatow brudnych poznawczo,
  - faktycznych `PAPER_OPEN` w dzienniku decyzji.
- Dodano nowe powody braku zaufania:
  - `PAPER_CONVERSION_BLOCKED`
  - `FOREFIELD_DIRTY`
- Zaktualizowano:
  - [MQL5\Include\Core\MbTuningTypes.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningTypes.mqh)
  - [MQL5\Include\Core\MbTuningStorage.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningStorage.mqh)
  - [MQL5\Include\Core\MbTuningDeckhand.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningDeckhand.mqh)
- Kompilacja floty:
  - `17/17 compile_ok=true`
- Dodano dokument:
  - [90_DECKHAND_FOREFIELD_CLEANING_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\90_DECKHAND_FOREFIELD_CLEANING_V1.md)

## 2026-03-16 - Normalizacja parytetu agentow strojenia

- Wyrownano warstwe paper runtime we wszystkich pozostalych `14` mikro-botach.
- Kazdy mikro-bot ma juz:
  - paper-safe `MbMarkPriceProbe`
  - `blocked_by_tuning_gate`
  - fallback `PAPER_IGNORE_MIN_LOT_FLOOR`
- Dograno brakujace filtry strategii w starszych genotypach:
  - `TUNING_BREAKOUT_POOR_CANDLE`
  - dla genotypow zakresowych dodatkowo:
    - `TUNING_RANGE_POOR_CANDLE`
    - `TUNING_RANGE_POOR_RENKO`
    - `TUNING_RANGE_CONFIDENCE_FLOOR`
- Kompilacja floty po normalizacji:
  - `17/17 compile_ok=true`
- Lokalny MT5 po restarcie zaladowal ponownie wszystkie `17` ekspertow.
- Dodano dokument:
  - [91_TUNING_AGENT_PARITY_AUDIT_20260316.md](C:\MAKRO_I_MIKRO_BOT\DOCS\91_TUNING_AGENT_PARITY_AUDIT_20260316.md)
- Dodano raport:
  - [TUNING_AGENT_PARITY_NORMALIZATION_20260316.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\TUNING_AGENT_PARITY_NORMALIZATION_20260316.md)


- `GBPUSD` dostal ostrzejsze sito dla breakoutow w chaosie i papierowy ratunek tylko dla mocnych, czystych sygnalow trend/pullback.
- `USDCHF` dostal brakujace odblokowanie papierowe dla minimalnego lota oraz selektywny ratunek dla mocnego trendu po blokadzie ryzyka.
- `DE30` zostal doszczelniony przeciw slabym `pullback` i `range` w chaosie/trendzie, a papierowe timeouty zostaly skrocone.
- Kompilacja po zmianie:
  - `17/17 compile_ok=true`
- Dodano dokument:
- Dodano raport:

## 2026-03-16 - Dodatkowe wsparcie konwersji breakoutow dla GBPUSD

- `GBPUSD` dostal dodatkowy, bardzo waski papierowy ratunek dla breakoutow:
  - tylko przy wysokim wyniku
  - poza `CHAOS`
  - bez zlego spreadu
  - z dobra egzekucja
  - i z sensownym potwierdzeniem swieca / Renko
- Celem nie bylo rozluznienie calego bota, tylko odetkanie nielicznych wartosciowych breakoutow, ktore wczesniej ginely na `RISK_CONTRACT_BLOCK`.
- `MicroBot_GBPUSD` zostal skompilowany ponownie i lokalny MT5 zostal odswiezony.
- Dodano dokument:
  - [93_GBPUSD_BREAKOUT_CONVERSION_SUPPORT_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\93_GBPUSD_BREAKOUT_CONVERSION_SUPPORT_V1.md)

## 2026-03-16 - Pamiec i sciezka myslenia agentow strojenia

- Lokalny agent strojenia i deckhand dostaly nowa warstwe pamieci:
  - streak powodu blokady
  - streak ostatniej akcji
  - licznik cykli zablokowanych / zaufanych
  - glowny obszar skupienia
  - robocza hipoteze
  - kontrfaktyczna przestroge: co by bylo, gdyby nic nie zmieniac
- Dodano nowy dziennik:
  - `tuning_reasoning.csv`
- Celem jest, aby agent nie tylko regulowal parametry, ale zostawial czytelny tok rozumowania i nie wracal slepo do tych samych bledow.
- Dodano dokument:
  - [94_TUNING_AGENT_MEMORY_AND_REASONING_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\94_TUNING_AGENT_MEMORY_AND_REASONING_V1.md)

## 2026-03-16 - Pamiec eksperymentu, rollback i blokada powrotu do fiaska

- Lokalny agent strojenia dostal trwala pamiec eksperymentu:
  - kiedy zaczal zmiane
  - na jakiej bazie ja zaczal
  - jaki setup i reżim rynku stroi
  - ile nowych lekcji paper przyszlo od czasu zmiany
- Dodano stabilny snapshot polityki:
  - `tuning_policy_stable.csv`
- Dodano dziennik eksperymentow:
  - `tuning_experiments.csv`
- Agent potrafi teraz:
  - dac zmianie oddech
  - ocenic, czy poprawila material
  - utrzymac skuteczna zmiane
  - cofnac nieudana zmiane
  - i przez pewien czas nie wracac do swiezo obalonej sciezki
- Potwierdzono juz zywy zapis `tuning_reasoning.csv` po restarcie MT5.
- Dodano dokument:
  - [95_TUNING_EXPERIMENT_MEMORY_AND_ROLLBACK_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\95_TUNING_EXPERIMENT_MEMORY_AND_ROLLBACK_V1.md)
- Dodano raport:
  - [TUNING_EXPERIMENT_MEMORY_AND_ROLLBACK_20260316.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\TUNING_EXPERIMENT_MEMORY_AND_ROLLBACK_20260316.md)

## 2026-03-16 - Potwierdzenie runtime cyklu start -> akceptacja / rollback

- Na zywych logach `tuning_experiments.csv` potwierdzono wszystkie etapy:
  - `START`
  - `REVIEW_PENDING`
  - `ACCEPT`
  - `ROLLBACK`
- Potwierdzone pozytywne przypadki:
  - `EURUSD`
  - `US500`
- Potwierdzone negatywne przypadki z poprawnym cofnieciem:
  - `AUDUSD`
  - `USDJPY`
- Dopięto tez zapis rollbacku tak, aby nie gubil kontekstu obalonego eksperymentu.
- Dodano dokument:
  - [96_EXPERIMENT_CYCLE_RUNTIME_CONFIRMATION_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\96_EXPERIMENT_CYCLE_RUNTIME_CONFIRMATION_V1.md)
- Dodano raport:
  - [EXPERIMENT_CYCLE_RUNTIME_CONFIRMATION_20260316.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\EXPERIMENT_CYCLE_RUNTIME_CONFIRMATION_20260316.md)

## 2026-03-16 - Doktryna forexowa tylko dla EURUSD

- Dodano osobna warstwe wiedzy rynkowej:
  - [MbForexDoctrineEURUSD.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbForexDoctrineEURUSD.mqh)
- Strategia `EURUSD` rozroznia teraz:
  - rdzen plynnosci
  - cienka plynnosc
  - okna przejsciowe
  - rollover
- Agent strojenia `EURUSD` nie rozpoczyna nowych eksperymentow poza zdrowym rdzeniem rynku walutowego.
- Sama strategia `EURUSD` dostaje tez podatki i blokady zgodne z faza rynku forex, a nie tylko z ogolnym `market_regime`.
- Dodano dokument:
  - [97_EURUSD_FOREX_DOCTRINE_FOR_TUNING_AGENT_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\97_EURUSD_FOREX_DOCTRINE_FOR_TUNING_AGENT_V1.md)
- Dodano raport:
  - [EURUSD_FOREX_DOCTRINE_RUNTIME_20260316.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\EURUSD_FOREX_DOCTRINE_RUNTIME_20260316.md)

## 2026-03-16 - Chirurgia najslabszych instrumentow poza EURUSD

- Wzmocniono logike agenta strojenia dla:
  - `USDJPY`
  - `USDCHF`
- Jalowy eksperyment nie wisi juz bez konca: po serii przegladow bez nowych lekcji agent robi cofniecie.
- Po rollbacku agent moze dobrac nowa sciezke alternatywna zaleznosc od symbolu i genotypu, zamiast wracac do tej samej porazki.
- Dodano dokument:
  - [98_WEAK_INSTRUMENT_SURGICAL_AGENT_RECOVERY_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\98_WEAK_INSTRUMENT_SURGICAL_AGENT_RECOVERY_V1.md)
- Dodano raport:
  - [WEAK_INSTRUMENT_SURGICAL_AGENT_RECOVERY_20260316.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\WEAK_INSTRUMENT_SURGICAL_AGENT_RECOVERY_20260316.md)

## 2026-03-16 - Domkniecie top5 natychmiastowej interwencji

- Dolozono brakujace symbolowe sciezki alternatywne dla:
  - `DE30`
  - `SILVER`
- `DE30` po fiasku breakoutowego Renko przechodzi teraz w bardziej selektywny `SETUP_RANGE / CHAOS`.
- `SILVER` po fiasku trendu w chaosie przechodzi teraz w bardziej naturalny `SETUP_REJECTION / RANGE`.
- Dodano dokument:
  - [99_TOP5_INTERVENTION_COMPLETION_DE30_SILVER_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\99_TOP5_INTERVENTION_COMPLETION_DE30_SILVER_V1.md)
- Dodano raport:
  - [TOP5_INTERVENTION_COMPLETION_DE30_SILVER_20260316.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\TOP5_INTERVENTION_COMPLETION_DE30_SILVER_20260316.md)

## 2026-03-16 - Domkniecie top5 natychmiastowej interwencji dla USDCAD

- Dolozono ostatnia brakujaca, symbolowa sciezke alternatywna dla `USDCAD`.
- Po fiasku `FILTER_REJECTION_SUPPORT / SETUP_BREAKOUT / TREND` agent przechodzi teraz do bardziej selektywnego `SETUP_PULLBACK / TREND`.
- Dodano dokument:
  - [100_TOP5_INTERVENTION_USDCAD_COMPLETION_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\100_TOP5_INTERVENTION_USDCAD_COMPLETION_V1.md)
- Dodano raport:
  - [TOP5_INTERVENTION_USDCAD_COMPLETION_20260316.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\TOP5_INTERVENTION_USDCAD_COMPLETION_20260316.md)

## 2026-03-16 - Audyt ochrony sieciowej i adaptacja do mikro-botow

- Przeanalizowano material:
  - `C:\Users\skite\Desktop\MQL5_ Ochrona przed problemami sieciowymi.md`
- Potwierdzono, ze system mial juz:
  - stale tick guard,
  - spread/caution guard,
  - rate guard,
  - retry wrapper,
  - slippage i execution telemetry,
  - heartbeat i status plane.
- Dolozono brakujace elementy:
  - `terminal_connected`
  - `terminal_ping_ms`
  - twardy `TERMINAL_DISCONNECTED`
  - ostroznosc przy wysokim pingu
  - `INFRASTRUCTURE_WEAK` dla deckhanda i agenta strojenia
- Dodano dokument:
  - [101_NETWORK_PROTECTION_AUDIT_AND_ADOPTION_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\101_NETWORK_PROTECTION_AUDIT_AND_ADOPTION_V1.md)
- Dodano raport:
  - [NETWORK_PROTECTION_AUDIT_AND_ADOPTION_20260316.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\NETWORK_PROTECTION_AUDIT_AND_ADOPTION_20260316.md)

## 2026-03-16 - Odetkanie konwersji paper dla GBPUSD i EURAUD

- `GBPUSD` dostal lekki bypass `BROKER_PRICE_RATE_LIMIT` tylko w `paper`.
- `GBPUSD` dostal dodatkowy, waski ratunek dla mocniejszego trendu `SELL`.
- `EURAUD` dostal lekki bypass `BROKER_PRICE_RATE_LIMIT` tylko w `paper`.
- `EURAUD` dostal brakujacy `PAPER_IGNORE_MIN_LOT_BLOCK`.
- `EURAUD` dostal waski ratunek dla `SETUP_RANGE / RANGE` z dobra egzekucja i dobrym Renko.
- Po restarcie MT5 oba symbole zostawily juz swieze `PAPER_OPEN`.
- Dodano dokument:
  - [102_GBPUSD_EURAUD_PAPER_CONVERSION_RECOVERY_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\102_GBPUSD_EURAUD_PAPER_CONVERSION_RECOVERY_V1.md)
- Dodano raport:
  - [GBPUSD_EURAUD_PAPER_CONVERSION_RECOVERY_20260316.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\GBPUSD_EURAUD_PAPER_CONVERSION_RECOVERY_20260316.md)

## 2026-03-16 - Odetkanie EURAUD spod paperowego portfelowego ciepla

- `EURAUD` nadal byl czesciowo duszony przez `PORTFOLIO_HEAT_BLOCK`, mimo ze dawal juz swieze sygnaly `SETUP_RANGE`.
- Dodano bardzo waski bypass tylko dla `paper`:
  - tylko dla `SETUP_RANGE`
  - tylko przy dobrym score, dobrej egzekucji i bez zlego spreadu
- Po restarcie MT5 `EURAUD` zostawil swiezy `PAPER_OPEN / OK` po tej zmianie.
- Dodano dokument:
  - [103_EURAUD_PAPER_HEAT_BYPASS_V1.md](C:\MAKRO_I_MIKRO_BOT\DOCS\103_EURAUD_PAPER_HEAT_BYPASS_V1.md)
- Dodano raport:
  - [EURAUD_PAPER_HEAT_BYPASS_20260316.md](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\EURAUD_PAPER_HEAT_BYPASS_20260316.md)
