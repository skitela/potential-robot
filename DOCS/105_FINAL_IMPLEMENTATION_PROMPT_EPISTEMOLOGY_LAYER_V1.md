# 105_FINAL_IMPLEMENTATION_PROMPT_EPISTEMOLOGY_LAYER_V1

Data: 2026-03-16

## Cel

Ten prompt sluzy do wdrozenia kolejnego etapu rozwoju systemu `MAKRO_I_MIKRO_BOT`:
- bez projektowania wszystkiego od zera,
- bez rozwalania hot-path,
- bez agresywnej przebudowy,
- jako zmiana delta oparta na istniejacej architekturze 17 mikrobotow, lokalnych tuning agentow, deckhandow, warstw rodzinnych, arbitrazu kandydatow, `portfolio heat` i warstwy centralnej.

## Prompt ostateczny

```text
Jestes architektem systemow MT5, audytorem quant oraz inzynierem runtime odpowiedzialnym za wdrozenie kolejnego etapu dojrzewania systemu `MAKRO_I_MIKRO_BOT`.

Nie projektujesz nowego systemu. Nie wolno Ci robic redesignu od zera. Masz wykonac zmiany delta w istniejacej architekturze 17 mikrobotow.

Kontekst twardy:
- system sklada sie z 17 mikrobotow,
- 1 mikrobot = 1 instrument,
- kazdy mikrobot ma wlasnego tuning agenta,
- kazdy tuning agent ma lokalnego deckhanda,
- system dziala obecnie w `paper/shadow`,
- istnieja juz:
  - `trust_reason`,
  - `reason_streak`,
  - `action_streak`,
  - `tuning_reasoning.csv`,
  - `tuning_experiments.csv`,
  - eksperyment `START / REVIEW_PENDING / ACCEPT / ROLLBACK`,
  - `avoid_repeat_until`,
  - `PAPER_CONVERSION_BLOCKED`,
  - `FOREFIELD_DIRTY`,
  - `INFRASTRUCTURE_WEAK`,
  - telemetryka `terminal_connected` i `terminal_ping_ms`,
  - warstwa centralna: candidate arbitration, portfolio heat, rodziny, domeny, koordynator.

Najwazniejszy cel tego etapu:
domknac epistemologie agenta strojenia, tak aby agent poprawnie ustalal przyczyne wyniku zanim ruszy parametr.

Nie wolno Ci:
- wdrazac ciezkich mechanizmow runtime bez uzasadnienia kosztu,
- dodawac szerokiej retencji do hot-path,
- stroic wszystkiego naraz,
- mieszac przyczyny lokalne, centralne, infrastrukturalne i kosztowe,
- usuwac istniejacej architektury eksperymentu, rollbacku i deckhanda,
- wprowadzac zmian live-only; to ma sluzyc najpierw paper/shadow.

Masz wdrozyc dokladnie 4 elementy, w tej kolejnosci:

1. jawne kontrakty stanow:
- `MbTrustState`
- `MbExecutionQualityState`
- `MbCostPressureState`

2. normalizacje przyczyny do modelu:
- `reason_domain`
- `reason_class`
- `reason_code`

3. domkniecie statusow kontraktowych, w tym:
- `CENTRAL_STATE_STALE`

4. wyciagniecie bounded adaptation z heurystyki do jawnego kontraktu parametrow.

## Wymagania funkcjonalne

### A. MbTrustState

Masz dodac lekki, jawny kontrakt stanu zaufania danych i przedpola.

Minimalny zakres `state`:
- `TRUSTED`
- `LOW_SAMPLE`
- `OBSERVATIONS_MISSING`
- `PAPER_CONVERSION_BLOCKED`
- `FOREFIELD_DIRTY`
- `INFRASTRUCTURE_WEAK`
- `CENTRAL_STATE_STALE`

Minimalne pola:
- `state`
- `reason_code`
- `conversion_ratio`
- `dirty_ratio`
- `blocked_ratio`
- `stale_seconds`
- `sample_count`
- `closed_lessons_count`

Minimalne zasady:
- jezeli `trust_state != TRUSTED`, agent nie wykonuje prawdziwego lokalnego tuning move,
- moze:
  - logowac,
  - przejsc do review,
  - zapisywac reasoning,
  - diagnozowac przyczyne,
  - ale nie powinien zmieniac lokalnej alfy.

### B. MbExecutionQualityState

Masz dodac jawny kontrakt oceny wykonania.

Zakres `state`:
- `GOOD`
- `CAUTION`
- `BAD`

Minimalne pola:
- `state`
- `reason_code`
- `ping_ms`
- `tick_age_ms`
- `slippage_proxy`
- `retry_proxy`
- `execution_pressure`

Minimalne kategorie powodow:
- `TICK_STALE`
- `RETRY_SPIKE`
- `SLIPPAGE_SPIKE`
- `PING_ELEVATED`
- `RATE_LIMIT_PRESSURE`
- `EXECUTION_PRESSURE_HIGH`

Zasada:
- jezeli `execution_quality == BAD`, agent nie obwinia setupu i nie stroi logiki sygnalu.

### C. MbCostPressureState

Masz dodac jawny kontrakt presji kosztowej.

Zakres `state`:
- `LOW`
- `MEDIUM`
- `HIGH`
- `NON_REPRESENTATIVE`

Minimalne pola:
- `state`
- `reason_code`
- `spread_now`
- `spread_vs_typical_move`
- `spread_vs_time_stop`
- `spread_vs_mfe`
- `spread_vs_mae`

Zasada:
- jezeli `cost_pressure == NON_REPRESENTATIVE`, agent nie stroi agresywnie lokalnej alfy,
- taka lekcja nie moze miec pelnej wagi,
- dla drogich instrumentow to moze wymuszac tryb obserwacyjny.

## Normalizacja przyczyny

Masz przejsc z pojedynczego, nieostrego `reason_code` na model:
- `reason_domain`
- `reason_class`
- `reason_code`

Dozwolone domeny:
- `SIGNAL`
- `EXECUTION`
- `COST`
- `DATA`
- `ARBITRATION`
- `CENTRAL`
- `INFRA`
- `RISK`
- `MODE`

Przyklady oczekiwanego formatu:
- `SIGNAL / QUALITY / BREAKOUT_POOR_CANDLE`
- `EXECUTION / DEGRADATION / RETRY_SPIKE`
- `COST / PRESSURE / SPREAD_TOO_WIDE`
- `DATA / TRUST / FOREFIELD_DIRTY`
- `ARBITRATION / GATE / FAMILY_TOP1_LOST`
- `CENTRAL / GATE / PORTFOLIO_HEAT_BLOCK`
- `INFRA / TERMINAL / DISCONNECTED`
- `RISK / CONTRACT / MIN_LOT_BLOCK`

Wymuszenie:
- nie usuwaj starego `reason_code`, jesli to za drogie architektonicznie,
- ale wprowadz obok jawne pola nowego modelu,
- zapewnij mapowanie kompatybilnosci wstecznej.

## Statusy kontraktowe

Masz domknac operacyjnie statusy:

### FOREFIELD_DIRTY

Status ma zapadac, gdy:
- udzial kandydatow niskiej pewnosci i slabej jakosci jest za wysoki,
albo
- kandydatow jest duzo, a bucketow i zamknietych lekcji malo,
albo
- material jest poznawczo niespojny.

### PAPER_CONVERSION_BLOCKED

Dodaj podtypy:
- `BY_RISK_CONTRACT`
- `BY_PORTFOLIO_HEAT`
- `BY_RATE_GUARD`
- `BY_MIN_LOT`
- `BY_RUNTIME_MODE`

Zasada:
- agent nie ma tego interpretowac jako porazki setupu.

### INFRASTRUCTURE_WEAK

Status ma wynikac z progow dla:
- pingu,
- tick age,
- retry,
- slippage proxy,
- execution pressure,
- terminal state.

### CENTRAL_STATE_STALE

Masz dodac nowy status.

Ma zapadac, gdy:
- artefakty centralne nie odswiezaja sie wystarczajaco swiezo wzgledem runtime symboli i arbitra grupowego.

Skutek:
- centralne wnioski maja wtedy status advisory,
- lokalny agent nie powinien traktowac warstwy centralnej jako pelnej prawdy.

## Bounded adaptation

Masz wyciagnac bounded adaptation z heurystyk zaszytych w logice do jawnego kontraktu.

Kazdy strojony parametr ma dostac definicje:
- `value_min`
- `value_max`
- `step_min`
- `step_max`
- `min_closed_lessons`
- `min_clean_reviews`
- `cooldown_after_change`
- `max_changes_per_window`
- `requires_trusted_state`
- `requires_execution_not_bad`
- `forbid_when_cost_non_representative`

Wymuszenie architektoniczne:
- najpierw kontrakt rodzinny,
- dopiero potem opcjonalny override per symbol,
- nie buduj od razu 17 calkowicie osobnych kontraktow, jesli rodzina wystarcza,
- override per symbol tylko tam, gdzie dowod jest mocny.

Po `ROLLBACK` blokada powrotu ma obejmowac:
- `action_code`
- `focus_setup`
- `focus_regime`
- `cause_class`

Nie tylko samo `action_code`.

## Twarda regula decyzyjna agenta

Masz wdrozyc jawna regule:

Agent moze wykonac prawdziwy lokalny tuning move tylko wtedy, gdy jednoczesnie:
- `trust_state == TRUSTED`
- `execution_quality != BAD`
- `cost_pressure != NON_REPRESENTATIVE`
- `reason_domain` wskazuje problem lokalnie strojony, a nie centralny, infrastrukturalny albo czysto kosztowy bez reprezentatywnej lekcji.

W przeciwnym razie:
- agent nie stroi lokalnej alfy,
- moze logowac review,
- moze dopisywac reasoning,
- moze zwiekszac liczniki przyczyn,
- ale nie zmienia parametrow strategii.

## Ograniczenia wydajnosciowe

Musisz pilnowac:
- brak ciezkich modeli runtime,
- brak szerokich obliczen na kazdym ticku,
- brak agresywnej retencji w hot-path,
- nowe kontrakty maja byc lekkie i oparte glownie na juz istniejacych artefaktach,
- tam gdzie to mozliwe:
  - licz online,
  - zapisuj zgrubnie,
  - agreguj poza hot-path.

## Material dowodowy

Pracuj na istniejacych artefaktach systemu, przede wszystkim:
- `candidate_signals.csv`
- `decision_events.csv`
- `learning_observations_v2.csv`
- `learning_bucket_summary_v1.csv`
- `tuning_actions.csv`
- `tuning_reasoning.csv`
- `tuning_experiments.csv`
- `tuning_deckhand.csv`
- `execution_summary.json`
- `broker_profile.json`
- `runtime_state.csv`
- `informational_policy.json`
- `paper_position.csv`

Nie wolno udawac danych, ktorych nie ma.

## Output

Masz dostarczyc:

1. Zmiany w typach / structach / enumach.
2. Zmiany w deckhandzie.
3. Zmiany w lokalnym agencie strojenia.
4. Minimalne zmiany w mikrobotach tylko tam, gdzie sa potrzebne do nowego modelu przyczyn.
5. Zmiany w logach i storage, ale lekkie.
6. Dokument architektoniczny opisujacy:
   - co zostalo dodane,
   - jak dziala,
   - jakie ma progi,
   - jaki jest koszt runtime,
   - jak wyglada rollback.
7. Evidence report pokazujacy:
   - czy kompilacja przeszla,
   - czy walidacje przeszly,
   - czy nowe pola sa zapisywane,
   - czy stary runtime nie zostal zepsuty.

## Wymuszenia koncowe

- Pisz technicznie, nie marketingowo.
- Nie przebudowuj calego systemu.
- Traktuj zmiany jako delta.
- Najpierw bezpieczenstwo epistemiczne, potem agresja.
- Jesli czegos nie da sie wdrozyc bez zbyt duzego kosztu hot-path, napisz to wprost i wybierz lzejsza alternatywe.
- Jezeli widzisz miejsce, gdzie rodzina powinna miec domyslny kontrakt, a symbol tylko override, wybierz to rozwiazanie.
- Nie wdrazaj kolejnych tuning move dla konkretnych symboli, dopoki ten pakiet nie bedzie gotowy.
```

## Intencja wdrozeniowa

Ten prompt ma sluzyc jako ostatnia, spieta instrukcja do wdrozenia:
- `trust_state`
- `execution_quality`
- `cost_pressure`
- nowego modelu przyczyn
- `CENTRAL_STATE_STALE`
- jawnego bounded adaptation

Najpierw epistemologia i ontologia przyczyny.
Dopiero potem dalsze strojenie konkretnych mikrobotow.
