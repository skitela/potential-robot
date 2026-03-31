# Raport Dla GPT Pro - Siodemka Global Teacher 2026-03-31

## 1. Co juz dziala

### Pierwsza fala - nauczyciele osobisci

Symbole:
- `US500`
- `EURJPY`
- `AUDUSD`
- `USDCAD`

To jest nasz wzorzec dojrzalej nauki.

Najwazniejsze rzeczy, ktore tam juz dzialaja:
- bogatszy tor per instrument,
- domkniety paper chain:
  `PAPER_OPEN -> PAPER_CLOSE -> EXECUTION_TRUTH_CLOSE -> LESSON_WRITE -> KNOWLEDGE_WRITE`
- lepszy zapis kontekstu pozycji,
- dojrzalsza warstwa lokalnego modelu i decyzji symbol-specyficznej.

### Druga partia - nauczyciel globalny

Symbole:
- `DE30`
- `GOLD`
- `SILVER`
- `USDJPY`
- `USDCHF`
- `COPPER-US`
- `EURAUD`
- `EURUSD`
- `GBPUSD`

Na laptopie uruchomione sa wszystkie 9 botow pod profilem paper-learning.

Potwierdzony stan z audytu:
- verdict: `GLOBAL_TEACHER_COHORT_CZESCIOWO_AKTYWNY`
- teacher_runtime_active_count: `2`
- fresh_full_lesson_count: `2`

Symbole, ktore rzeczywiscie ucza sie teraz:
- `GOLD`
- `SILVER`

Symbole, ktore zyja obserwacyjnie, ale nie domykaja swiezych lekcji:
- `DE30`
- `USDJPY`
- `USDCHF`
- `COPPER-US`
- `EURAUD`
- `EURUSD`
- `GBPUSD`

## 2. Co wiemy o architekturze

Druga partia uczy sie pod nauczycielem globalnym, ale nie jest to osobna, uboga sciezka.
Rdzen obserwacji jest wspolny z pierwsza fala:
- `MbOnnxPilotObservation.mqh` buduje obserwacje z kontekstu rynku i laduje listy cech z runtime manifestow,
- zapisuje miedzy innymi:
  - `teacher_score`
  - `symbol_score`
  - `market_regime`
  - `spread_regime`
  - `confidence_bucket`
  - `spread_points`
  - `score`
  - `confidence_score`
- most runtime ML dopina warstwe ekonomiczna i wykonawcza:
  - `expected_edge_pln`
  - `decision_score_pln`
  - `server_ping_ms`
  - `server_latency_us_avg`
  - `local_training_mode`

Najwazniejsza roznica:
- pierwsza fala schodzi juz do bogatszego toru per instrument,
- druga partia pracuje glownie w `FALLBACK_ONLY`, czyli opiera sie na nauczycielu wspolnym i nie wymaga lokalnego modelu per symbol do startu.

## 3. Co odblokowalo dotychczas globalnego nauczyciela

Wazne ruchy, ktore juz weszly:
- uruchomienie calej dziewiatki w paper-learning na laptopie,
- diagnostyczny plik `global_teacher_cohort_diagnostic.csv`,
- `TIMER_FALLBACK_SCAN`,
- rescue tuningowe w botach,
- audyt aktywnosci drugiej partii,
- podpiecie supervisorow do obserwacji nie tylko plikow, ale swiezych lekcji i wiedzy.

To wystarczylo, zeby `GOLD` i `SILVER` zaczely dawac swieze lekcje.

## 4. Co nadal nie dziala

Dla pozostalej siodemki typowy wzorzec jest taki:
- swiezy `decision_events.csv`
- swiezy `onnx_observations.csv`
- brak swiezego `student_gate_latest.json`
- brak swiezego `learning_observations_v2.csv`
- brak swiezego `broker_net_ledger_runtime.csv`

To znaczy:
- obserwacja dziala,
- bot zyje,
- ale nie przechodzi stabilnie do bramki studenta, lekcji i wiedzy.

W logach zatrzymanych symboli, szczegolnie `EURUSD`, mocno powtarza sie:
- `SCORE_BELOW_TRIGGER`

## 5. Co jest pytaniem do rozwiazania

Chcemy ustalic:
- czy globalny nauczyciel juz teraz uczy na wystarczajaco takim samym rdzeniu cech jak pierwsza czworka,
- czy problemem jest jeszcze brak ktorejs warstwy cech, warstwy ekonomicznej, telemetrycznej albo kosztowej,
- dlaczego `GOLD` i `SILVER` przechodza do wiedzy, a siodemka nie,
- czy najpierw doprowadzic `9/9` na nauczycielu globalnym, czy czesc siodemki juz teraz schodzic do nauczycieli osobistych.

## 6. Stan wzgledem VPS

Tego materialu nie nalezy czytac tak, jakby druga partia byla juz potwierdzona na VPS.

Stan uczciwy jest taki:
- potwierdzenie mamy lokalnie na laptopie,
- dla `GOLD` i `SILVER` potwierdzona jest lokalna swieza nauka,
- dla siodemki nie ma jeszcze lokalnego potwierdzenia swiezych lekcji,
- dopiero po dojściu do `9/9` lokalnie chcemy przejsc do etapu paper-learning na VPS.

## 7. Zalaczone pliki i ich rola

- `MbGlobalTeacherLearningDiagnostic.mqh`
  - diagnostyka i rescue global teacher
- `MbOnnxPilotObservation.mqh`
  - wspolny pipeline obserwacji i cech
- `MbMlRuntimeBridge.mqh`
  - warstwa runtime, bramki, score ekonomiczny i tryb treningu
- `FOCUS_GLOBAL_TEACHER_COHORT_LEARNING.ps1`
  - launcher calej dziewiatki
- `BUILD_GLOBAL_TEACHER_COHORT_ACTIVITY_AUDIT.ps1`
  - audyt zliczajacy runtime nauczyciela i swieze lekcje
- `MicroBot_GOLD.mq5`
  - przyklad symbolu, ktory teraz realnie sie uczy
- `MicroBot_EURUSD.mq5`
  - przyklad symbolu, ktory zyje, ale nie domyka nauki
- `MicroBot_US500.mq5`
  - wzorzec pierwszej fali z bogatszym torem per instrument

## 8. Czego oczekujemy od analizy Pro

Prosimy o:
- diagnoze, co blokuje siodemke,
- liste minimalnych poprawek, zeby dojsc do `9/9`,
- ocene zgodnosci zestawu cech globalnego nauczyciela z pierwsza fala,
- plan przejscia:
  - laptop local paper-learning,
  - VPS paper-learning,
  - canary,
  - live paper,
- liste alarmow, ktore supervisor uczenia ma podnosic dla kazdego symbolu.
