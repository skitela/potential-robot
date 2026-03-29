# 104_RIGOROUS_AUDIT_17_MICROBOTS_V1

Data: 2026-03-16

## Sekcja 0 - Jakosc materialu wejsciowego

### Ocena ogolna

Stan danych jest wystarczajacy do mocnych wnioskow architektonicznych, ale nie dla wszystkich 17 instrumentow w takim samym stopniu.

Mocne zrodla:
- `execution_summary.json`
- `broker_profile.json`
- `runtime_state.csv`
- `paper_position.csv`
- `learning_bucket_summary_v1.csv`
- `tuning_reasoning.csv`
- `tuning_experiments.csv`
- `tuning_deckhand.csv`
- `candidate_arbiter_state.csv`

Mocne wnioski mozna opierac przede wszystkim na:
- `EURUSD`
- `AUDUSD`
- `USDJPY`
- `USDCAD`
- `USDCHF`
- `EURAUD`
- `DE30`
- `US500`
- `GOLD`
- `SILVER`
- `COPPER-US`

Wnioski warunkowe:
- `GBPUSD`
- `NZDUSD`
- `EURJPY`
- `GBPJPY`

Powod:
- albo probka byla historycznie zbyt mala,
- albo material byl dlugo zablokowany przez slaba konwersje paper,
- albo centralne artefakty sesyjne nie sa wystarczajaco swieze, by traktowac je jako jedyne zrodlo prawdy.

### Najwazniejsze problemy jakosci danych

1. `session_capital_coordinator.csv` jest artefaktem nieaktualnym wzgledem zywego runtime symboli i grup.
2. `runtime_control.csv` dla domen nie zawsze odpowiada biezacemu zachowaniu symboli.
3. Dla czesci symboli historycznie kandydaci nie konwertowaly sie na zamkniete lekcje paper.
4. W metalach i crossach wysoki koszt transakcyjny bywa tak duzy, ze paper moze byc slabo reprezentatywny dla przyszlego live scalpingu.

### Statusy dowodowe per instrument

| Instrument | Status materialu | Glowny problem |
|---|---|---|
| EURUSD | WYSTARCZAJACY | ujemny profil `SETUP_TREND/BREAKOUT` mimo duzej probki |
| AUDUSD | WYSTARCZAJACY | jedna strona kierunkowa i slabe breakouty |
| GBPUSD | WARUNKOWY | historycznie `PAPER_CONVERSION_BLOCKED`, dopiero swiezo odetkany |
| USDJPY | WYSTARCZAJACY | przewaga kandydatow kupna, ujemny profil breakout/trend |
| USDCAD | WYSTARCZAJACY | zly trend/breakout i wysokie szpilki latencji |
| USDCHF | WARUNKOWO_WYSTARCZAJACY | breakouty slabe, konwersja paper poprawiona dopiero niedawno |
| NZDUSD | PROBKA_ZA_MALA | prawie brak swiezych kandydatow |
| EURJPY | WARUNKOWY | historycznie `OBSERVATIONS_MISSING`, teraz probka rosnie ale slabo |
| GBPJPY | PROBKA_ZA_MALA | spread `BAD`, bardzo malo lekcji |
| EURAUD | WYSTARCZAJACY_WARUNKOWO | range ruszyl dopiero po odetkaniu heat/risk bypass |
| GOLD | WYSTARCZAJACY_WARUNKOWO | probka juz rosnie, ale koszt i breakout noise nadal wysokie |
| SILVER | WYSTARCZAJACY_WARUNKOWO | rosnie probka, ale koszt i chaos mocno psuja wynik |
| COPPER-US | DANE_SLABO_REPREZENTATYWNE | spread tak wysoki, ze paper traci reprezentatywnosc |
| DE30 | WYSTARCZAJACY | aktywny, ale breakouty sa trwale stratne |
| US500 | WYSTARCZAJACY | najlepsza operacyjnosc, ale nadal lekko ujemna alfa po kosztach |

### Wnioski silne vs warunkowe

Wnioski silne:
- infrastruktura terminal-serwer jest obecnie stabilna,
- najwiekszy problem systemu nie lezy teraz w pingu ani polaczeniu,
- glownym problemem jest lokalna jakosc setupow i jakosc konwersji kandydat -> lekcja paper,
- centralne artefakty sesyjne sa mniej wiarygodne niz artefakty lokalne i grupowe.

Wnioski warunkowe:
- dokladna ocena warstwy centralnej musi byc oparta bardziej na grupowych arbiterach i runtime symboli niz na starym pliku koordynatora,
- dla `GBPUSD`, `USDCHF`, `EURAUD` i czesci metali trzeba jeszcze poczekac na dojrzalsza probe po ostatnich poprawkach.

## Sekcja 1 - Stan architektury

System sklada sie z:
- 17 mikrobotow, po 1 na instrument,
- 17 lokalnych agentow strojenia,
- 17 lokalnych deckhandow oceniachacych czystosc przedpola,
- warstwy rodzinnej,
- warstwy domenowej,
- globalnego koordynatora sesji i kapitalu,
- grupowego arbitra kandydatow,
- centralnego `portfolio heat`,
- warstwy broker/MT5/infrastruktura.

Model wykonawczy:
- sygnal rodzi sie lokalnie w mikrobocie,
- lokalny agent strojenia modyfikuje lokalna polityke instrumentu,
- deckhand decyduje, czy material jest czysty i czy w ogole wolno stroic,
- arbiter grupowy wybiera maksymalnie 1 kandydata na aktywna rodzine,
- centralny risk i `portfolio heat` moga odroczyc lub zablokowac wejscie,
- MT5 i broker dostarczaja stan feedu, spreadu, praw handlowych i pingu.

Stan dojrzalosci architektury:
- lokalna architektura strojenia jest juz dojrzala,
- agent ma pamiec rozumowania, eksperymentu, rollbacku i blokady powrotu,
- deckhand umie odroznic `LOW_SAMPLE`, `OBSERVATIONS_MISSING`, `PAPER_CONVERSION_BLOCKED`, `FOREFIELD_DIRTY`, `INFRASTRUCTURE_WEAK`,
- warstwa centralna jest funkcjonalna, ale nie wszystkie jej artefakty persystencji sa obecnie wystarczajaco swieze.

Najwazniejszy rozjazd architektoniczny:
- lokalne symbole i grupowe arbitery zyja,
- ale globalny plik koordynatora sesji nie wyglada na aktualny source of truth,
- przez to analiza centralna musi byc oparta na krzyzowym potwierdzeniu z kilku zrodel.

## Sekcja 2 - Parametry krytyczne

### Warstwa lokalna mikrobota

Krytyczne:
- `max_spread_threshold`
- `spread_regime`
- `market_regime`
- `execution_regime`
- `entry_threshold`
- `time_stop`
- `cooldown`
- `volatility_normalized_tp_multiplier`
- `volatility_normalized_sl_multiplier`
- `confidence_bucket`
- `confidence_score`
- `risk_multiplier`
- `breakout_filter_candle`
- `breakout_filter_renko`
- `trend_filter_candle`
- `range_filter_candle`
- `range_filter_renko`
- `rejection_support_filter`
- `auxiliary_intelligence_filter`
- `setup_type`
- `entry_timing_quality`
- `exit_timing_quality`
- `hold_time_efficiency`
- `MFE`
- `MAE`

### Warstwa agenta strojenia

Krytyczne:
- `confidence_cap`
- `risk_cap`
- `breakout_guard_tax`
- `breakout_conflict_tax`
- `breakout_renko_tax`
- `trend_body_tax`
- `trend_candle_tax`
- `range_chaos_tax`
- `range_trend_tax`
- `range_floor_confidence`
- `index_open_tax`
- `index_near_close_tax`
- `rejection_support_tax`
- `experiment_active`
- `experiment_revision`
- `experiment_status`
- `avoid_repeat_until`
- `last_failed_action_code`
- `last_focus_setup_type`
- `last_focus_market_regime`
- `reason_streak`
- `action_streak`
- `blocked_cycles`
- `trusted_cycles`

### Warstwa deckhanda

Krytyczne:
- `observations_total`
- `bucket_count`
- `paper_open_total`
- `risk_block_total`
- `score_gate_total`
- `dirty_total`
- `trust_reason`
- `conversion_ratio`
- `forefield_cleanliness`
- `infrastructure_ok`

### Warstwa centralna

Krytyczne:
- `family_max_new_entries_per_cycle`
- `domain_max_new_entries_per_cycle`
- `global_max_new_entries_per_cycle`
- `symbol_max_open_positions`
- `portfolio_heat_same_family_weight`
- `portfolio_heat_cross_family_weight`
- `global_risk_budget`
- `daily_hard_stop`
- `parallel_exposure_cap_usd_factor`
- `group_selection_mode`
- `near_tie_priority_gap_pct`
- `true_tie_mode_paper`
- `true_tie_mode_live`

### Warstwa infrastrukturalna

Krytyczne:
- `terminal_connected`
- `terminal_ping_ms`
- `tick_age_ms`
- `order_send_ms_avg`
- `order_send_ms_max`
- `execution_retry_avg`
- `execution_slippage_points_avg`
- `execution_slippage_points_max`
- `price_requests_sec`
- `price_requests_min`
- `order_requests_sec`
- `order_requests_min`

## Sekcja 3 - Co dostrajac, a czego nie ruszac

### Dynamiczne online

Dostrajac online:
- `confidence_cap`
- `risk_cap`
- `entry_threshold`
- `time_stop`
- `cooldown`
- `session_specific_acceptance`
- `breakout/trend/range/rejection` filtry
- male podatki kosztowe i konfliktowe
- `volatility_normalized_tp/sl` w waskim zakresie

Warunek:
- tylko przy czystym materiale,
- tylko przy sensownej konwersji paper,
- tylko bez problemu infrastrukturalnego,
- tylko bez aktywnej blokady `avoid_repeat`.

### Batchowe offline

Przeniesc do batch/offline:
- genotyp instrumentu,
- definicje najlepszych i najgorszych okien,
- wagi scoringu,
- progi klasyfikacji rezhimow,
- progi regret,
- progi deckhand trust,
- progi reprezentatywnosci paper,
- wagi `portfolio heat`,
- reguly korelacji ekspozycji.

### Hard-limity nieruszalne

Nie ruszac online:
- `daily hard stop`
- `broker/request caps`
- `max positions`
- `central kill-switch`
- `compliance constraints`
- maksymalna ekspozycja na wspolny czynnik USD
- twarde blokady po `TERMINAL_DISCONNECTED`
- twarde blokady po ekstremalnie wysokim pingu

### Parametry, ktorych nie wolno jeszcze ruszac

Na dzis nie ruszac bez dodatkowej proby:
- `NZDUSD` - za mala probka
- `GBPJPY` - za mala probka i zly koszt
- `COPPER-US` - koszt ekstremalny, paper slabo reprezentatywny
- `global priority_formula` - brak dowodu, ze obecnie to ona jest glownym waskim gardlem

## Sekcja 4 - Logika uczenia agenta

### Trade won

Agent powinien:
- sprawdzic, czy wygrana byla czysta kosztowo i wykonawczo,
- przypisac wynik do `setup_type + market_regime + session_tag`,
- jezeli zysk netto po kosztach utrzymuje sie na dodatnim poziomie i nie rosnie regret, utrzymac lub lekko wzmocnic aktywna polityke,
- krok pojedynczy: `0.02-0.04` na cap/tax lub wlaczenie jednego filtra binarnego.

### Trade lost

Agent powinien rozroznic:
- strata zlego sygnalu,
- strata zlego kosztu,
- strata zlej egzekucji,
- strata zlego timingu,
- strata przez portfelowe ciepło,
- strata przez faze rynku.

Dopiero po tym moze:
- przyciac konkretna klase setupu,
- podniesc wymagania dla swiecy lub Renko,
- skracac `time_stop`,
- obnizac `risk_cap`,
- uruchomic eksperyment alternatywny.

### Skipped profitable

Warunek:
- co najmniej 4-6 pominietych dobrych sygnalow w tym samym `setup/regime/session`,
- bez zlego spreadu,
- bez slabej egzekucji,
- bez blokady centralnej, ktora sama uzasadnia skip.

Wtedy:
- poluzowac tylko 1 parametr naraz,
- nie poluzowac jednoczesnie filtra i ryzyka.

### Skipped unprofitable

Interpretacja:
- to moze byc sukces filtra, nie problem.

Dzialanie:
- utrzymac lub delikatnie wzmacniac biezace sito,
- nie traktowac skipa jako straty okazji, jesli counterfactual pokazuje strate netto.

### Degraded execution

Jesli:
- rosnacy slippage,
- retry,
- ping,
- stale tick age,
- rate-limit,

to:
- nie stroic strategii,
- zapisac osobny tag wykonania,
- oznaczyc epizod jako `execution-caused`,
- zamrozic eksperymenty online dla tego instrumentu do czasu powrotu do normalnosci.

### Regime shift

Regime shift uznac, gdy zachodza co najmniej 2 z 5:
- zmiana `spread_regime`,
- zmiana dominujacego `setup/regime` bucketu,
- zmiana znaku `avg_pnl` dominujacego bucketu,
- spadek `hold-time efficiency` o >= 20%,
- wzrost `false breakout` lub `MAE` o >= 20%.

### PAPER_CONVERSION_BLOCKED

Agent nie powinien najpierw stroic strategii.
Najpierw ma sprawdzic:
- `risk contract block`,
- `portfolio heat`,
- `min lot floor`,
- `broker price rate limit`,
- `candidate arbitration`.

Dopiero jesli konwersja ruszy i pojawia sie zamkniete lekcje, wolno wracac do strojenia alfa.

### FOREFIELD_DIRTY

Przy `FOREFIELD_DIRTY`:
- zatrzymac zmiany online,
- prowadzic obserwacje,
- zostawic material do offline,
- nie dopisywac agresywnych wnioskow do genotypu.

### INFRASTRUCTURE_WEAK

Przy `INFRASTRUCTURE_WEAK`:
- zamrozic eksperymenty,
- nie przypisywac winy strategii,
- trzymac tylko telemetrie i kontrfakty.

### Minimalne progi zmian

Rekomendowane progi:
- FX_MAIN, FX_ASIA: min `12` zamknietych lekcji dla zmiany kierunkowej
- FX_CROSS: min `16`
- INDEX_EU, INDEX_US: min `14`
- METALS_SPOT_PM, METALS_FUTURES: min `18`

Progi dla eksperymentu:
- `START` dopiero przy czystym przedpolu,
- `REVIEW_PENDING` po minimum `3` nowych lekcjach lub `2` nowych `paper_open`,
- `ACCEPT` po dodatnim delta-pnl i przewadze wygranych,
- `ROLLBACK` po ujemnym delta-pnl i wzroscie strat bez rekompensaty w wygranych.

## Sekcja 5 - Plan gromadzenia danych

### Minimalny zestaw logow

- `candidate_signals.csv`
- `decision_events.csv`
- `learning_observations_v2.csv`
- `learning_bucket_summary_v1.csv`
- `tuning_actions.csv`
- `tuning_deckhand.csv`
- `execution_summary.json`
- `broker_profile.json`
- `runtime_state.csv`
- `paper_position.csv`

### Rozszerzony zestaw logow

- `tuning_reasoning.csv`
- `tuning_experiments.csv`
- `informational_policy.json`
- `incident_journal.jsonl`
- `candidate_arbiter_state.csv`
- telemetryka `portfolio heat`
- telemetryka centralnego koordynatora z gwarancja swiezosci

### Czestotliwosc oceny

- lokalna telemetria: na kazdym cyklu runtime
- review deckhanda: co `1-5` minut lub po istotnym przyroscie obserwacji
- review eksperymentu: po kazdych `3-6` nowych lekcjach
- review rodziny: co `15` minut i na granicach sesji
- review centralny: co `30-60` minut i na granicach domen

### Minimalna liczba zdarzen do sensownej zmiany

- filtr binarny: min `12-18` zamknietych lekcji zalezne od rodziny
- cap/tax: min `8-12`
- batch/genotyp: min `40-80` zamknietych lekcji per dominujacy setup/regime

### Zasady wersjonowania ustawien

Kazda zmiana powinna miec:
- `revision`
- `base_revision`
- `effective_at`
- `action_code`
- `focus_setup`
- `focus_regime`
- `trust_reason_before`
- `trust_reason_after`
- `experiment_id`

### Wygaszanie i archiwizacja

- logi hot-path: rotacja dzienna
- bucket summary i eksperymenty: archiwizacja tygodniowa
- snapshot polityki stabilnej: po kazdym `ACCEPT` i `ROLLBACK`
- retention z hot-path ograniczac przez agregacje, nie przez trzymanie kazdego szczegolu bez konca

## Sekcja 6 - Rekomendacje modyfikacji systemu

### 10 zmian o najwiekszym efekcie

1. Uczynic `conversion_ratio` twardym warunkiem trust dla agenta.
2. Dolozyc `paper_not_representative` dla instrumentow z kosztem ekstremalnym.
3. Oznaczac centralne artefakty jako `stale` i nie pozwalac, by byly jedynym source of truth.
4. Rozdzielic w eksperymencie porazke sygnalu od porazki kosztu i od porazki egzekucji.
5. Wprowadzic per-instrument `cost envelope` dla spread + slippage + time-stop.
6. Ograniczyc paper `portfolio heat` trybem edukacyjnym tam, gdzie dusi uczenie bardziej niz chroni.
7. Dodac automatyczne przesuniecie fokusu agenta, gdy nowy setup zaczyna przewyzszac stary bucket.
8. Zaostrzyc strojenie crossow i metali przez wyzsze minimalne proby.
9. Dodac centralny limit ekspozycji na wspolny czynnik USD.
10. Dolozyc prosty znacznik swiezosci dla koordynatora sesji i domen.

### 10 parametrow o najwyzszym wplywie

1. `max_spread_threshold`
2. `confidence_cap`
3. `risk_cap`
4. `time_stop`
5. `breakout_filter_candle`
6. `breakout_filter_renko`
7. `range_floor_confidence`
8. `rejection_support_filter`
9. `portfolio_heat_cross_family_weight`
10. `session_specific_acceptance`

### 10 bledow najczesciej psujacych wynik

1. Strojenie na `PAPER_CONVERSION_BLOCKED`
2. Strojenie na `FOREFIELD_DIRTY`
3. Mylenie kosztu z jakoscia sygnalu
4. Mylenie egzekucji z jakoscia sygnalu
5. Powrot do swiezo obalonej sciezki
6. Traktowanie duzej liczby kandydatow jako dowodu przewagi
7. Uzywanie tego samego sita dla roznych genotypow
8. Brak rozdzialu paper-education vs live-hard-limits
9. Ignorowanie przejsciowych faz sesji
10. Ignorowanie lokalnej poprawy vs globalnej szkody

### 5 zmian zrobic najpierw

1. `conversion_ratio` jako warunek trust
2. znacznik `paper_not_representative`
3. swiezosc centralnego koordynatora
4. osobny tag `execution-caused` w eksperymencie
5. centralny limit ekspozycji USD i odroczenie rownoleglych wejsc

### 5 zmian nie robic jeszcze teraz

1. nie podmieniac globalnie `priority_formula`
2. nie luzowac hurtowo filtrow dla wszystkich FX
3. nie rozszerzac agresywnie bypassow paper na live
4. nie stroic `NZDUSD` i `GBPJPY` bez nowej proby
5. nie traktowac metali futures jako gotowych do live scalpingu

## Sekcja 7 - Output wdrozeniowy

### A. JSON schema wynikow analizy per instrument

```json
{
  "type": "object",
  "required": [
    "symbol",
    "family",
    "genotype",
    "data_quality",
    "runtime_snapshot",
    "learning_snapshot",
    "cost_profile",
    "agent_state",
    "deckhand_state",
    "recommendations"
  ],
  "properties": {
    "symbol": { "type": "string" },
    "family": { "type": "string" },
    "genotype": {
      "type": "object",
      "properties": {
        "preferred_windows": { "type": "array" },
        "worst_windows": { "type": "array" },
        "spread_behavior": { "type": "string" },
        "volatility_profile": { "type": "string" },
        "false_breakout_tendency": { "type": "string" }
      }
    },
    "data_quality": {
      "type": "object",
      "properties": {
        "status": { "type": "string" },
        "sample_size": { "type": "integer" },
        "paper_conversion_status": { "type": "string" },
        "representative_for_live": { "type": "boolean" }
      }
    },
    "runtime_snapshot": {
      "type": "object",
      "properties": {
        "runtime_mode": { "type": "string" },
        "market_regime": { "type": "string" },
        "spread_regime": { "type": "string" },
        "execution_regime": { "type": "string" },
        "terminal_connected": { "type": "boolean" },
        "terminal_ping_ms": { "type": "number" }
      }
    },
    "learning_snapshot": {
      "type": "object",
      "properties": {
        "samples": { "type": "integer" },
        "wins": { "type": "integer" },
        "losses": { "type": "integer" },
        "pnl_day": { "type": "number" },
        "top_bucket_setup": { "type": "string" },
        "top_bucket_regime": { "type": "string" }
      }
    },
    "agent_state": { "type": "object" },
    "deckhand_state": { "type": "object" },
    "recommendations": { "type": "array" }
  }
}
```

### B. JSON schema zmian proponowanych przez tuning agenta

```json
{
  "type": "object",
  "required": [
    "symbol",
    "revision",
    "action_code",
    "focus_setup",
    "focus_regime",
    "change_set",
    "reason_code",
    "evidence_window",
    "rollback_rule"
  ],
  "properties": {
    "symbol": { "type": "string" },
    "revision": { "type": "integer" },
    "action_code": { "type": "string" },
    "focus_setup": { "type": "string" },
    "focus_regime": { "type": "string" },
    "change_set": { "type": "object" },
    "reason_code": { "type": "string" },
    "evidence_window": { "type": "object" },
    "rollback_rule": { "type": "object" }
  }
}
```

### C. JSON schema oceny deckhanda

```json
{
  "type": "object",
  "required": [
    "symbol",
    "trust_reason",
    "observations_total",
    "bucket_count",
    "paper_open_total",
    "risk_blocks_total",
    "dirty_total",
    "conversion_ratio",
    "forefield_clean"
  ],
  "properties": {
    "symbol": { "type": "string" },
    "trust_reason": { "type": "string" },
    "observations_total": { "type": "integer" },
    "bucket_count": { "type": "integer" },
    "paper_open_total": { "type": "integer" },
    "risk_blocks_total": { "type": "integer" },
    "dirty_total": { "type": "integer" },
    "conversion_ratio": { "type": "number" },
    "forefield_clean": { "type": "boolean" },
    "infrastructure_ok": { "type": "boolean" }
  }
}
```

### D. MQL5 struct dla konfiguracji mikrobota

```cpp
struct MbMicrobotConfig
{
   string symbol;
   string family;
   double max_spread_points;
   double entry_threshold;
   double tp_vol_mult;
   double sl_vol_mult;
   int    time_stop_sec;
   int    cooldown_sec;
   bool   allow_breakout;
   bool   allow_trend;
   bool   allow_range;
   bool   allow_rejection;
};
```

### E. MQL5 struct dla konfiguracji tuning agenta

```cpp
struct MbTuningAgentConfig
{
   double confidence_cap;
   double risk_cap;
   double breakout_guard_tax;
   double breakout_conflict_tax;
   double breakout_renko_tax;
   double trend_body_tax;
   double trend_candle_tax;
   double range_chaos_tax;
   double range_trend_tax;
   double range_floor_confidence;
   double rejection_support_tax;
   bool   breakout_candle_filter;
   bool   breakout_renko_filter;
   bool   trend_candle_filter;
   bool   range_candle_filter;
   bool   range_renko_filter;
};
```

### F. MQL5 struct dla deckhanda

```cpp
struct MbDeckhandConfig
{
   int    min_observations;
   int    min_bucket_count;
   int    min_paper_open;
   double min_conversion_ratio;
   int    max_dirty_events;
   int    max_risk_block_ratio_pct;
   bool   freeze_on_infrastructure_weak;
   bool   freeze_on_forefield_dirty;
};
```

### G. MQL5 struct dla warstwy centralnej risk/compliance

```cpp
struct MbCentralRiskConfig
{
   int    symbol_max_open_positions;
   int    family_max_new_entries_per_cycle;
   int    domain_max_new_entries_per_cycle;
   int    global_max_new_entries_per_cycle;
   double portfolio_heat_same_family_weight;
   double portfolio_heat_cross_family_weight;
   double usd_factor_exposure_cap;
   double daily_hard_stop_pct;
   bool   kill_switch_enabled;
};
```

## Sekcja 8 - Macierz priorytetu

| Kolejnosc | Rekomendacja | Oczekiwany efekt | Sila dowodu | Ryzyko architektoniczne | Wplyw na latencje | Wplyw na retencje | Trudnosc wdrozenia | Trudnosc rollbacku |
|---|---|---|---|---|---|---|---|---|
| 1 | `conversion_ratio` jako warunek trust | duzo lepsze odroznienie wiedzy od szumu | wysoka | niskie | niski | niski | srednia | niska |
| 2 | znacznik `paper_not_representative` | mniej falszywych wnioskow z metali futures | wysoka | niskie | niski | niski | srednia | niska |
| 3 | swiezosc koordynatora i domen | bardziej wiarygodna warstwa centralna | wysoka | srednie | niski | niski | srednia | niska |
| 4 | osobny tag `execution-caused` | mniej falszywego strojenia strategii | wysoka | niskie | niski | niski | srednia | niska |
| 5 | edukacyjny `portfolio heat` w paper | lepsza konwersja lekcji bez ruszania live | srednia | srednie | niski | niski | srednia | srednia |
| 6 | centralny limit ekspozycji USD | mniejsza szkoda globalna z lokalnych wejsc | srednia | srednie | niski | niski | srednia | srednia |
| 7 | focus-shift po zmianie bucket dominance | agent szybciej uczy sie nowych setupow | srednia | srednie | niski | sredni | srednia | srednia |
| 8 | ostrzejsze progi probki dla cross/metals | mniej overfittingu na drozszych rynkach | wysoka | niskie | brak | brak | niska | niska |
| 9 | batchowa rekalibracja genotypu | lepsze dopasowanie okien i kosztu | srednia | niskie | brak | sredni | srednia | niska |
| 10 | rewizja priority formula dopiero po innych naprawach | unikanie przedwczesnej przebudowy | srednia | wysokie jesli zrobic za wczesnie | sredni | niski | wysoka | wysoka |

## Plan wdrozenia zmian

Minimalny bezpieczny plan:
- `paper`: tylko obserwacja i walidacja artefaktow
- `shadow`: wlaczenie nowych klasyfikacji, bez wplywu na live gating
- `controlled canary`: 1-2 instrumenty o najlepszej probce i najlepszym koszcie
- `live`: dopiero po dodatnim wyniku netto po kosztach i stabilnosci w kilku rolling windows

## Reguly rollbacku

- rollback natychmiast, gdy pogarsza sie delta-pnl i rosną straty przy czystym materiale
- rollback natychmiast, gdy po zmianie spada conversion ratio
- rollback natychmiast, gdy zmiana zwieksza konflikt centralny lub ekspozycje na wspolny czynnik
- rollback natychmiast, gdy pogarsza sie latencja hot-path lub retencja runtime

## Reguly zatwierdzania zmian przez operatora

- kazda zmiana musi miec dowod w logach i revision trail
- kazda zmiana online musi miec zdefiniowany rollback
- batchowe zmiany genotypu tylko po review rolling window
- zmiany centralne dopiero po pokazaniu, ze lokalna poprawa nie szkodzi globalnie

## Sygaly ostrzegawcze, ze agent zaczal szkodzic

- agent bardzo aktywny, ale wynik netto nie poprawia sie
- rosnie liczba eksperymentow `START`, a nie ma `ACCEPT`
- rosnie liczba `paper_open`, ale nie rosnie liczba wartosciowych zamknietych lekcji
- rosnace `dirty_total` i jednoczesne strojenie
- ciagle powroty do bardzo podobnych sciezek po rollbacku

## Kiedy wstrzymac strojenie mimo pozornego bogactwa danych

- gdy kandydatow jest duzo, ale zamknietych lekcji prawie brak
- gdy duzy koszt czyni paper niereprezentatywnym
- gdy centralne artefakty sa stale lub sprzeczne z lokalnym runtime
- gdy problem jest infrastrukturalny, a nie strategiczny
- gdy portfelowe cieplo blokuje wiekszosc sensownych lekcji
