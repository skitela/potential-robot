# Globalny Plan Wdrozenia Integracji MT5 OANDA + MAKRO_I_MIKRO_BOT + ML + Domkniecie Pro

Data: 2026-04-01
Status: plan globalny do prowadzenia zmiany wielofalowej

## Cel

Przygotowac jeden wspolny plan wdrozenia dla zmiany, ktora jednoczesnie dotyka:

- pelniejszej zgodnosci z runtime `OANDA TMS MT5`,
- wszystkich `13` aktywnych instrumentow,
- makro i mikro runtime,
- teacher package globalnego i personalnego,
- lokalnych modeli i warstwy `ONNX`,
- supervision, promocji, rollbacku i retrainingu,
- migracji laptop -> `MT5` -> `VPS`,
- auditow, handoffu i operator runbookow.

Ten plan ma uniknac klasycznego bledu szerokich zmian: poprawienia jednej warstwy przy jednoczesnym rozjechaniu innych warstw kontraktu, runtime, migracji albo audytu.

## Jednoznaczny Werdykt Strategiczny

Tak, ta zmiane da sie wdrozyc globalnie.

Nie da sie jednak zrobic tego uczciwie jako jednego slepego przelaczenia wszystkiego naraz.

Jedyna bezpieczna droga to program wielofalowy, w ktorym kazda fala konczy sie jawna walidacja:

- kontraktow,
- runtime,
- broker parity,
- deploymentu,
- supervision,
- evidence,
- rollbacku.

Czyli:

- tak, mozna to wdrozyc globalnie,
- nie, nie nalezy obiecywac jednego skoku bez ryzyka pominiecia ogniw,
- trzeba to zrobic etapami, ale z jedna wspolna mapa calego systemu.

## Co Jest Juz Zamkniete

Na dzis w repo jest juz domknieta duza czesc fundamentu, wiec ten plan nie startuje od zera.

Domkniete albo osadzone sa juz:

- separacja `teacher_package_mode` od `paper_live_bucket`,
- `teacher_package_contract.csv` i `teacher_package_manifest_latest.json`,
- `build_teacher_promotion_snapshot.py`,
- `validate_teacher_promotion.py`,
- `teacher_promotion_policy_v1.json`,
- `teacher_promotion_history_template_v1.json`,
- `teacher_learning_process_blueprint_v1.json`,
- `personal_teacher_curricula_registry_v1.json`,
- komplety `personal_teacher_curriculum_*.json` dla `13` aktywnych symboli,
- jawna macierz nazw `symbol_alias` / `broker_symbol` / `code_symbol` / `state_alias`,
- dokumentacja roznicy miedzy `MT5 install path`, `terminal data path` i `Common Files`,
- rollout checklist i remote install checklist z ograniczeniami `MetaTrader VPS`.

To znaczy, ze najwazniejsze braki nie leza juz w samym slowniku systemu, tylko w wykonaniu calosci end-to-end.

## Co Nadal Nie Jest Domkniete

To sa faktyczne luki, ktore ten plan ma domknac:

1. Brak stalej orkiestracji promotion pipeline w `RUN`.
2. Brak regularnego zapisu `teacher_promotion_verdict_latest.json` i `teacher_promotion_history_latest.json` per symbol.
3. Brak pelnego operational loop dla retraining / promotion / rollback.
4. Brak jawnego shadow lifecycle dla `GLOBAL_PLUS_PERSONAL` jako stalego trybu operacyjnego.
5. Brak dynamicznego routingu `ONNX` po `teacher_id` albo `teacher_package_mode`; runtime nadal trzyma nauczyciela globalnego na `_GLOBAL`.
6. Brak dowodu runtimeowej emisji i wykorzystania calego personal feature space dla calej floty.
7. Brak domknietej parity importu metadanych brokera: `volume_min`, `volume_step`, `volume_max`, `tick_size`, `tick_value`, `stops_level`, `freeze_level`.
8. Brak deployment parity dla `teacher_package_contract.csv` dla calej floty; znana luka `12/13`.
9. Brak potwierdzonej obecnosci `MicroBot_AUDUSD.ex5` w aktywnej instancji `OANDA TMS MT5`.
10. Brak jednego globalnego gate, ktory spina `contracts -> runtime -> ML -> deployment -> audit -> go/no-go`.

## Ogniwa Systemu Objetego Zmiana

Ten program zmian obejmuje wszystkie krytyczne warstwy. Nie wolno prowadzic zmiany tylko w jednej z nich.

### 1. Contracts i Registry

Glowne pliki:

- `CONFIG/learning_universe_contract.json`
- `CONFIG/microbots_registry.json`
- `CONFIG/mt5_first_wave_server_parity_v1.json`
- `CONFIG/teacher_package_schema_v1.json`
- `CONFIG/teacher_learning_process_blueprint_v1.json`
- `CONFIG/teacher_promotion_policy_v1.json`
- `CONFIG/personal_teacher_curricula_registry_v1.json`
- `CONFIG/global_teacher_curriculum_v1.json`
- `CONFIG/personal_teacher_curriculum_*.json`

Rola warstwy:

- trzyma zrodlo prawdy o aktywnej flocie,
- trzyma semantyke teacher mode,
- trzyma broker parity i session parity,
- trzyma definicje oczekiwanych artefaktow i przejsc.

Zmiana wymagana:

- wszystkie nowe reguly integracyjne musza najpierw byc wyrazone tutaj,
- nie wolno dopisywac alternatywnej prawdy w `RUN`, `DOCS` albo `MQL5` bez aktualizacji tych kontraktow.

### 2. Nazewnictwo i Mapowanie Symboli

Glowne pliki:

- `DOCS/02_MODEL_WDROZENIA_11_BOTOW_OANDA_MT5.md`
- `TOOLS/REGISTRY_SYMBOL_HELPERS.ps1`
- `CONFIG/microbots_registry.json`

Rola warstwy:

- utrzymuje zgodnosc miedzy `symbol_alias`, `broker_symbol`, `code_symbol` i `state_alias`.

Zmiana wymagana:

- kazda nowa automatyka musi uzywac tej samej mapy nazw,
- `COPPER-US` pozostaje twardym testem spojnosc calego systemu.

### 3. MQL5 Runtime

Glowne pliki:

- `MQL5/Experts/MicroBots/MicroBot_*.mq5`
- `MQL5/Include/Core/MbMlRuntimeBridge.mqh`
- `MQL5/Include/Core/MbTeacherPackage.mqh`
- `MQL5/Include/Core/MbTeacherModeResolver.mqh`
- `MQL5/Include/Core/MbTeacherKnowledgeSnapshot.mqh`
- `MQL5/Include/Core/MbOnnxPilotObservation.mqh`
- `MQL5/Include/Core/MbBrokerProfilePlane.mqh`
- `MQL5/Include/Profiles/Profile_*.mqh`
- `MQL5/Include/Strategies/Strategy_*.mqh`

Rola warstwy:

- wykonuje decyzje handlowe,
- publikuje snapshoty i broker profile,
- laduje teacher package,
- korzysta z `ONNX`,
- zapisuje stan do `Common Files`.

Zmiana wymagana:

- nie robimy drugiego runtime,
- nie psujemy wspolnego `decision path`,
- rozszerzamy runtime tak, aby umial dzialac z pelniejsza semantyka brokera i pelniejszym lifecycle nauczyciela.

### 4. CONTROL i ML

Glowne pliki:

- `CONTROL/build_teacher_package.py`
- `CONTROL/build_teacher_promotion_snapshot.py`
- `CONTROL/validate_teacher_promotion.py`
- `CONTROL/build_learning_supervisor_matrix.py`
- `CONTROL/build_system_snapshot.py`
- `TOOLS/mb_ml_core/*.py`
- `TOOLS/mb_ml_supervision/*.py`

Rola warstwy:

- buduje kontrakty i manifesty,
- wylicza gotowosc nauczyciela,
- waliduje promocje,
- nadzoruje zdrowie uczenia,
- buduje treningowy i supervision control-plane.

Zmiana wymagana:

- CONTROL musi przestac byc tylko warstwa kontraktowa,
- musi przejsc do stalej automatyki decyzji i historii.

### 5. RUN i Orkiestracja

Glowne pliki i skrypty:

- `RUN/PREPARE_MT5_ROLLOUT.ps1`
- `RUN/PREPARE_RUNTIME_ONNX_PILOT.ps1`
- `RUN/ENSURE_SHADOW_RUNTIME_BOOTSTRAP.ps1`
- `RUN/BUILD_LEARNING_PAPER_RUNTIME_PLAN.ps1`
- `RUN/BUILD_ONNX_CABLE_STATUS_REPORT.ps1`
- `RUN/GET_ORCHESTRATOR_TASKBOARD.ps1`
- `RUN/GET_ORCHESTRATOR_WORKBOARD.ps1`
- `RUN/VALIDATE_PRELIVE_GONOGO.ps1`

Rola warstwy:

- uruchamia preflight,
- laczy prace brygad,
- buduje stan readiness,
- przygotowuje `ONNX` runtime,
- wystawia bramki go/no-go.

Zmiana wymagana:

- to tutaj ma wejsc brakujaca petla promotion pipeline,
- to tutaj ma sie spiac retraining, verdict, history, rollback i pilot shadow.

### 6. Deployment i Migracja

Glowne pliki:

- `TOOLS/PREPARE_MT5_ROLLOUT.ps1`
- `TOOLS/INSTALL_MT5_SERVER_PACKAGE.ps1`
- `TOOLS/VALIDATE_MT5_SERVER_INSTALL.ps1`
- `TOOLS/SIMULATE_MT5_SERVER_INSTALL.ps1`
- `TOOLS/DEPLOY_MT5_PACKAGE_TO_REMOTE.ps1`
- `TOOLS/EXPORT_MT5_SERVER_PROFILE.ps1`
- `RUN/MIGRATE_OANDA_MT5_VPS_CLEAN.ps1`

Rola warstwy:

- przenosi kod, presety i runtime na terminal `MT5`,
- waliduje parity laptop -> terminal -> `VPS`,
- buduje package, handoff i rollback points.

Zmiana wymagana:

- migracja ma byc traktowana jako integralna czesc systemu ML/runtime, a nie osobny manualny proces operatorski.

### 7. Audyty i Evidence

Glowne pliki:

- `TOOLS/BUILD_MT5_ACTIVE_SYMBOL_DEPLOYMENT_AUDIT.ps1`
- `TOOLS/BUILD_MT5_SYMBOL_METADATA_PROFILE_AUDIT.ps1`
- `TOOLS/BUILD_BROKER_REALISM_PARITY_AUDIT.py`
- `RUN/AUDIT_POST_MIGRATION_STARTUP.ps1`
- `EVIDENCE/OPS/*`

Rola warstwy:

- udowadnia, ze zmiana rzeczywiscie dziala,
- udowadnia, ze nie mamy dryfu miedzy repo a terminalem,
- daje podstawy pod `go/no-go`.

Zmiana wymagana:

- kazda fala wdrozenia musi konczyc sie audytem, a nie tylko "kompilacja przeszla".

### 8. Dokumentacja i Handoff

Glowne pliki:

- `DOCS/10_OPERATOR_ROLLOUT_CHECKLIST.md`
- `DOCS/11_REMOTE_MT5_INSTALL.md`
- `DOCS/PLAN_IMPLANTACJI_TEACHER_PACKAGE_BRYGADA_20260401.md`
- `SERVER_PROFILE/HANDOFF/DOCS/*`
- `BRYGADY/00_START_BRYGADY.md`

Rola warstwy:

- przenosi plan do operatora i do innych brygad,
- pilnuje, zeby po zmianie nie powstaly dwa sprzeczne modele prawdy.

Zmiana wymagana:

- po kazdej fali dokumenty operatorskie musza byc zsynchronizowane z runtime i kontraktami.

## Zasady Niezmienialne

1. Jeden wspolny runtime `MQL5`, bez drugiego silnika.
2. `teacher_package_mode` i `paper_live_bucket` pozostaja rozdzielone.
3. `symbol_alias`, `broker_symbol`, `code_symbol` i `state_alias` nie sa zamienne.
4. `MT5 install path`, `terminal data path` i `Common Files` nie sa zamienne.
5. `teacher_knowledge_snapshot` pozostaje snapshotem suplementarnym, nie zastepuje `learning_supervisor_snapshot` ani `supervisor_snapshot`.
6. `GLOBAL_PLUS_PERSONAL` ma byc shadow mode z dowodem historii, a nie tylko etykieta.
7. Nie wlaczamy szerokiego `PERSONAL_PRIMARY`, dopoki nie ma dowodu runtimeowej dojrzalosci per symbol.
8. Kazda zmiana musi byc odwracalna i konczyc sie dowodem parity.

## Program Wdrozenia Globalnego

### Faza 0. Freeze i Mapa Prawdy

Cel:

- ustalic jeden punkt startowy i jeden zestaw artefaktow prawdy.

Zakres:

- odswiezyc deployment audit,
- odswiezyc symbol metadata audit,
- odswiezyc broker realism parity audit,
- odswiezyc post-migration startup audit,
- zrzucic aktualny status `teacher_package`, `broker_profile`, `ONNX` runtime i `ex5`.

Artefakty wyjsciowe:

- `mt5_active_symbol_deployment_audit_latest.*`
- `mt5_symbol_metadata_profile_audit_latest.*`
- `mt5_first_wave_server_parity_latest.*`
- `full_stack_audit_latest.*`

Warunek wyjscia:

- mamy jedna twarda baze stanu zero.

### Faza 1. Domkniecie Broker Parity i Nazw

Cel:

- doprowadzic cala flote do jednej mapy nazewniczej i jednej mapy metadanych brokera.

Zakres:

- domknac import gaps dla `broker_profile.json`,
- upewnic sie, ze runtime eksportuje i audytuje `tick_size`, `tick_value`, `volume_min`, `volume_step`, `volume_max`, `stops_level`, `freeze_level`,
- dopiac parity dla suffixu `.pro` i state aliasow,
- wyeliminowac reczne mapowania poza helperami registry.

Najbardziej dotkniete miejsca:

- `MbBrokerProfilePlane.mqh`
- `BUILD_MT5_SYMBOL_METADATA_PROFILE_AUDIT.ps1`
- `microbots_registry.json`
- rollout/install docs

Warunek wyjscia:

- audit metadata nie pokazuje juz stalego `import_gaps` jako otwartego dlugu.

### Faza 2. Domkniecie Deployment Parity Calej Floty

Cel:

- przejsc z "repo gotowe" do "aktywny terminal faktycznie ma wszystkie wymagane artefakty".

Zakres:

- usunac brak `MicroBot_AUDUSD.ex5` z aktywnej instancji,
- doprowadzic `teacher_package_contract.csv` do `13/13`,
- utrzymac `runtime_control.csv`, `runtime_status.json`, `student_gate_contract.csv`, `broker_profile.json` dla calej floty,
- wzmocnic `PREPARE_MT5_ROLLOUT`, `INSTALL_MT5_SERVER_PACKAGE` i `VALIDATE_MT5_SERVER_INSTALL` o wymagane checki teacher package.

Warunek wyjscia:

- deployment audit przechodzi dla `13/13` bez luk kontraktowych.

### Faza 3. Wpiecie Promotion Pipeline do RUN

Cel:

- zamienic gotowe komponenty `CONTROL` w staly proces operacyjny.

Zakres:

- uruchamiac `build_teacher_promotion_snapshot.py` z `RUN`,
- uruchamiac `validate_teacher_promotion.py` z `RUN`,
- zapisywac `teacher_promotion_verdict_latest.json`,
- aktualizowac `teacher_promotion_history_latest.json`,
- budowac jawny report verdictow i cooldownow.

Brakujacy wynik tej fazy:

- nie moze juz byc sytuacji, w ktorej policy i validator istnieja, ale nic ich regularnie nie wykonuje.

Warunek wyjscia:

- verdict i historia odswiezaja sie bez recznej interwencji.

### Faza 4. Shadow Lifecycle dla GLOBAL_PLUS_PERSONAL

Cel:

- uczynic `GLOBAL_PLUS_PERSONAL` realna faza dojrzewania, a nie tylko polem w kontrakcie.

Zakres:

- jawne przejscia `GLOBAL_ONLY -> GLOBAL_PLUS_PERSONAL -> PERSONAL_PRIMARY`,
- guarded fallback,
- hard rollback,
- historia przejsc i cooldownow per symbol,
- jawna interpretacja verdictu w runtime i control-plane.

Warunek wyjscia:

- `GLOBAL_PLUS_PERSONAL` ma dowod historii, a nie tylko flage.

### Faza 5. Routing ONNX i Teacher Runtime

Cel:

- domknac wykonawczo personalnego teacher runtime tam, gdzie plan `Pro` dotyka realnych modeli.

Zakres:

- przebudowac ladowanie nauczyciela w `MbOnnxPilotObservation.mqh`,
- wprowadzic routing po `teacher_id` albo `teacher_package_mode`,
- zachowac bezpieczny fallback do `_GLOBAL`,
- utrzymac zgodnosc z `PREPARE_RUNTIME_ONNX_PILOT.ps1` i `ENSURE_SHADOW_RUNTIME_BOOTSTRAP.ps1`.

Warunek wyjscia:

- runtime przestaje byc na stale przywiazany do `_GLOBAL` jako jedynego nauczyciela.

### Faza 6. Dowod Feature Parity i Gotowosci ML

Cel:

- udowodnic, ze personalny teacher nie jest tylko kontraktem wiedzy, ale rzeczywista warstwa danych i modelu.

Zakres:

- audyt emisji wszystkich wymaganych cech dla `13` symboli,
- audyt wykorzystania tych cech w treningu,
- audyt jakosci cech i coverage,
- audyt lokalnych modeli per symbol,
- audyt promotion truth i quality deltas.

Warunek wyjscia:

- kazdy symbol ma twardy dowod: feature space, model readiness, promotion readiness.

### Faza 7. Retraining / Promotion / Rollback Loop

Cel:

- domknac rekomendacje `Pro` na poziomie lifecycle, a nie tylko artifactow.

Zakres:

- scheduled retraining,
- scheduled verdict evaluation,
- controlled promotion,
- controlled rollback,
- zapis decyzji i efektu decyzji,
- audit trail dla operatora i brygady nadzoru.

Warunek wyjscia:

- system umie nie tylko budowac modele, ale takze nimi operacyjnie zarzadzac w czasie.

### Faza 8. Migracja i Rollout Globalny

Cel:

- zrobic z migracji element stalego procesu, a nie jednorazowy reczny handoff.

Zakres:

- preferowana droga przez `DEPLOY_MT5_PACKAGE_TO_REMOTE.ps1`,
- jawne `remote_terminal_data_dir` i `remote_common_files_dir`,
- hash-based deploy i pruning stale managed files,
- package parity laptop -> terminal -> `VPS`,
- kontrolowany rollback package.

Warunek wyjscia:

- wdrozenie zdalne jest reprodukowalne i nie zalezy od ukrytej wiedzy operatorskiej.

### Faza 9. Full-Stack Go/No-Go

Cel:

- zamknac caly program jednym spietym gate.

Zakres:

- laczny audit kontraktow,
- laczny audit runtime,
- laczny audit broker parity,
- laczny audit ML readiness,
- laczny audit deployment parity,
- laczny audit startupu po migracji.

Warunek wyjscia:

- system ma formalny status: `GO`, `SHADOW_ONLY` albo `NO-GO`.

## Kolejnosc Wdrozenia Flotowego

Wdrozenie nie powinno isc od razu po calej flocie w trybie `PERSONAL_PRIMARY`.

Rekomendowana kolejnosc:

1. Domknac cala warstwe kontraktu, parity i deploymentu dla `13` symboli.
2. Domknac `RUN` promotion pipeline.
3. Uruchomic pierwszy kontrolowany pilot `GLOBAL_PLUS_PERSONAL` na `EURUSD`.
4. Po stabilizacji rozszerzac shadow na kolejne symbole o najwyzszej gotowosci.
5. Dopiero po dowodzie stabilnosci rozwazac `PERSONAL_PRIMARY`.

## Wlasciciele Wykonawczy

Zmiana jest zbyt szeroka dla jednej brygady i musi byc prowadzona wielotorowo.

### BRYGADA ARCHITEKTURA I INNOWACJE

Zakres:

- kontrakty,
- mapa zaleznosci,
- zasady semantyczne,
- granice zmian i guardraile.

### BRYGADA ROZWOJ KODU

Zakres:

- `MQL5/Include/Core`,
- `MicroBot_*`,
- integracja runtime,
- `ONNX` routing,
- helpery i build tools.

### BRYGADA ML I MIGRACJA MT5

Zakres:

- lokalne modele,
- runtime `ONNX`,
- shadow bootstrap,
- parity ML state laptop -> terminal.

### BRYGADA NADZOR UCZENIA I GO-NO-GO

Zakres:

- readiness,
- verdicty,
- cooldowny,
- quality gates,
- finalne `GO/NO-GO`.

### BRYGADA WDROZENIA MT5

Zakres:

- package,
- install,
- validate,
- remote deploy,
- parity terminal / `VPS`.

### BRYGADA AUDYT I CLEANUP

Zakres:

- residue,
- stare artefakty,
- stare presety,
- drift po migracjach,
- higiena evidence i backupow.

## Definicja Done Dla Calego Programu

Program mozna uznac za globalnie wdrozony dopiero, gdy jednoczesnie sa prawdziwe wszystkie ponizsze punkty:

1. `13/13` symboli ma komplet deploymentowych i runtime artefaktow.
2. `13/13` symboli przechodzi aktywny deployment audit bez brakow `ex5`, package i broker profile.
3. Broker metadata audit nie pokazuje krytycznych `import_gaps`.
4. Promotion pipeline dziala z `RUN`, a nie tylko z recznego wywolania `CONTROL`.
5. Historia verdictow i cooldowny sa zapisywane per symbol.
6. `GLOBAL_PLUS_PERSONAL` ma realny shadow lifecycle.
7. Runtime `ONNX` ma jawny i bezpieczny teacher routing z fallbackiem do `_GLOBAL`.
8. Dla symboli dopuszczanych do personalizacji istnieje dowod feature parity i model readiness.
9. Zdalny deploy jest powtarzalny i walidowany.
10. Dokumentacja operatorska i handoff odzwierciedlaja aktualny runtime.

## Czego Nie Nalezy Robic

1. Nie wlaczac szerokiego `PERSONAL_PRIMARY` bez historii i verdict loop.
2. Nie zmieniac routingu `ONNX` bez fallbacku i rollbacku.
3. Nie prowadzic zmian tylko w `DOCS` albo tylko w `MQL5`.
4. Nie utrzymywac recznych, ukrytych map nazw poza registry i helperami.
5. Nie traktowac migracji jako osobnego tematu od ML i runtime.
6. Nie przykrywac luk deploymentowych samym twierdzeniem, ze repo ma pliki zrodlowe.

## Co Mozna Zrobic Od Razu

To da sie uruchomic od razu na tym etapie:

- odswiezenie bazy audytowej stanu zero,
- domkniecie deployment parity do `13/13`,
- wpiecie promotion pipeline do `RUN`,
- zbudowanie jawnej historii verdictow,
- domkniecie broker metadata parity,
- przygotowanie kontrolowanego pilota `EURUSD` w `GLOBAL_PLUS_PERSONAL`.

## Co Jest Jeszcze Za Wczesnie Na Masowe Wlaczenie

Na dzis za wczesnie na:

- pelne globalne `PERSONAL_PRIMARY` dla calej floty,
- slepe wlaczenie lokalnych modeli bez parity feature space,
- uznanie systemu za autonomiczny lifecycle teacherow end-to-end.

## Jednoznaczna Odpowiedz Koncowa

Tak, jestem w stanie poprowadzic i wdrozyc te zmiany globalnie w repo, tak aby objac wszystkie glowne ogniwa systemu:

- kontrakty,
- runtime,
- `MQL5`,
- `CONTROL`,
- `RUN`,
- deployment,
- migracje,
- audyty,
- handoff.

Nie moge jednak uczciwie obiecac, ze nalezy zrobic to w jednym skoku bez fazowania.

Jednoznaczna odpowiedz brzmi wiec:

- tak, globalne wdrozenie jest wykonalne,
- tak, da sie je poprowadzic bez swiadomego pomijania ogniw,
- ale tylko pod warunkiem realizacji tego planu falami, z twardymi auditami po kazdej fazie.

To jest poprawna technicznie odpowiedz dla systemu tej skali.
