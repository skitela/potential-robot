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

## Najwazniejsze roznice do zamkniecia przed wdrozeniem

### 1. `paper_live_bucket` jest przeciazony w obecnym builderze repo

W repo:
- `CONTROL/build_teacher_package.py` zapisuje `paper_live_bucket = mode`

To jest bledne semantycznie, bo:
- `paper_live_bucket` juz ma znaczenie deployment/parity,
- tryb nauczyciela to osobna os semantyczna.

Wymagana korekta:
- dodac osobne pole `teacher_package_mode` albo `teacher_runtime_mode`,
- przestac wpisywac `GLOBAL_ONLY`, `GLOBAL_PLUS_PERSONAL`, `PERSONAL_PRIMARY` do `paper_live_bucket`.

### 2. Walidator promocji nie ma jeszcze pelnego snapshotu z obecnego control-plane

Repo ma walidator, ale nie ma jeszcze kompletnego adaptera dostarczajacego:
- `full_lessons_window`
- `gate_visible_events_window`
- `feature_coverage_ratio`
- `days_observed`
- `unclassified_count`
- `sticky_diagnostic`
- `relative_quality_vs_global`
- `quality_drop_vs_baseline`

`BRYGADA` dodaje brakujacy element:
- `build_teacher_promotion_snapshot.py`

### 3. Personal curricula w repo sa zbyt waskie

Repo ma tylko:
- `CONFIG/personal_teacher_curriculum_EURUSD_v1.json`

`BRYGADA` ma:
- registry oraz curricula dla calej aktywnej 13-symbolowej floty.

### 4. Obecny teacher snapshot nie ma jeszcze pelnego procesu history/hysteresis

`BRYGADA` bardzo sensownie dodaje:
- approval streak,
- cooldown promocji,
- cooldown rollbacku,
- rozdzielenie `GLOBAL_PLUS_PERSONAL` od `PERSONAL_PRIMARY`.

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

## Plan wdrozenia etapami

## Etap 1. Naprawa semantyki kontraktu teacher package

Cel:
- oddzielic deployment bucket od teacher runtime mode.

Zakres:
- poprawic `CONTROL/build_teacher_package.py`,
- poprawic `MQL5/Include/Core/MbTeacherPackage.mqh`,
- ewentualnie lekko dopasowac `MQL5/Include/Core/MbTeacherModeResolver.mqh`.

Wynik:
- `paper_live_bucket` zostaje deploymentowe,
- `teacher_package_mode` staje sie osobnym polem.

Kryterium odbioru:
- wygenerowany `teacher_package_contract.csv` niesie oba pola osobno,
- runtime laduje nowy kontrakt bez regresji.

## Etap 2. Promotion snapshot jako adapter nad obecnym CONTROL

Cel:
- zbudowac prawdziwe zrodlo dla decyzji promocyjnej.

Zakres:
- dodac `CONTROL/build_teacher_promotion_snapshot.py`,
- zmapowac wejscia z:
  - `learning_supervisor_snapshot_latest.json`
  - `supervisor_snapshot_latest.json`
  - `global_teacher_cohort_activity_latest.json`
  - `student_gate_latest.json`
  - metryk okiennych i audytow

Wynik:
- `teacher_promotion_snapshot_latest.json` per symbol.

Kryterium odbioru:
- `validate_teacher_promotion.py` dostaje pelny snapshot i nie musi zgadywac brakujacych pol.

## Etap 3. Lifecycle polityki: history, hysteresis, cooldown

Cel:
- odseparowac pojedyncze dobre okno od dojrzalej promocji.

Zakres:
- rozszerzyc `CONTROL/validate_teacher_promotion.py`,
- dodac obsluge:
  - `approval_streak`
  - `promotion_cooldown`
  - `rollback_cooldown`
  - `rollback triggers`
- wykorzystac:
  - `teacher_promotion_policy_v1.json`
  - `teacher_promotion_history_template_v1.json`

Wynik:
- werdykty:
  - `PROMOTE_TO_PERSONAL`
  - `HOLD_GLOBAL`
  - `ROLLBACK_TO_GLOBAL`
  staja sie stabilniejsze i audytowalne.

Kryterium odbioru:
- brak flappingu `PROMOTE/HOLD/ROLLBACK` na pojedynczych oknach.

## Etap 4. Rozszerzenie curricula i registry na cala aktywna flote

Cel:
- miec jeden, jawny rejestr pilotow personalnych.

Zakres:
- dodac `CONFIG/personal_teacher_curricula_registry_v1.json`,
- dodac curricula dla 13 aktywnych symboli,
- sprawdzic zgodnosc nazw symboli z repo.

Wynik:
- repo ma komplet curricula,
- ale aktywacja nadal etapowa.

Kryterium odbioru:
- registry jest zgodny z:
  - `learning_universe_contract.json`
  - `microbots_registry.json`

## Etap 5. Shadow mode i pierwszy pilot runtime

Cel:
- nie przeskakiwac prosto do `PERSONAL_PRIMARY`.

Zakres:
- pierwszy pilot: `EURUSD`,
- tryb:
  - start `GLOBAL_ONLY`
  - potem `GLOBAL_PLUS_PERSONAL`
  - dopiero po stabilnej promocji `PERSONAL_PRIMARY`
- bez zmiany routingu ONNX w pierwszej iteracji.

Wynik:
- personalny teacher jest liczony, oceniany i dokumentowany,
- ale globalny pozostaje glownym zabezpieczeniem.

Kryterium odbioru:
- `EURUSD` ma komplet:
  - curriculum
  - package manifest
  - promotion snapshot
  - promotion history
  - stabilny verdict bez flappingu.

## Kolejnosc techniczna prac

1. Poprawa `teacher_package_mode` w repo.
2. Dodanie `build_teacher_promotion_snapshot.py`.
3. Rozszerzenie `validate_teacher_promotion.py`.
4. Dodanie registry + curricula dla 13 symboli.
5. Integracja z `CONTROL` i `codex workbench`.
6. Dopiero potem pierwszy realny pilot `EURUSD`.

## Rekomendowany zakres pierwszego wdrozenia

### Do wdrozenia od razu
- separacja `teacher_package_mode`
- promotion snapshot builder
- policy + history + hysteresis
- curricula registry

### Do wdrozenia po walidacji
- komplet personal curricula do repo
- pierwszy pilot `EURUSD` w `GLOBAL_PLUS_PERSONAL`

### Na pozniej
- routing ONNX po `teacher_id` albo `teacher_package_mode`
- automatyczny guarded fallback / hard rollback w runtime

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
