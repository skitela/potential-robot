# Pierwsza Fala: wzorzec odblokowania toru lokalnego

Ten dokument zbiera praktyczne wnioski z odblokowania pierwszej fali poza laboratorium
(`Common Files`, zwykły terminal OANDA), tak aby ten sam wzorzec dało się później
przenieść na drugą partię instrumentów.

## Co było rzeczywistą blokadą

Blokada nie była pojedynczym błędem. Łańcuch zatrzymywał się na kilku warstwach:

1. Ogranicznik żądań potrafił utrzymywać stare liczniki na podstawie zapisanych stanów
   runtime, więc nowe próby były blokowane mimo braku realnej aktywności w bieżącym
   oknie czasu.
2. Diagnostyczny przebieg czasowy nie był jednakowy w całej czwórce. `US500` nie
   opakowywał `OnTick()` w aktywację skanu diagnostycznego, więc obejście
   `WAIT_NEW_BAR` nie działało tam tak samo jak w pozostałych botach.
3. Miękkie odrzucenia były ratowane zbyt wąsko. Sama obecność
   `SCORE_BELOW_TRIGGER` nie wystarczała, bo dalszy przebieg zależał jeszcze od
   lokalnych progów i kosztów.
4. Sprawdzenie wykonania w trybie papierowym było za twarde dla pierwszej fali.
   Nawet gdy diagnostyka doprowadzała sygnał do próby, ścieżka mogła zatrzymać się
   na `NET_EDGE_TOO_SMALL*` albo na historycznym ograniczniku żądań.
5. Sam sposób uruchomienia terminala też miał znaczenie. Surowe uruchomienie profilem
   potrafiło dawać niepełny obraz, dopiero start przez skrypt profilu zapewnił właściwe
   wykresy i zestaw presetów roboczych.

## Co odblokowało system

Najskuteczniejsza kolejność była taka:

1. Dodać odświeżanie okien ogranicznika żądań na podstawie bieżącego czasu:
   - `MbRefreshRateGuardWindows(...)` w [MbRateGuard.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbRateGuard.mqh)
2. Wpuścić obejście ogranicznika żądań w aktywnym trybie diagnostycznym pierwszej fali:
   - `MbShouldBypassFirstWaveTruthDiagnosticRateGuard(...)`
   - wykorzystanie tego w czterech botach
3. Wpuścić obejście krytycznych blokad sprawdzenia wykonania:
   - `NET_EDGE_TOO_SMALL_FOR_TIME_STOP`
   - `NET_EDGE_TOO_SMALL`
4. Ujednolicić przebieg czasowy `US500` z pozostałą trójką:
   - `MbBeginFirstWaveTruthDiagnosticTimerScan(...)`
   - `MbEndFirstWaveTruthDiagnosticTimerScan()`
5. Uprościć ratowanie miękkich odrzuceń bezpośrednio w botach:
   - lokalna biała lista `SCORE_BELOW_TRIGGER`, `LOW_CONFIDENCE`,
     `CONTEXT_LOW_CONFIDENCE`, `AUX_CONFLICT_BLOCK`,
     `FOREFIELD_DIRTY_*`, `PAPER_CONVERSION_BLOCKED_*`
   - bez polegania wyłącznie na pośrednim helperze
6. Uruchamiać realny terminal OANDA przez
   [setup_mt5_microbots_profile.py](C:\MAKRO_I_MIKRO_BOT\TOOLS\setup_mt5_microbots_profile.py),
   a nie tylko przez surowy `/profile`.

## Po czym poznaliśmy, że naprawa działa

Nie po samym hałasie w logu, tylko po świeżym, pełnym łańcuchu:

1. `EXEC_PRECHECK READY`
2. `EXECUTION_TRUTH_OPEN OK`
3. `PAPER_POSITION_SAVE OK`
4. `PAPER_OPEN OK`
5. `PAPER_CLOSE`
6. `EXECUTION_TRUTH_CLOSE OK`
7. `LESSON_WRITE OK`
8. `KNOWLEDGE_WRITE OK`

Najmocniejsze świeże dowody po tej serii poprawek:

- [decision_events.csv](C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\logs\US500\decision_events.csv)
- [decision_events.csv](C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\logs\EURJPY\decision_events.csv)
- [execution_truth_US500.csv](C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\spool\execution_truth\execution_truth_US500.csv)
- [execution_truth_EURJPY.csv](C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\spool\execution_truth\execution_truth_EURJPY.csv)
- [first_wave_lesson_closure_latest.json](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\first_wave_lesson_closure_latest.json)

## Aktualny stan

Po tej serii zmian zwykły tor lokalny poza laboratorium świeżo domyka się już dla:

- `US500`
- `EURJPY`

Nadal nie świeżo dla:

- `AUDUSD`
- `USDCAD`

To oznacza, że wzorzec działa, ale dla drugiej pary trzeba jeszcze znaleźć
ostatnią, bardziej lokalną blokadę w logice przejścia z miękkiego odrzucenia do
realnej próby.

## Jak używać tego wzorca przy drugiej partii instrumentów

1. Najpierw sprawdzić, czy logi `decision_events.csv` są świeże.
2. Potem sprawdzić, czy `candidate_signals.csv` pokazuje świeże `setup_type`,
   a nie tylko puste `NONE`.
3. Jeśli są `SCORE_BELOW_TRIGGER`, najpierw sprawdzić:
   - ogranicznik żądań,
   - przebieg czasowy,
   - blokady `NET_EDGE_TOO_SMALL*`,
   - sposób uruchomienia terminala/profile.
4. Dopiero potem ruszać strategie i progi punktowe.
5. Nie wysyłać na VPS, dopóki zwykły tor lokalny nie pokazuje świeżego domknięcia
   dla wszystkich symboli w danej partii.
