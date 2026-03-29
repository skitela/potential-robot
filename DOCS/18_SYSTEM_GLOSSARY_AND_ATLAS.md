# MAKRO_I_MIKRO_BOT System Glossary And Atlas

Version: 1.0  
Scope: `C:\MAKRO_I_MIKRO_BOT`  
Model: `100% MQL5`, `MT5-only`, `thin Core`, `thick MicroBots`

## Maintenance Rule

Ten dokument jest dokumentem utrzymaniowym systemu.

Musi byc aktualizowany zawsze, gdy:

- dochodzi nowy plik `mq5`, `mqh`, `ps1`, `json`, `md` albo `txt`, ktory zmienia zachowanie systemu,
- plik zmienia role,
- plik zmienia zakres odpowiedzialnosci,
- pojawia sie nowa warstwa walidacji, rolloutu, polityki rodziny albo propagacji,
- zmienia sie kontrakt miedzy `Core`, `Profiles`, `Strategies`, `MicroBots`, `TOOLS` i `SERVER_PROFILE`.

Zasada historyczna:

- jesli plik zmienil funkcje, opis ma zostac poprawiony tak, aby biezacy stan systemu byl prawdziwy,
- zmiana ma byc odnotowana takze w `DOCS/04_BOOTSTRAP_STATUS.md`,
- opis nie moze byc starszy niz kod, ktory opisuje.

## Cel Systemu

`MAKRO_I_MIKRO_BOT` jest nowym projektem runtime `MQL5-only`, zbudowanym po to, aby:

- zachowac filozofie ochrony kapitalu z `OANDA_MT5_SYSTEM`,
- przeniesc runtime na architekture bezposrednio wykonywana w `MetaTrader 5`,
- utrzymac mozliwie niska latencje per instrument,
- rozdzielic wspolne zachowania forexowe od lokalnych genow symbolu,
- wdrazac boty jako autonomiczne `EA`, po jednym na wykres i po jednym na symbol.

## Nadrzedna Zasada Architektoniczna

System nie buduje centralnego makro-bota sterujacego wszystkim.

Buduje:

- cienki `Core` jako biblioteke wspolnego kodu,
- autonomiczne `MicroBots` jako lokalne runtime per symbol,
- `Profiles` jako opis polityki symbolu,
- `Strategies` jako lokalna inteligencje wejscia, ryzyka i zarzadzania pozycja,
- `TOOLS` jako operacyjna warstwe budowy, walidacji i rolloutu.

`Core` jest wspolnym kodem.  
`MicroBot` jest wlascicielem decyzji tradingowej dla swojej pary.

## Zaleznosci Miedzy Warstwami

Przeplyw zaleznosci jest celowo jednostronny:

- `Experts/MicroBots` zaleza od `Core`, `Profiles`, `Strategies`
- `Strategies` zaleza od `Core`, ale zachowuja lokalne geny
- `Profiles` dostarczaja lokalna polityke symbolu
- `TOOLS` manipuluja plikami projektu, ale nie uczestnicza w hot-path
- `SERVER_PROFILE` jest artefaktem wdrozeniowym, nie zrodlem prawdy

Hot-path tradingowy:

- `OnTick`
- lokalny snapshot rynku
- lokalne guardy
- lokalna strategia
- lokalny risk plan
- lokalny execution

Poza hot-path:

- journaling
- telemetry
- rollout
- packaging
- deploy
- walidacje
- polityki rodzinne
- planowanie propagacji

## Drzewo Logiczne Systemu

### 1. `CONFIG`

Rola:

- trzymac jawne rejestry polityki, rodzin, wariantow i rolloutu.

Pliki:

`project_config.json`
- podstawowa konfiguracja projektu.
- definiuje tozsamosc projektu i ustawienia wysokiego poziomu.

`microbots_registry.json`
- deployment registry dla pary `symbol -> expert -> preset -> magic -> session_profile`.
- jest lekkim rejestrem rolloutowym.
- nie jest zrodlem prawdy dla edge.

`strategy_variant_registry.json`
- rejestr wariantow strategii wygenerowany z realnego kodu.
- opisuje lokalne roznice symbolowe: okna, setupy, ryzyko, triggery, okresy wskaznikow.
- jest jednym z glownych zrodel prawdy o genach par.

`family_policy_registry.json`
- rejestr rodzin `FX_MAIN / FX_ASIA / FX_CROSS`.
- trzyma wspolne inwarianty rodziny i dozwolone zakresy zmian.
- sluzy do kontrolowania, czy symbol nie wypada poza granice swojej rodziny.

`family_reference_registry.json`
- rejestr wzorcow rodzinnych.
- ustala, ktory bot jest wzorcem dla danej rodziny:
  - `FX_MAIN -> EURUSD`
  - `FX_ASIA -> USDJPY`
  - `FX_CROSS -> EURJPY`

### 2. `DOCS`

Rola:

- utrzymywac architekture, runbooki, modele propagacji i slownik systemu.

Pliki:

`01_ARCHITEKTURA_MAKRO_I_MIKRO_MQL5.md`
- dokument nadrzednej architektury.
- wyjasnia podzial na `Core`, `MicroBots`, `Profiles`, `Strategies`, `Tools`.

`02_MODEL_WDROZENIA_11_BOTOW_OANDA_MT5.md`
- model wdrozenia `11` botow na `MT5 OANDA`.
- opisuje model `1 bot = 1 chart = 1 symbol`.

`03_OSTRY_PROMPT_DLA_CODEX_NOWY_PODZIAL.md`
- dokument roboczy opisujacy zasady autonomicznego rozwoju projektu.

`04_BOOTSTRAP_STATUS.md`
- dziennik rozwoju projektu.
- zawiera liste juz wdrozonych warstw i zmian.

`05_RESEARCH_SOURCES_AND_CONSTRAINTS.md`
- zapis zrodel i ograniczen technicznych.
- spina wiedze o `MQL5`, `MT5`, `OANDA`.

`06_MT5_CHART_ATTACHMENT_PLAN.md/.txt/.json`
- plan przypiecia botow do wykresow.
- sluzy operatorowi do rolloutu.

`07_EURUSD_MODULE_MAPPING.md`
- mapa translacji z referencyjnego `EURUSD` do nowej architektury.

`08_EURUSD_INTEGRATION_CONTRACT.md`
- kontrakt integracyjny z referencyjnym mikro-botem `EURUSD`.

`09_KILL_SWITCH_MODEL.md`
- model tokenowego `kill-switch`.
- wyjasnia zaleznosc miedzy tokenem, runtime i blokada handlu.

`10_OPERATOR_ROLLOUT_CHECKLIST.md`
- checklista operatorska rolloutu.

`11_REMOTE_MT5_INSTALL.md`
- instrukcja zdalnej instalacji pakietu `MT5-only`.

`12_STRATEGY_PROPAGATION_MODEL.md`
- model propagacji wspolnego flow strategii.
- rozdziela to, co wolno propagowac, od tego, co musi zostac lokalne.

`13_SYMBOL_DIFFERENTIATION_STATUS.md`
- stan zroznicowania symboli.
- opisuje, co jest wspolne, a co juz jest lokalnym genem pary.

`14_RISK_POLICY_SPLIT.md`
- dokument podzialu ryzyka.
- rozroznia wspolne `hard guards` od lokalnego modelu ryzyka pary.

`15_SYMBOL_POLICY_COORDINATION.md`
- dokument koordynacji polityk symbolowych.
- spina `registry`, profile i warianty strategii.

`16_PROPAGATION_WORKFLOW.md`
- workflow dalszego rozwoju przez wzorzec i kontrolowana propagacje.

`17_FAMILY_REFERENCE_MODEL.md`
- model rodzinnych wzorcow rozwojowych.
- zapisuje, ktory bot jest wzorcem rodziny.

`18_SYSTEM_GLOSSARY_AND_ATLAS.md`
- ten dokument.
- pelny atlas roli plikow, warstw i zaleznosci.

### 3. `MQL5/Experts/MicroBots`

Rola:

- zawierac autonomiczne `EA` przypisane do konkretnych par.
- kazdy z tych plikow jest runtime ownerem jednego symbolu.

Pliki:

`MicroBot_EURUSD.mq5`
- wzorcowy mikro-bot rodziny `FX_MAIN`.
- spina `Core + Profile_EURUSD + Strategy_EURUSD`.
- wlasciciel runtime dla `EURUSD`.

`MicroBot_GBPUSD.mq5`
- mikro-bot `FX_MAIN` dla `GBPUSD`.
- uzywa wspolnego flow i lokalnych genow `GBPUSD`.

`MicroBot_USDCAD.mq5`
- mikro-bot `FX_MAIN` dla `USDCAD`.
- lokalna odmiana glownej rodziny z setupem `reversal`.

`MicroBot_USDCHF.mq5`
- mikro-bot `FX_MAIN` dla `USDCHF`.
- lokalny wariant glownej rodziny z innym profilem ryzyka i triggerow.

`MicroBot_USDJPY.mq5`
- wzorcowy mikro-bot rodziny `FX_ASIA`.
- glowny punkt odniesienia dla azjatyckich par.

`MicroBot_NZDUSD.mq5`
- mikro-bot `FX_ASIA` dla `NZDUSD`.

`MicroBot_AUDUSD.mq5`
- mikro-bot `FX_ASIA` dla `AUDUSD`.
- lokalnie zawiera wariant `range`.

`MicroBot_EURJPY.mq5`
- wzorcowy mikro-bot rodziny `FX_CROSS`.
- glowny punkt odniesienia dla par krzyzowych.

`MicroBot_GBPJPY.mq5`
- mikro-bot `FX_CROSS` dla `GBPJPY`.

`MicroBot_EURAUD.mq5`
- mikro-bot `FX_CROSS` dla `EURAUD`.
- lokalnie zawiera wariant `range`.


### 4. `MQL5/Include/Core`

Rola:

- przechowywac wspolny kod biblioteczny, ktory nie odbiera mikro-botom decyzyjnosci.

Pliki:

`MbRuntimeTypes.mqh`
- definicje typow runtime.
- enumy trybow pracy, kierunkow sygnalu, struktur stanu, market snapshot, execution result.
- podstawowy kontrakt calego systemu.

`MbRuntimeKernel.mqh`
- najcienszy kernel cyklu runtime.
- aktualizuje tryb i liczniki `OnTick` / `OnTimer`.

`MbStorage.mqh`
- wspolna persystencja runtime.
- zapis i odczyt stanu bota.

`MbStoragePaths.mqh`
- standaryzuje sciezki zapisu `FILE_COMMON`.
- oddziela logike nazw katalogow od logiki runtime.

`MbStatusPlane.mqh`
- eksport statusu runtime.
- buduje lekkie status payloady dla operatora.

`MbRuntimeControl.mqh`
- odczyt i aplikacja lokalnych komend runtime.
- obsluguje `halt`, `close_only`, tryb pracy.

`MbKillSwitchGuard.mqh`
- wspolna implementacja lokalnego `kill-switch`.
- sprawdza token ochronny i TTL.

`MbRateGuard.mqh`
- budzetuje zapytania cenowe i rynkowe.
- lokalna zgodnosc z polityka brokera i ochrony przed floodem.

`MbSessionGuard.mqh`
- helpery okien handlu i sesji.
- sluzy do szybkiej weryfikacji, czy symbol jest w aktywnym oknie.

`MbMarketState.mqh`
- buduje snapshot rynku i stanu terminala.
- sluzy do odczytu bid/ask/spread, tick age, wolumenu i diagnostyki feedu.

`MbMarketGuards.mqh`
- wspolne pre-trade guardy rynku.
- pilnuje:
  - okna handlu
  - cooldownu
  - loss caps
  - margin guard
  - stale cache
  - spread cap

`MbLatencyProfile.mqh`
- agreguje pomiary latencji lokalnej.

`MbBrokerProfilePlane.mqh`
- lekki obraz warunkow execution po stronie brokera.

`MbExecutionSummaryPlane.mqh`
- zwarty summary runtime i execution.

`MbInformationalPolicyPlane.mqh`
- eksport informacji o aktywnej polityce runtime.

`MbExecutionCommon.mqh`
- niskopoziomowe helpery klasyfikacji retcode i execution.

`MbExecutionPrecheck.mqh`
- buduje i ocenia `OrderCheck` / `OrderCalcMargin`.
- warstwa przed realnym `OrderSend`.

`MbExecutionSend.mqh`
- wspolny wrapper wysylki i retry.
- realizuje `Buy/Sell`, klasyfikuje retcode, liczy czas wysylki i slippage.

`MbExecutionFeedback.mqh`
- sprzezenie zwrotne execution do runtime.
- aktualizuje execution pressure.

`MbDecisionJournal.mqh`
- wspolny zapis zdarzen decyzyjnych.
- wspiera buforowanie kolejki i flush poza hot-path.

`MbExecutionTelemetry.mqh`
- telemetryka wykonania.
- wspiera buforowanie kolejki i flush poza hot-path.

`MbIncidentJournal.mqh`
- journal incydentow runtime, guardow i execution.
- wspiera buforowanie kolejki i flush poza hot-path.

`MbTradeTransactionJournal.mqh`
- sluchacz i journaling `OnTradeTransaction`.
- wspiera buforowanie kolejki i flush poza hot-path.

`MbClosedDealTracker.mqh`
- wykrywa i rejestruje nowe zamkniete deal'e tylko raz.
- aktualizuje tez lekka pamiec swiezych wynikow: `learning_bias` i `adaptive_risk_scale`.

`MbExecutionQualityGuard.mqh`
- wspolny lekki guard jakosci execution.
- wprowadza `CAUTION` albo blokuje nowe wejscie przy degradacji swiezych metryk execution.

`MbConfigEnvelope.mqh`
- helper transportu konfiguracji i payloadow.

### 5. `MQL5/Include/Profiles`

Rola:

- trzymac polityke symbolu.
- nie podejmowac decyzji tradingowej, ale definiowac warunki lokalne.

Pliki:

`Profile_EURUSD.mqh`
- polityka `EURUSD`.
- rodzina `FX_MAIN`, okno `8-11`, kill-switch `oandakey_eurusd.token`.

`Profile_GBPUSD.mqh`
- polityka `GBPUSD`.
- rodzina `FX_MAIN`, okno glownej sesji.

`Profile_USDCAD.mqh`
- polityka `USDCAD`.
- rodzina `FX_MAIN`, okno `8-12`.

`Profile_USDCHF.mqh`
- polityka `USDCHF`.
- rodzina `FX_MAIN`, okno `8-12`.

`Profile_USDJPY.mqh`
- polityka `USDJPY`.
- rodzina `FX_ASIA`, okno `0-3`.

`Profile_NZDUSD.mqh`
- polityka `NZDUSD`.
- rodzina `FX_ASIA`, okno `0-3`.

`Profile_AUDUSD.mqh`
- polityka `AUDUSD`.
- rodzina `FX_ASIA`, okno `0-5`.

`Profile_EURJPY.mqh`
- polityka `EURJPY`.
- rodzina `FX_CROSS`, okno `7-12`.

`Profile_GBPJPY.mqh`
- polityka `GBPJPY`.
- rodzina `FX_CROSS`, okno `7-12`.

`Profile_EURAUD.mqh`
- polityka `EURAUD`.
- rodzina `FX_CROSS`, okno `7-11`.

- rodzina `FX_CROSS`, okno `7-11`.

### 6. `MQL5/Include/Strategies`

Rola:

- zawierac lokalna inteligencje symbolowa.
- tu siedza setupy, scoring, trigger thresholds, model ryzyka, trailing i zarzadzanie pozycja.

Pliki:

`Common/MbStrategyCommon.mqh`
- wspolny bezpieczny szkielet flow strategii.
- zawiera:
  - init/deinit indikatorow
  - kopiowanie ostatnich wartosci
  - `new-bar gate`
  - liczenie lota
  - budowe risk-planu
  - trailing helper
  - ranking setupow
  - finalizacje trigger gate
- nie zawiera lokalnego edge symbolowego.

`Strategy_EURUSD.mqh`
- strategia wzorcowa `FX_MAIN`.
- ma lokalny `rejection`.
- wzorzec rozwojowy rodziny glownej.

`Strategy_GBPUSD.mqh`
- strategia `GBPUSD`.
- lokalny wariant rodziny glownej.

`Strategy_USDCAD.mqh`
- strategia `USDCAD`.
- lokalny wariant z `reversal`.

`Strategy_USDCHF.mqh`
- strategia `USDCHF`.
- lokalna odmiana rodziny glownej.

`Strategy_USDJPY.mqh`
- strategia wzorcowa `FX_ASIA`.
- lokalne etykiety `_ASIA`.

`Strategy_NZDUSD.mqh`
- strategia `NZDUSD`.
- lokalny wariant azjatycki.

`Strategy_AUDUSD.mqh`
- strategia `AUDUSD`.
- lokalny wariant azjatycki z `range`.

`Strategy_EURJPY.mqh`
- strategia wzorcowa `FX_CROSS`.

`Strategy_GBPJPY.mqh`
- strategia `GBPJPY`.
- lokalny cross trend/pullback.

`Strategy_EURAUD.mqh`
- strategia `EURAUD`.
- lokalny cross z `range`.

- lokalny cross z mocniejszym profilem triggera i trailingu.

### 7. `MQL5/Presets`

Rola:

- przechowywac parametry attachu per bot.
- rozdzielac presety bezpieczne od aktywowanych swiadomie.

Pliki:

`MicroBot_<SYMBOL>_Live.set`
- domyslny preset dla kazdego mikro-bota.
- domyslnie bezpieczny.
- `InpEnableLiveEntries=false` dopoki operator swiadomie nie wygeneruje presetow aktywnych.

### 8. `RUN`

Rola:

- dostarczyc operatorowi jednoznaczny punkt wejscia do rolloutu.

Pliki:

`PREPARE_MT5_ROLLOUT.ps1`
- wrapper operatorski.
- odpala preflight i przygotowuje rollout.

`README_RUN.txt`
- krotki opis warstwy `RUN`.

### 9. `TOOLS`

Rola:

- utrzymywac tooling rozwojowy, walidacyjny, deployowy i operatorski.

Pliki:

`README_TOOLS.txt`
- krotki slownik narzedzi.

`NEW_MICROBOT_SCAFFOLD.ps1`
- generator nowego mikro-bota.
- buduje eksperta, profil, strategie i preset.
- odtwarza aktualny wzorzec runtime oparty o `EURUSD`, bez nadpisywania lokalnej strategii ani profilu przy przebudowie expert-only.

`REBUILD_GENERATED_MICROBOTS.ps1`
- przebudowuje wygenerowane boty po zmianie scaffolda.

`COMPILE_MICROBOT.ps1`
- kompiluje jednego bota.
- sluzy do kontroli per symbol.

`COMPILE_ALL_MICROBOTS.ps1`
- kompiluje cala partie `11`.

`SYNC_OANDAKEY_TOKEN.ps1`
- odswieza token `kill-switch` dla jednego symbolu.

`SYNC_ALL_OANDAKEY_TOKENS.ps1`
- odswieza tokeny calej partii.

`VALIDATE_PROJECT_LAYOUT.ps1`
- waliduje strukture projektu i obecnosci artefaktow.

`VALIDATE_PRESET_SAFETY.ps1`
- pilnuje bezpieczenstwa presetow.

`VALIDATE_DEPLOYMENT_READINESS.ps1`
- waliduje gotowosc rolloutowa:
  - magiki
  - tokeny
  - spojnosci ekspert/preset/rejestr

`VALIDATE_TRANSFER_PACKAGE.ps1`
- sprawdza spojnosci `PACKAGE + HANDOFF`.

`VALIDATE_MT5_SERVER_INSTALL.ps1`
- waliduje instalacje pakietu w terminalu MT5.

`SIMULATE_MT5_SERVER_INSTALL.ps1`
- lokalna symulacja rozlozenia pakietu.

`PREPARE_MT5_ROLLOUT.ps1`
- pelny preflight rolloutu.
- scala walidacje, eksporty, packaging i handoff.

`GENERATE_ACTIVE_LIVE_PRESETS.ps1`
- generuje aktywne presety `live=true` poza domyslnie bezpiecznym repo.

`EXPORT_MT5_SERVER_PROFILE.ps1`
- eksportuje pakiet serwerowy `MT5-only`.

`EXPORT_OPERATOR_HANDOFF.ps1`
- tworzy pakiet operatorski.

`PACK_PROJECT_ZIP.ps1`
- backup calego projektu.

`PACK_HANDOFF_ZIP.ps1`
- backup pakietu operatorskiego.

`BOOTSTRAP_REMOTE_LAYOUT.ps1`
- buduje zdalny layout pod wdrozenie.

`GENERATE_MT5_CHART_PLAN.ps1`
- generuje plan wykresow i attachu botow.

`INSTALL_MT5_SERVER_PACKAGE.ps1`
- rozklada pakiet do danych terminala `MT5`.

`GENERATE_STRATEGY_VARIANT_REGISTRY.ps1`
- buduje rejestr wariantow strategii z realnego kodu.

`VALIDATE_SYMBOL_POLICY_CONSISTENCY.ps1`
- pilnuje zgodnosci miedzy `registry`, profilami i wariantami strategii.

`GENERATE_FAMILY_POLICY_REGISTRY.ps1`
- buduje rejestr granic rodzin.

`VALIDATE_FAMILY_POLICY_BOUNDS.ps1`
- pilnuje, by symbol nie wypadal poza ramy swojej rodziny.

`PLAN_STRATEGY_PROPAGATION.ps1`
- planuje propagacje zmian z wzorca.
- rozroznia to, co wolno rozlac, od tego, co trzeba zachowac lokalnie.

`GENERATE_ALL_PROPAGATION_PLANS.ps1`
- buduje komplet planow rodzinnych.

`GENERATE_FAMILY_REFERENCE_REGISTRY.ps1`
- buduje jawny rejestr wzorcow rodzin.

`VALIDATE_FAMILY_REFERENCE_REGISTRY.ps1`
- waliduje, czy wzorzec nalezy do swojej rodziny i czy rodzina ma poprawny zestaw targetow.

### 10. `SERVER_PROFILE`

Rola:

- byc przenoszalnym obrazem wdrozeniowym `MT5-only`.

Struktury:

`SERVER_PROFILE/PACKAGE`
- pakiet techniczny do instalacji w docelowym terminalu.

`SERVER_PROFILE/HANDOFF`
- pakiet operatorski z dokumentami, checklistami i raportami.

`SERVER_PROFILE/REMOTE_SIM`
- lokalna symulacja docelowej instalacji.

### 11. `EVIDENCE`

Rola:

- przechowywac dowody kompilacji, walidacji, rolloutu i planowania.

Najwazniejsze grupy:

`build_verification_report.*`
- dowod kompilacji i weryfikacji.

`deployment_readiness_report.*`
- dowod gotowosci rolloutowej.

`preset_safety_report.*`
- dowod bezpieczenstwa presetow.

`prepare_mt5_rollout_report.*`
- dowod pelnego preflightu.

`transfer_package_report.*`
- dowod spojnosci pakietu transferowego.

`symbol_policy_consistency_report.*`
- dowod spojnosci polityk symbolowych.

`family_policy_*`
- dowody dotyczace granic i inwariantow rodzin.

`strategy_propagation_plan.*`
- plan propagacji dla konkretnego wzorca.

`propagation_plan_matrix.*`
- macierz wszystkich rodzinnych planow rozwoju.

`PROPAGATION_PLANS/*`
- konkretne plany per rodzina.

`family_reference_*`
- dowody dotyczace rodzinnych wzorcow zrodlowych.

### 12. `MANIFEST` I `README`

`MANIFEST.json`
- glowny manifest tozsamosci projektu.

`README.md`
- glowny punkt wejscia operatorskiego i architektonicznego.

## Slownik Pojec

`Core`
- wspolna biblioteka pomocnicza.

`MicroBot`
- autonomiczny EA jednego symbolu.

`Profile`
- polityka symbolu.

`Strategy`
- lokalna inteligencja symbolowa.

`Gene symbolu`
- lokalna cecha, ktorej nie wolno nadpisywac przez wspolna propagacje.

`Family`
- grupa symboli o podobnym schemacie pracy:
  - `FX_MAIN`
  - `FX_ASIA`
  - `FX_CROSS`

`Family reference`
- bot wzorcowy dla rodziny.

`Propagation`
- rozprowadzanie wspolnych zmian bez niszczenia lokalnych genow.

`Kill-switch`
- lokalny bezpiecznik tokenowy zatrzymujacy handel przy braku waznego tokenu.

`Preflight`
- pelna sekwencja walidacyjna przed rolloutem.

## Wniosek Koncowy

`MAKRO_I_MIKRO_BOT` nie jest zlepkiem botow.

To jest juz uporzadkowany system z:

- autonomicznymi mikro-botami,
- cienkim `Core`,
- jawna polityka rodzin,
- jawnymi wzorcami rodzin,
- kontrolowana propagacja zmian,
- narzedziami rolloutowymi,
- dowodami walidacji i wdrozenia.

To oznacza, ze dalszy rozwoj moze byc prowadzony:

- przez wzorzec symbolu,
- przez wzorzec rodziny,
- albo przez wspolny flow,

bez mieszania tych poziomow i bez utraty lokalnych genow par walutowych.
