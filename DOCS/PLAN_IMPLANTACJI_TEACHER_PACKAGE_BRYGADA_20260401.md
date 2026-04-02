# PLAN IMPLANTACJI TEACHER PACKAGE BRYGADA DO AKTUALNEGO REPO

## Cel

Zintegrowac pakiet `C:\NAUKA GLOBALNA I INDYWIDUALNA BRYGADA` z aktualnym repo tak, aby:
- nie zrobic drugiego runtime nauczyciela,
- nie rozjechac semantyki obecnego `MbMlRuntimeBridge`,
- wykorzystac dojrzalszy proces promocji i rollbacku,
- zachowac kompatybilnosc z obecnym `CONTROL`, snapshotami i audit plane.

## Werdykt

Pakiet `BRYGADA` jest wart wdrozenia selektywnego. Nie powinien wejsc do repo jako hurtowa podmiana obecnych plikow teacher/runtime.

Najwazniejsze:
- repo jest silniejsze w runtime i integracji z MT5,
- `BRYGADA` jest silniejsza w procesie `globalny -> personalny`,
- poprawna droga to implantacja warstwowa: adaptery, polityki, registry i snapshot promocji, a nie wymiana calego runtime.

## Aktualizacja stanu po ostatnim wdrozeniu

Na dzien `2026-04-01` ten dokument nie moze juz byc czytany jako lista brakow "przed wdrozeniem".

Stan prawdy jest dzis taki:
- czesc kontraktowa i walidacyjna z planu `BRYGADA` zostala juz osadzona w repo,
- otwarte pozostaja elementy wykonawcze wysokiego ryzyka: orkiestracja `RUN`, routing runtime ONNX, shadow lifecycle i rollback jako proces operacyjny,
- problem nie polega juz na braku package/policy/blueprint, tylko na tym, ze nie caly plan `Pro` zostal jeszcze domkniety w stalej petli operacyjnej.

## Co juz mamy w repo i czego nie wolno zdublowac

### Runtime i bridge
- `CONTROL/build_teacher_package.py`
- `CONTROL/validate_teacher_promotion.py`
- `MQL5/Include/Core/MbTeacherPackage.mqh`
- `MQL5/Include/Core/MbTeacherModeResolver.mqh`
- `MQL5/Include/Core/MbTeacherKnowledgeSnapshot.mqh`
- `MQL5/Include/Core/MbMlRuntimeBridge.mqh`

### Snapshoty i supervision
- `MQL5/Include/Core/MbSupervisorSnapshot.mqh`
- `MQL5/Include/Core/MbLearningSupervisorSnapshot.mqh`
- `MQL5/Include/Core/MbMicrobotHooks.mqh`
- `CONTROL/build_system_snapshot.py`
- `CONTROL/build_symbol_health_matrix.py`
- `CONTROL/build_learning_supervisor_matrix.py`
- `CONTROL/build_learning_action_plan.py`

### Kontrakty uniwersum
- `CONFIG/learning_universe_contract.json`
- `CONFIG/microbots_registry.json`

## Co `BRYGADA` wnosi realnie nowego

### Proces i lifecycle
- `build_teacher_promotion_snapshot.py`
- `teacher_learning_process_blueprint_v1.json`
- `teacher_promotion_policy_v1.json`
- `teacher_promotion_history_template_v1.json`

### Szerszy zasieg curriculum
- `personal_teacher_curricula_registry_v1.json`
- zestaw `personal_teacher_curriculum_<SYMBOL>_v1.json` dla 13 aktywnych symboli

### Dodatkowe audyty i notatki architektoniczne
- `DLA_CODEX__AUDYT_DOPASOWANIA_TEACHER_PACKAGE_DO_AKTUALNEGO_REPO__20260401.md`
- `DLA_CODEX__PLAN_ROZWOJU_PROCESU_UCZENIA__20260401.md`
- `DLA_CODEX__WALIDACJA_PLANOW_NAUCZYCIELI__20260401.md`

## Status po ostatnim wdrozeniu

### Zamkniete w repo

### 1. Separacja `teacher_package_mode` od `paper_live_bucket`

Ten zarzut byl prawdziwy wczesniej, ale jest juz zamkniety.

W repo:
- `CONTROL/build_teacher_package.py` zapisuje dzis osobno `paper_live_bucket = deployment_bucket` i `teacher_package_mode`,
- `MQL5/Include/Core/MbTeacherPackage.mqh` laduje oba pola rozdzielnie,
- `CONFIG/teacher_package_schema_v1.json` pilnuje, ze `teacher_package_mode` ma pozostac oddzielone od `paper_live_bucket`.

Wniosek:
- problem przeciazenia semantyki bucketu nie jest juz otwartym brakiem.

### 2. Adapter `promotion snapshot`

Ten punkt jest juz wdrozony.

W repo istnieje:
- `CONTROL/build_teacher_promotion_snapshot.py`,
- builder sklada snapshot z wielu zrodel: learning snapshot, supervisor snapshot, teacher snapshot, cohort audit, student gate i window metrics.

Wniosek:
- promotion nie musi juz opierac sie na pojedynczym surowym snapshotcie runtime.

### 3. Historia, histereza i cooldowny promocji

Ten punkt jest juz wdrozony po stronie kontraktu i walidacji.

W repo istnieje:
- `CONTROL/validate_teacher_promotion.py`,
- `CONFIG/teacher_promotion_policy_v1.json`,
- `CONFIG/teacher_promotion_history_template_v1.json`.

Walidator umie dzis:
- liczyc `approval_streak`,
- pilnowac `promotion_cooldown_hours`,
- pilnowac `rollback_cooldown_hours`,
- oceniac rollback triggers,
- rozrozniac `PROMOTE_TO_PERSONAL`, `HOLD_GLOBAL` i `ROLLBACK_TO_GLOBAL`.

Wniosek:
- brak historii/histerezy nie jest juz prawdziwa krytyka obecnego repo.

### 4. Blueprint faz dojrzewania

Ten punkt jest juz wdrozony.

W repo istnieje:
- `CONFIG/teacher_learning_process_blueprint_v1.json`,
- blueprint prowadzi fazy `GLOBAL_ONLY -> GLOBAL_PLUS_PERSONAL -> PERSONAL_PRIMARY` i jawnie zabrania przeciazania `paper_live_bucket` oraz udawania dynamicznego routingu ONNX w fazie 1.

### 5. Registry i curricula dla calej aktywnej floty

Ten punkt jest juz wdrozony.

W repo istnieje:
- `CONFIG/personal_teacher_curricula_registry_v1.json`,
- komplet `CONFIG/personal_teacher_curriculum_*.json` dla 13 aktywnych symboli.

Wniosek:
- zewnetrzny dokument nie jest juz aktualny tam, gdzie sugerowal tylko pojedynczy pilot `EURUSD` bez pelnej floty curricula.

### 6. Szerokosc kontraktu personalnych curricula

Ten punkt jest dzis czesciowo zamkniety na poziomie kontraktu wiedzy.

Repo ma juz w curricula pasma typu:
- `local_policy_blocks`,
- `local_intermarket`,
- `local_promotion_readiness`,
- wskazniki `feature_quality_ratio` i `relative_quality_vs_family` w gate/promocji.

Wniosek:
- nie mozna juz uczciwie twierdzic, ze repo nie ma tych kategorii w ogole.
- Nadal otwarte pozostaje cos innego: dowod runtime, ze te pola sa stale emitowane, utrzymywane i wykorzystywane w treningu/promocji dla calej floty.

### Nadal otwarte i realnie blokujace domkniecie planu `Pro`

### 1. Brak pelnej orkiestracji promotion pipeline end-to-end w `RUN`

To pozostaje otwarte.

Na dzis nie ma jeszcze stalej petli operacyjnej, ktora:
- buduje `teacher_promotion_snapshot_latest.json`,
- liczy verdict przez `validate_teacher_promotion.py`,
- zapisuje `teacher_promotion_verdict_latest.json`,
- aktualizuje `teacher_promotion_history_latest.json`,
- robi to stale jako czesc `RUN`.

Wniosek:
- warstwa kontraktu jest gotowa, ale control-plane nie zostal jeszcze wpiety do regularnego cyklu pracy.

### 2. Brak dynamicznego routingu ONNX po `teacher_id` albo `teacher_package_mode`

To pozostaje otwarte.

W runtime:
- `MQL5/Include/Core/MbOnnxPilotObservation.mqh` nadal laduje nauczyciela globalnego z `_GLOBAL`,
- kontrakt globalny i model globalny sa pobierane ze sciezek `paper_gate_acceptor_runtime_contract_latest.csv` oraz `paper_gate_acceptor_runtime_latest.onnx` dla `_GLOBAL`.

Wniosek:
- teacher package juz istnieje,
- teacher mode juz istnieje,
- ale runtime ONNX nie przelacza jeszcze modelu dynamicznie wedlug personalnego package.

### 3. `GLOBAL_PLUS_PERSONAL` nie jest jeszcze pelnym shadow lifecycle sterowanym operacyjnie

To pozostaje otwarte.

Mamy juz:
- tryb,
- blueprint,
- validator,
- policy,
- historiograficzny template.

Brakuje nadal:
- stalego zapisu historii verdictow per symbol,
- automatycznego przejscia miedzy fazami na podstawie historii,
- guarded fallback / hard rollback jako jawnego procesu operacyjnego.

### 4. Brak dowodu pelnej runtimeowej dojrzalosci personalnych nauczycieli dla calej floty

To pozostaje otwarte.

Fakt, ze mamy curricula dla 13 symboli, nie dowodzi jeszcze, ze kazdy symbol:
- ma gotowy lokalny model,
- ma pelny runtime feature space,
- ma stale promotion truth,
- jest gotowy do `PERSONAL_PRIMARY`.

Wniosek:
- pakiet wiedzy jest przygotowany szybciej niz pelna gotowosc runtime.

### 5. Brak domknietego operational loop dla retraining / promotion / rollback

To pozostaje otwarte.

Brakuje nadal:
- scheduled retraining jako spojnego procesu,
- promotion / rollback jako stalej automatyki,
- kontrolowanego zapisu decyzji i reakcji systemu na te decyzje.

To jest nadal wdrozenie typu:
- `phase 1 / phase 2 foundation`,
- a nie pelny autonomiczny lifecycle nauczyciela.

## Czego nie wolno zrobic

Nie wolno:
- hurtowo podmienic obecnych plikow `MbTeacher*.mqh`,
- zrobic drugiego kontraktu runtime obok `MbMlRuntimeBridge`,
- podmienic `teacher_mode` z `learning_universe_contract.json` nowymi trybami runtime,
- zmieniac teraz routingu ONNX na podstawie samego istnienia personal curriculum,
- wrzucic do repo smieci operatorskich z `BRYGADA`:
  - `.mypy_cache/`
  - `monitor_codex_changes.log`

## Co bierzemy z `BRYGADA` wprost

Mozna przeniesc niemal 1:1 po przegladzie:
- `build_teacher_promotion_snapshot.py`
- `teacher_learning_process_blueprint_v1.json`
- `teacher_promotion_history_template_v1.json`
- `teacher_window_metrics_template_EURUSD_v1.json`
- `teacher_promotion_snapshot_template_EURUSD_v1.json`
- `personal_teacher_curricula_registry_v1.json`
- komplet `personal_teacher_curriculum_<SYMBOL>_v1.json`

Uwagi:
- nazwy `COPPERUS` trzeba zmapowac do repozytoryjnego `COPPER-US`,
- registry musi byc zgodny z `CONFIG/microbots_registry.json` oraz `CONFIG/learning_universe_contract.json`.

## Co bierzemy z `BRYGADA`, ale adaptujemy

### Python
- `build_teacher_package.py`
  - zachowac logike dziedziczenia curriculum,
  - usunac przeciazenie `paper_live_bucket`,
  - dodac `teacher_package_mode`,
  - zostawic kontrakt zgodny z obecnym `MbMlRuntimeBridge`.

- `validate_teacher_promotion.py`
  - rozszerzyc obecny walidator o:
    - historyczne verdicts,
    - approval streak,
    - promotion cooldown,
    - rollback cooldown,
    - rollback triggers,
  - ale karmic go promotion snapshotem z `CONTROL`, nie raw runtime snapshotem.

### MQL5
- `MbTeacherPackage.mqh`
  - zachowac obecny loader jako baze,
  - dodac nowe pole `teacher_package_mode`,
  - nie rozwalac kompatybilnosci z juz wygenerowanymi plikami.

- `MbTeacherModeResolver.mqh`
  - utrzymac jako cienki resolver nad:
    - `learning_universe_contract.teacher_mode`
    - `teacher_package_mode`
    - `promotion verdict`
  - nie robic z niego routera ONNX.

- `MbTeacherKnowledgeSnapshot.mqh`
  - utrzymac jako snapshot suplementarny,
  - nie robic z niego trzeciego glownego snapshotu runtime.

## Czego nie importujemy teraz

Nie importujemy teraz jako produktu runtime:
- `monitor_codex_changes.ps1`
- `monitor_codex_changes.log`
- `.mypy_cache/`
- promptow operatorskich

One moga byc materialem pomocniczym, ale nie warstwa systemowa.

## Pozostaly plan domkniecia `Pro`

## Etap 1. Wpiecie promotion pipeline do `RUN`

Cel:
- przestac utrzymywac snapshot/validator jako narzedzia tylko kontraktowe.

Zakres:
- uruchamiac `CONTROL/build_teacher_promotion_snapshot.py` z cyklu operacyjnego,
- uruchamiac `CONTROL/validate_teacher_promotion.py` z cyklu operacyjnego,
- zapisywac `teacher_promotion_verdict_latest.json`,
- utrzymywac `teacher_promotion_history_latest.json` per symbol.

Kryterium odbioru:
- verdict i historia sa odswiezane regularnie bez recznej interwencji.

## Etap 2. Pierwszy prawdziwy pilot `GLOBAL_PLUS_PERSONAL`

Cel:
- wejsc w kontrolowany shadow mode bez udawania pelnego `PERSONAL_PRIMARY`.

Zakres:
- pilot na `EURUSD`,
- 24-48h stabilnych danych,
- kontrola flappingu verdictow,
- jawny monitoring historii promocji.

Kryterium odbioru:
- `EURUSD` przechodzi czysto przez `GLOBAL_ONLY -> GLOBAL_PLUS_PERSONAL` bez utraty globalnego fallbacku.

## Etap 3. Lifecycle przejsc i rollback jako proces, nie tylko kontrakt

Cel:
- zamienic blueprint i policy w realna automatyke systemowa.

Zakres:
- jawne przejscia miedzy fazami na podstawie historii,
- guarded fallback,
- hard rollback,
- audytowalny zapis decyzji i reakcji systemu.

Kryterium odbioru:
- system umie nie tylko wydac verdict, ale tez konsekwentnie nim zarzadzic w runtime.

## Etap 4. Routing runtime ONNX

Cel:
- domknac wykonawczo personalnego nauczyciela tam, gdzie plan `Pro` faktycznie dotyka runtime.

Zakres:
- routing po `teacher_id` albo `teacher_package_mode`,
- albo inny jawny mechanizm przelaczania modelu teacher runtime,
- z zachowaniem bezpiecznego fallbacku do `_GLOBAL`.

Kryterium odbioru:
- runtime nie jest juz skazany na stalego globalnego teacher modela.

## Etap 5. Dowod gotowosci flotowej

Cel:
- udowodnic, ze personalny teacher nie jest tylko kontraktem wiedzy.

Zakres:
- audyt emisji feature space dla 13 symboli,
- audyt dostepnosci modeli lokalnych,
- audyt promotion truth i jakosci cech,
- dopiero potem rozszerzanie `PERSONAL_PRIMARY`.

Kryterium odbioru:
- kazdy symbol ma dowod runtimeowej dojrzalosci, a nie tylko curriculum.

## Jednoznaczny werdykt gotowosci

### Gotowi teraz

- do dalszego wdrazania: tak,
- do domkniecia control-plane: tak,
- do rozpoczecia pierwszego kontrolowanego pilota shadow po wpiece do `RUN`: tak.

### Jeszcze nie gotowi

- do szerokiego `PERSONAL_PRIMARY` dla calej floty,
- do pelnego autonomicznego lifecycle nauczyciela,
- do uczciwego twierdzenia, ze runtime personalnych teacherow jest juz domkniety end-to-end.

### Praktyczny horyzont

- nastepny etap: od razu,
- pierwszy sensowny pilot shadow: po 1-2 czystych iteracjach wdrozeniowych i `24-48h` stabilnych danych,
- pelna dojrzalosc: dopiero po kilku kolejnych cyklach stabilnej walidacji, nie po samym wdrozeniu kodu.

## Jak to laczy sie z obecnym problemem uczenia

To wdrozenie nie naprawia samo z siebie ostatniej trojki:
- `USDJPY`
- `COPPER-US`
- `EURAUD`

Ono rozwiazuje inny problem:
- jak system ma dojrzale zarzadzac nauczycielem globalnym i personalnym,
- jak nie zgubic wiedzy operatora,
- jak kontrolowac promocje nauczyciela bez psucia runtime.

Czyli:
- front supervision i domykania kohorty pozostaje osobny,
- front teacher package daje nam trwaly lifecycle wiedzy.

## Finalna rekomendacja

Wchodzimy z `BRYGADA` selektywnie i etapowo.

Najpierw:
- kontrakt,
- promotion snapshot,
- polityka,
- historia,
- registry.

Potem:
- shadow mode dla `EURUSD`.

Nie robimy teraz:
- hurtowej podmiany teacher runtime,
- zmiany routingu ONNX,
- masowego wlaczenia personal primary dla calej floty.

To jest najbezpieczniejsza droga, z ktorej da sie skorzystac bez niszczenia obecnego makro/mikro runtime.
