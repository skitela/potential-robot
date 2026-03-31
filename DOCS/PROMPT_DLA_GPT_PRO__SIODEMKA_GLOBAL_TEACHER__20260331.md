# Prompt Dla GPT Pro - Siodemka Global Teacher 2026-03-31

Pracujemy nad druga partia instrumentow uczacych sie na laptopie pod nauczycielem globalnym. Chcemy, zebys przeanalizowal stan, wskazal brakujace ruchy i zaproponowal najlepszy plan dojscia do:

1. stabilnej nauki lokalnej dla calej dziewiatki,
2. zgodnosci warstwy globalnego nauczyciela z bogatszym wzorcem pierwszej czworki z nauczycielami osobistymi,
3. bezpiecznego przejscia na VPS najpierw w paper-learning, a dopiero potem do etapu live paper.

## Kontekst architektoniczny

Mamy dwa tory:

- pierwsza fala z nauczycielami osobistymi:
  `US500`, `EURJPY`, `AUDUSD`, `USDCAD`
- druga partia z nauczycielem globalnym:
  `DE30`, `GOLD`, `SILVER`, `USDJPY`, `USDCHF`, `COPPER-US`, `EURAUD`, `EURUSD`, `GBPUSD`

Pierwsza fala jest dla nas wzorcem. Tam nauka zostala juz odblokowana przez:
- poszerzenie diagnostyki miekich odrzucen,
- domkniecie lancucha `PAPER_OPEN -> PAPER_CLOSE -> EXECUTION_TRUTH_CLOSE -> LESSON_WRITE -> KNOWLEDGE_WRITE`,
- lepszy zapis kontekstu pozycji,
- dojscie do bogatszej warstwy per instrument.

Druga partia ma uczyc sie na nauczycielu globalnym, ale na tym samym rdzeniu obserwacji rynku co pierwsza fala. Chcemy, zeby globalny nauczyciel korzystal z tych samych typow cech, kontekstu rynku, spreadu, reżimu rynku, bucketow zaufania i warstwy ekonomicznej, a nie z ubogiego lub uproszczonego toru.

## Stan potwierdzony lokalnie

Na laptopie, w zwyklym paper-learning:
- `GOLD` i `SILVER` daja swieze pelne lekcje i wiedze,
- `DE30`, `USDJPY`, `USDCHF`, `COPPER-US`, `EURAUD`, `EURUSD`, `GBPUSD` zyja obserwacyjnie, ale nie domykaja swiezych lekcji.

Najswiezszy audyt:
- verdict: `GLOBAL_TEACHER_COHORT_CZESCIOWO_AKTYWNY`
- teacher_runtime_active_count: `2`
- fresh_full_lesson_count: `2`
- stalled symbols:
  `DE30`, `USDJPY`, `USDCHF`, `COPPER-US`, `EURAUD`, `EURUSD`, `GBPUSD`

Wazne: nie twierdzimy jeszcze, ze druga partia jest potwierdzona na VPS. To jest stan lokalny na laptopie. Chcemy od Ciebie uczciwej analizy jak doprowadzic te siedem do poziomu `GOLD` i `SILVER`, a potem jak bezpiecznie przeniesc to na VPS.

## Co widzimy jako glowny problem

Te siedem symboli ma zwykle:
- swiezy `decision_events.csv`,
- swiezy `onnx_observations.csv`,
- ale brak swiezego `student_gate_latest.json`,
- brak swiezego `learning_observations_v2.csv`,
- brak swiezego `broker_net_ledger_runtime.csv`.

To znaczy: tor obserwacyjny zyje, ale nie przechodzi stabilnie do bramki studenta, lekcji i wiedzy.

W niektorych logach, zwlaszcza dla `EURUSD`, dominujacy objaw to:
- `SCORE_BELOW_TRIGGER`

Mamy juz dorzucone:
- `TIMER_FALLBACK_SCAN`,
- diagnostyczne rozluznienia dla global teacher,
- rescue tuningowe w botach.

To poprawilo sytuacje, ale nie wystarczylo na `9/9`.

## Co jest zalaczone

W tej paczce dostajesz:
- kod diagnostyki globalnego nauczyciela,
- kod wspolnego pipeline obserwacji ONNX,
- most runtime ML,
- launcher drugiej partii,
- audyt aktywnosci drugiej partii,
- jeden bot dzialajacy pod globalnym nauczycielem,
- jeden bot zatrzymany pod globalnym nauczycielem,
- jeden bot z pierwszej fali jako wzorzec bogatszego toru.

## O co prosimy

Przeanalizuj te pliki i odpowiedz bardzo konkretnie:

1. Czy globalny nauczyciel juz teraz uczy na wystarczajaco podobnym zestawie cech do pierwszej czworki?
2. Jesli nie, jakie dokładnie cechy, warstwy ekonomiczne albo sygnaly wykonawcze trzeba jeszcze dopiac?
3. Dlaczego `GOLD` i `SILVER` przechodza do swiezych lekcji, a pozostala siodemka nie?
4. Jakie minimalne poprawki w kodzie zrobic teraz, zeby przejsc z `2/9` do `9/9` na laptopie?
5. Jakie alarmy i zasady nadzoru ma miec supervisor uczenia, zeby lapal stagnacje kazdego symbolu najpozniej po 30 minutach?
6. Jak bezpiecznie przejsc na VPS:
   - etap paper-learning,
   - etap canary,
   - etap live paper?
7. Czy warto od razu schodzic dla czesci tej siodemki do nauczycieli osobistych per instrument, czy najpierw doprowadzic cala dziewiatke do stabilnej nauki na nauczycielu globalnym?

## Oczekiwany wynik od Ciebie

Chcemy od Ciebie:
- diagnoze przyczyny,
- kolejnosc wdrozenia,
- liste konkretnych poprawek w plikach,
- plan walidacji po kazdym kroku,
- plan przejscia na VPS bez utraty ciaglosci nauki.

Prosba: nie zakladaj sukcesu na VPS, jesli material go nie dowodzi. Rozdziel prosze:
- stan potwierdzony lokalnie,
- stan gotowosci do VPS,
- stan gotowosci do live paper.
