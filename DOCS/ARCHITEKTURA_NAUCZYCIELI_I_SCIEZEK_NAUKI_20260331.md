# Architektura Nauczycieli I Sciezek Nauki

Ten zapis utrwala dwa rozne tory nauki, zeby za pol roku nie odtwarzac tego z logow.

## Pierwsza fala

Symbole:
- `US500`
- `EURJPY`
- `AUDUSD`
- `USDCAD`

Cel:
- dojscie do lokalnego modelu per instrument,
- domykanie pelnego lancucha:
  `OBSERVED -> PRECHECK -> PAPER_OPEN -> PAPER_CLOSE -> EXECUTION_TRUTH_CLOSE -> LESSON_WRITE -> KNOWLEDGE_WRITE`

Najwazniejsze miejsca w kodzie:
- `MQL5/Include/Core/MbOnnxPilotObservation.mqh`
- `MQL5/Include/Core/MbMlRuntimeBridge.mqh`
- `MQL5/Include/Core/MbPaperTrading.mqh`
- `MQL5/Include/Core/MbExecutionTruthFeed.mqh`
- `MQL5/Include/Core/MbLearningContext.mqh`
- `MQL5/Experts/MicroBots/MicroBot_US500.mq5`
- `MQL5/Experts/MicroBots/MicroBot_EURJPY.mq5`
- `MQL5/Experts/MicroBots/MicroBot_AUDUSD.mq5`
- `MQL5/Experts/MicroBots/MicroBot_USDCAD.mq5`

Jak podlaczamy nauczyciela osobistego:
- kontrakt runtime musi miec lokalny model dla symbolu,
- `MbMlRuntimeBridge` nie moze zostac w `FALLBACK_ONLY`,
- `MbOnnxPilotObservation` liczy najpierw wynik nauczyciela wspolnego, a potem wynik lokalnego modelu symbolu,
- student gate i decyzja lokalna dostaja juz kontekst konkretnego instrumentu.

## Druga partia z nauczycielem globalnym

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

Cel:
- utrzymac ciagla obserwacje i papierowe lekcje na laptopie,
- uczyc na nauczycielu wspolnym, dopoki nie bedzie sensu schodzic do modeli lokalnych.

Najwazniejsze miejsca w kodzie:
- `MQL5/Include/Core/MbGlobalTeacherLearningDiagnostic.mqh`
- `MQL5/Include/Core/MbCandidateArbitration.mqh`
- `MQL5/Include/Core/MbOnnxPilotObservation.mqh`
- `RUN/FOCUS_GLOBAL_TEACHER_COHORT_LEARNING.ps1`
- `RUN/SET_GLOBAL_TEACHER_COHORT_DIAGNOSTIC_MODE.ps1`
- `RUN/BUILD_GLOBAL_TEACHER_COHORT_ACTIVITY_AUDIT.ps1`

Jak podlaczamy nauczyciela globalnego:
- runtime idzie w `local_training_mode = FALLBACK_ONLY`,
- `MbOnnxPilotObservation` zapisuje te same obserwacje rynku, ale decyzja symbolu opiera sie na wyniku nauczyciela wspolnego,
- lokalny model instrumentu nie jest wymagany do startu,
- paper-learning ma prawo uzyc diagnostycznych obejsc, zeby nie utknac na `SCORE_BELOW_TRIGGER`, kosztowych bramkach albo zamrozeniach rodzin/floty.

## Czy globalny nauczyciel uczy na tych samych zmiennych

W duzej czesci tak.

Wspolne elementy:
- ten sam `MbSignalDecision`,
- ten sam kontekst rynku,
- te same pola obserwacji ONNX,
- ten sam zapis obserwacji i gate state.

Roznica:
- pierwsza fala moze uzyc lokalnego modelu symbolu i osobistego nauczyciela,
- druga partia w `FALLBACK_ONLY` uzywa nauczyciela wspolnego jako glownego zrodla wyniku.

Czyli:
- pipeline obserwacji jest wspolny,
- ale warstwa decyzyjna pierwszej fali jest bogatsza i bardziej spersonalizowana.

## Wzorzec odblokowania nauki

To juz zadzialalo i trzeba to zachowac:
- poprawny profil MT5 i poprawne zaladowanie ekspertow,
- aktywny tryb papierowy,
- swiezy plik diagnostyczny w `Common Files\\MAKRO_I_MIKRO_BOT\\run`,
- obejscie miekkich odrzucen,
- obejscie zbyt twardych cost gate,
- obejscie zamrozenia rodzin/floty tylko w paper-learning,
- supervisor patrzy nie tylko na swieze pliki, ale na swieze lekcje i wiedze.

## Co supervisor ma pilnowac

Dla pierwszej fali:
- `EXECUTION_TRUTH_CLOSE`
- `LESSON_WRITE`
- `KNOWLEDGE_WRITE`

Dla drugiej partii:
- swiezy `decision_events.csv`
- swiezy `onnx_observations.csv`
- swiezy `student_gate_latest.json`
- swiezy `learning_observations_v2.csv`
- swiezy `broker_net_ledger_runtime.csv`

Alarm ma sie zapalic, gdy symbol:
- przestaje dawac runtime nauczyciela,
- przestaje dawac swieze lekcje,
- albo stoi obserwacyjnie bez domkniecia nauki.
