# SafetyBot - mapa sterowania i granice uczenia

## Rola

`SafetyBot` jest właścicielem decyzji wykonawczej. To on:

- wybiera kandydatów do skanowania,
- przepuszcza albo odrzuca wejście,
- pilnuje kosztu wejścia, ryzyka i stanu infrastruktury,
- przygotowuje zlecenie,
- zapisuje ślad decyzji i wyniku.

Warstwa ucząca:

- nie zastępuje `SafetyBot`,
- nie przejmuje wykonania,
- nie dostaje prawa samodzielnego otwierania transakcji,
- jedynie koryguje miękkie progi i priorytety w `paper/shadow`.

To jest zasada nadrzędna:

- `SafetyBot` = dowódca wykonania,
- nauka = doradca i pamięć statystyczna.

## Warstwy umysłu SafetyBot

### 1. Orkiestracja rynku

Na wejściu `SafetyBot` ustala:

- aktywne okno czasowe,
- aktywną grupę instrumentów,
- limity liczby symboli na przebieg,
- rotację koszyków,
- zawężenie symboli do bieżącego okna.

To jest warstwa porządkowania ruchu, nie warstwa sygnału.

### 2. Ochrona globalna

Zanim dojdzie do typowania, `SafetyBot` sprawdza:

- stan mostu i odpowiedzi środowiska,
- stan snapshotów rynku,
- ochronę przed czarnym łabędziem,
- samoleczenie po złej serii,
- tryb próbny,
- ograniczenia sesyjne i piątkowe,
- ostrzeżenia z degradacji środowiska.

Ta warstwa ma prawo zatrzymać albo ograniczyć handel.

### 3. Ranking kandydatów

Po odfiltrowaniu świata `SafetyBot` buduje ranking:

- `time_weight`,
- `score_factor`,
- `group_factor`,
- ewentualny bonus za już otwartą pozycję,
- miękki bonus lub kara z warstwy uczącej w `paper/shadow`.

To jest miejsce, w którym nauka może pomagać, ale nie może łamać zasad bezpieczeństwa.

### 4. Ocena pojedynczego symbolu

Dla każdego kandydata `SafetyBot` liczy:

- logikę kierunku,
- jakość układu,
- rodzinę strategii,
- ocenę z warstwy świec,
- ocenę z warstwy Renko,
- lekką korektę z nauki,
- minimalny wymagany wynik punktowy.

To jest właściwe serce wejścia.

### 5. Ryzyko i przygotowanie zlecenia

Po przejściu punktacji `SafetyBot` jeszcze raz sprawdza:

- dzienną ochronę kapitału,
- procent ryzyka,
- wielkość pozycji,
- ciepło portfela,
- zgodność z ograniczeniami grupy,
- zgodność z ograniczeniami brokera.

Dopiero potem przygotowuje zlecenie.

### 6. Zapis pamięci i sprzężenie zwrotne

Po decyzji i po wyniku `SafetyBot` zapisuje:

- pełny kontekst decyzji,
- odrzucenia i ich przyczyny,
- punktację wejścia,
- rodzinę strategii,
- okno i grupę,
- wynik netto po zamknięciu.

To jest materiał dla laboratorium i warstwy uczącej.

## Cztery klasy parametrów

### 1. Nienaruszalne - kapitał i bezpieczeństwo

To są parametry, których nie wolno oddać automatycznej nauce:

- `risk_per_trade_max_pct`
- `risk_scalp_pct`
- `risk_scalp_min_pct`
- `risk_scalp_max_pct`
- `risk_swing_pct`
- `risk_swing_min_pct`
- `risk_swing_max_pct`
- `max_open_risk_pct`
- `friday_risk_*`
- `black_swan_*`
- `kill_switch_*`
- `manual_kill_switch_file`

Powód:

- one chronią kapitał i zdolność przetrwania systemu.

### 2. Adaptacyjne runtime

To są parametry, które `SafetyBot` już dziś wykorzystuje do reagowania na stan rynku i wykonania:

- `self_heal_*`
- `canary_*`
- `drift_*`
- `learner_qa_*`
- `unified_learning_runtime_*`
- `unified_learning_rank_*`
- `eco_probe_*`
- część ostrzeżeń degradacyjnych.

Powód:

- to nie są stałe parametry strategii,
- to są parametry zachowania ochronnego i ostrożnościowego.

### 3. Miękkie progi do uczenia

To są najlepsze kandydaty do dalszej samoregulacji:

- `fx_signal_score_threshold`
- `fx_signal_score_hot_relaxed_threshold`
- `fx_spread_cap_points_default`
- `metal_signal_score_threshold`
- `metal_signal_score_hot_relaxed_threshold`
- `metal_spread_cap_points_default`
- `crypto_signal_score_threshold`
- `crypto_signal_score_hot_relaxed_threshold`

Powód:

- to są progi dopuszczenia,
- nie otwierają handlu samodzielnie,
- mogą być ostrożnie dociskane albo luzowane przez naukę.

### 4. Parametry logiki sygnału

To jest warstwa bardziej wrażliwa i wymaga osobnego audytu przed automatycznym uczeniem:

- `sma_fast`
- `sma_trend`
- `adx_period`
- `adx_threshold`
- `adx_range_max`
- `regime_switch_enabled`
- `mean_reversion_enabled`
- `structure_filter_enabled`
- parametry Renko,
- parametry świec,
- część ustawień trendu i struktury.

Powód:

- one wpływają już na sam kształt strategii,
- ich automatyczne ruszanie bez ścisłego audytu może wywołać dryf logiki.

## Co powinno się uczyć pierwsze

Najpierw powinny uczyć się:

- priorytety `instrument + okno`,
- priorytety `instrument + okno + rodzina strategii`,
- miękkie progi punktacji,
- miękkie progi spreadu,
- miękkie progi opóźnienia paper/shadow.

Nie powinny się uczyć w pierwszej kolejności:

- wielkości ryzyka kapitału,
- ochrony piątkowej,
- kill switcha,
- twardych progów czarnego łabędzia,
- zasad wykonania mostu.

## Co jest stanem idealnym

Stan idealny nie oznacza `50/50` między `SafetyBot` a warstwą uczącą.

Stan idealny oznacza:

- `SafetyBot` ma stałe prawo weta,
- warstwa ucząca ma zmienną wagę,
- ta waga zależy od jakości dowodów,
- im lepiej nauka typuje wynik netto, tym większy ma wpływ na miękkie korekty,
- im gorzej typuje, tym bardziej `SafetyBot` wraca do rdzenia własnej logiki.

## Wniosek praktyczny

Dalsze strojenie powinno iść w tej kolejności:

1. rozpisanie i inwentaryzacja parametrów,
2. oddzielenie parametrów miękkich od nienaruszalnych,
3. uczenie wpływu doradztwa na ranking i progi,
4. dopiero potem bardzo ostrożne uczenie wybranych parametrów logiki sygnału.

Najważniejsze:

- moduł uczący nie może przejąć roli `SafetyBot`,
- ale `SafetyBot` powinien coraz lepiej korzystać z jego wiedzy.
