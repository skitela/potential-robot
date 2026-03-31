# Pamietnik Nauki I Nauczycieli 2026-03-31

Ten zapis utrwala dzisiejszy stan, zeby nie odtwarzac go pozniej z commitow, logow i domyslow.

## 1. Pierwsza fala z nauczycielami osobistymi

Symbole:
- `US500`
- `EURJPY`
- `AUDUSD`
- `USDCAD`

To, co realnie przywrocilo nauke:
- poszerzenie diagnostycznej sciezki miekich odrzucen,
- usuniecie ukrywania przypadkow `setup_type = NONE`,
- odblokowanie bootstrapu `LOW_SAMPLE` i `BUCKETS_EMPTY`,
- domkniecie paper chain:
  `PAPER_OPEN -> PAPER_CLOSE -> EXECUTION_TRUTH_CLOSE -> LESSON_WRITE -> KNOWLEDGE_WRITE`,
- dopisanie kontekstu pozycji probnej:
  `candidate_id`, `request_comment`,
- live close przeprowadzony na `V2`, z lepszym wynikiem ekonomicznym i jawnymi etapami w logu.

Jak podpinasz nauczyciela osobistego:
- symbol musi miec gotowy kontrakt runtime,
- lokalny model symbolu nie moze zostac w `FALLBACK_ONLY`,
- obserwacja idzie wspolnym torem ONNX, ale decyzja dostaje juz symbol-local wynik i student gate dla konkretnego instrumentu,
- supervisor nie moze patrzec tylko na swiezy plik; ma widziec swieze:
  `EXECUTION_TRUTH_CLOSE`, `LESSON_WRITE`, `KNOWLEDGE_WRITE`.

## 2. Druga partia z nauczycielem globalnym

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

Cel tej partii:
- utrzymac ciagla obserwacje na laptopie,
- domykac papierowe lekcje bez wymogu lokalnego modelu per symbol,
- korzystac z nauczyciela wspolnego, dopoki nie bedzie sensu schodzic do modeli lokalnych.

Jak podpinasz nauczyciela globalnego:
- `local_training_mode = FALLBACK_ONLY`,
- `InpEnableLiveEntries = false`,
- `InpPaperCollectMode = true`,
- wspolny plik diagnostyczny:
  `Common Files\\MAKRO_I_MIKRO_BOT\\run\\global_teacher_cohort_diagnostic.csv`,
- uruchomienie skupione przez:
  `RUN\\FOCUS_GLOBAL_TEACHER_COHORT_LEARNING.ps1`.

## 3. Czy globalny nauczyciel uczy na tych samych zmiennych

W duzej czesci tak.

Wspolne dla pierwszej fali i drugiej partii:
- ten sam rdzen obserwacji rynku,
- te same pola ONNX,
- ten sam kontekst spreadu, rezimu rynku, jakosci swiecy i renko,
- ten sam zapis obserwacji i ten sam most runtime.

Roznica:
- pierwsza fala moze korzystac z nauczyciela osobistego i lokalnego modelu symbolu,
- druga partia dzisiaj jedzie glownie na nauczycielu wspolnym i nie wymaga lokalnego modelu na starcie.

Czyli:
- jezyk obserwacji jest wspolny,
- warstwa decyzyjna pierwszej fali jest bardziej spersonalizowana,
- druga partia jest prostsza i bardziej zalezna od nauczyciela globalnego.

## 4. Co dzisiaj zostalo wdrozone dla drugiej partii

Wdrozone i zapisane w kodzie:
- diagnostyka globalnego nauczyciela w:
  `MQL5\\Include\\Core\\MbGlobalTeacherLearningDiagnostic.mqh`,
- launcher i przelacznik diagnostyczny:
  `RUN\\FOCUS_GLOBAL_TEACHER_COHORT_LEARNING.ps1`,
  `RUN\\SET_GLOBAL_TEACHER_COHORT_DIAGNOSTIC_MODE.ps1`,
- audyt tej partii:
  `RUN\\BUILD_GLOBAL_TEACHER_COHORT_ACTIVITY_AUDIT.ps1`,
- wellbeing i full stack widza juz druga partie i potrafia alarmowac, gdy przestaje dawac swieze lekcje.

Dodatkowe ruchy naprawcze z dzisiejszego wieczoru:
- ratowanie `family/fleet freeze` zostalo dopiete do global-teacher paper-learning,
- awaryjny `OnTimer -> OnTick` zostal dodany do dziewiatki,
- wiedza o tych wzorcach zostala zapisana w dokumentach, zeby nie zniknela.

## 5. Stan rzeczywisty na koniec tej tury

Na teraz naprawde ucza sie pod globalnym nauczycielem:
- `GOLD`
- `SILVER`

To sa swieze, udowodnione lekcje i wiedza w `Common Files`.

Na teraz pozostala siodemka:
- `DE30`
- `USDJPY`
- `USDCHF`
- `COPPER-US`
- `EURAUD`
- `EURUSD`
- `GBPUSD`

zyje obserwacyjnie i ma swieze dzienniki decyzji oraz ONNX, ale nie domyka jeszcze swiezych lekcji.

## 6. Najwazniejsza otwarta blokada dla siodemki

Ta siodemka:
- ma aktywny `paper_mode_active = 1`,
- dostaje ticki,
- zapisuje swieze `decision_events.csv`,
- zapisuje swieze `onnx_observations.csv`,
- ale nadal nie daje swiezych:
  `student_gate_latest.json`,
  `learning_observations_v2.csv`,
  `broker_net_ledger_runtime.csv`.

To znaczy:
- problem nie lezy juz w starcie MT5,
- problem nie lezy juz w samym wykresie ani w presetach,
- problem siedzi jeszcze przed stabilnym przejsciem do swiezych `SCAN -> PRECHECK -> PAPER_OPEN -> LESSON_WRITE`.

## 7. Co supervisor ma teraz robic

Supervisor uczenia ma badac wszystkie symbole z obu fal.

Dla pierwszej fali alarm:
- brak swiezego `EXECUTION_TRUTH_CLOSE`,
- brak swiezego `LESSON_WRITE`,
- brak swiezego `KNOWLEDGE_WRITE`.

Dla drugiej partii alarm:
- brak swiezych obserwacji nauczyciela,
- brak swiezej lekcji,
- brak swiezej wiedzy,
- brak swiezego stanu bramki lub dluga stagnacja bez przejscia z obserwacji do lekcji.

## 8. Najuczciwszy wniosek

Pierwsza fala ma juz odtworzony wzorzec:
- obserwacja,
- decyzja,
- otwarcie,
- zamkniecie,
- lekcja,
- wiedza.

Druga partia jest uruchomiona i juz nie jest martwa, ale jeszcze nie jest domknieta cala dziewiatka.

Na koniec tej tury:
- `2 z 9` ucza sie naprawde,
- `7 z 9` jest obserwacyjnie aktywne, ale nadal wymaga dalszego odblokowania wejscia do swiezej lekcji.
