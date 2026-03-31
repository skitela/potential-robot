# Druga Partia Global Teacher: Odblokowanie 2026-03-31

## Cel

Zachować twarde ustalenia z uruchomienia drugiej partii na laptopie tak, żeby:
- nie zginęły w historii rozmowy,
- dało się z nich skorzystać przy kolejnych partiach,
- było jasne, co było problemem infrastrukturalnym, a co blokuje już samo uczenie.

## Symbole

Druga partia uruchamiana na globalnym nauczycielu:
- DE30
- GOLD
- SILVER
- USDJPY
- USDCHF
- COPPER-US
- EURAUD
- EURUSD
- GBPUSD

## Co było prawdziwą blokadą na początku

To nie był problem modeli ani samych ekspertów.

Najpierw blokował nas profil MT5:
- terminal startował,
- ale nie ładował faktycznie ekspertów dla drugiej partii,
- osobny profil `MAKRO_I_MIKRO_BOT_GLOBAL_TEACHER_AUTO` był ignorowany przez ścieżkę startową terminala,
- dopiero użycie aktywnego aliasu `MAKRO_I_MIKRO_BOT_AUTO` przywróciło realne ładowanie dziewięciu botów.

Dodatkowo znaleziono i naprawiono dwa istotne szczegóły profilu:
- `order.wnd` musiał być zapisany jako `UTF-16LE` z `BOM`,
- charty dla drugiej partii musiały dostać pełne bezpieczne wejścia paper-learning:
  - `InpEnableLiveEntries=false`
  - `InpPaperCollectMode=true`
  - `InpEnableOnnxObservation=true`
  - `InpEnableMlRuntimeBridge=true`
  - `InpEnableStudentDecisionGate=false`

## Co potwierdziliśmy po naprawie profilu

Po rozruchu przez aktywny alias profilu:
- wszystkie 9 botów ładuje się lokalnie,
- wszystkie 9 zapisuje świeże decyzje,
- wszystkie 9 zapisuje świeże obserwacje ONNX,
- nie ma już stanu „profil wygląda dobrze, ale eksperci nie żyją”.

To był pierwszy realny przełom.

## Co blokowało naukę po uruchomieniu profilu

Kiedy profil już działał, okazało się, że problem przesunął się do lokalnych bramek paper-learning:
- `SCORE_BELOW_TRIGGER`
- `FOREFIELD_DIRTY_*`
- `PAPER_CONVERSION_BLOCKED_*`
- `PORTFOLIO_HEAT_BLOCK`
- pośrednio także przez kosztowe i tuningowe bramki symbol-specyficzne

Czyli druga partia:
- żyła obserwacyjnie,
- ale nie przechodziła stabilnie do `PAPER_OPEN`,
- a bez tego nie mogły powstać świeże lekcje i świeża wiedza.

## Co zostało wdrożone

### 1. Wspólny tryb diagnostyczny dla globalnego nauczyciela

Dodane zostało:
- `MQL5\Include\Core\MbGlobalTeacherLearningDiagnostic.mqh`
- `RUN\SET_GLOBAL_TEACHER_COHORT_DIAGNOSTIC_MODE.ps1`

Ten tryb:
- działa tylko w paper-learning,
- działa tylko dla dziewięciu symboli drugiej partii,
- wygasa sam po czasie przez świeżość pliku CSV,
- luzuje tylko miękkie bramki potrzebne do budowy lekcji.

### 2. Uruchamianie drugiej partii zawsze z aktywnym trybem diagnostycznym

`RUN\FOCUS_GLOBAL_TEACHER_COHORT_LEARNING.ps1`:
- aktywuje tryb diagnostyczny,
- generuje plan wykresów,
- ustawia aktywny profil,
- uruchamia terminal,
- odświeża audyt aktywności drugiej partii.

### 3. Wspólny bypass portfela dla paper-learning

`MbCandidateArbitration.mqh` dostał bezpieczny bypass:
- tylko dla paper-learning,
- tylko dla symboli drugiej partii,
- tylko dla `PORTFOLIO_HEAT_BLOCK`,
- tylko przy nie-złym reżimie wykonania i spreadzie.

### 4. Wpięcie diagnostycznego paper-gate do dziewięciu botów

Zmodyfikowane boty:
- `MicroBot_DE30.mq5`
- `MicroBot_GOLD.mq5`
- `MicroBot_SILVER.mq5`
- `MicroBot_USDJPY.mq5`
- `MicroBot_USDCHF.mq5`
- `MicroBot_COPPERUS.mq5`
- `MicroBot_EURAUD.mq5`
- `MicroBot_EURUSD.mq5`
- `MicroBot_GBPUSD.mq5`

Wspólne zmiany:
- boty rozpoznają aktywny tryb diagnostyczny drugiej partii,
- miękkie odrzucenia nie zatrzymują już paper-learning tak wcześnie,
- luzowane są tuning gate i cost gate wyłącznie w tym trybie,
- `paper_gate_abs` może być obniżony dla budowy pierwszych lekcji,
- wynik wpada jako:
  - `GLOBAL_TEACHER_SCORE_GATE_DIAGNOSTIC`

## Co mamy realnie po wdrożeniu

Po świeżym rozruchu:
- wszystkie 9 symboli jest aktywne obserwacyjnie,
- `teacher_runtime_active_count = 2`,
- `fresh_full_lesson_count = 1`

Najważniejszy dowód:
- `GOLD` ma świeżą lekcję i świeżą wiedzę,
- `SILVER` ma już świeże:
  - `EXEC_PRECHECK READY`
  - `PAPER_OPEN OK`
- pozostała siódemka nadal częściej kończy na tuning/family/fleet i jeszcze nie domknęła świeżej lekcji.

## Co to znaczy praktycznie

Stan obecny nie jest już „martwy”.

To jest już etap:
- 9/9 żyje lokalnie,
- co najmniej 1 symbol realnie domknął naukę,
- kolejny symbol doszedł do świeżego otwarcia,
- pozostałe wymagają dalszego dociśnięcia lokalnych bramek wejścia.

## Najważniejsze ścieżki dowodowe

- `EVIDENCE\OPS\global_teacher_cohort_activity_latest.json`
- `EVIDENCE\OPS\global_teacher_cohort_activity_latest.md`
- `EVIDENCE\OPS\global_teacher_cohort_focus_latest.json`
- `EVIDENCE\OPS\global_teacher_cohort_chart_plan_latest.json`
- `Common Files\MAKRO_I_MIKRO_BOT\logs\<symbol>\decision_events.csv`
- `Common Files\MAKRO_I_MIKRO_BOT\logs\<symbol>\onnx_observations.csv`
- `Common Files\MAKRO_I_MIKRO_BOT\logs\<symbol>\learning_observations_v2.csv`
- `Common Files\MAKRO_I_MIKRO_BOT\logs\<symbol>\broker_net_ledger_runtime.csv`

## Wniosek operacyjny

Druga partia została realnie uruchomiona na laptopie.

Najważniejsze:
- infrastruktura profilu jest naprawiona,
- dziewiątka żyje na globalnym nauczycielu,
- paper-learning dostał własny bezpieczny tryb diagnostyczny,
- `GOLD` już realnie domknął świeżą lekcję,
- `SILVER` jest już w świeżym otwarciu,
- czyli problem nie polega już na uruchomieniu grupy, tylko na dalszym dociśnięciu przejścia z obserwacji do pełnej lekcji dla pozostałych symboli.
