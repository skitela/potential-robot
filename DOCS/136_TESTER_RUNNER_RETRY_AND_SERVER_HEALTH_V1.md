# 136 TESTER RUNNER RETRY AND SERVER HEALTH V1

## Cel
Domknac dzisiejsza runde przed zamknieciem komputera:
- zapisac tylko te zmiany, ktore sa uczciwie potwierdzone
- poprawic niezawodnosc laboratorium MT5
- sprawdzic, czy hosting MetaTrader VPS pracuje zdrowo

## Co zostalo zaakceptowane
### Runner testera
W `TOOLS/RUN_MICROBOT_STRATEGY_TESTER.ps1` dodano retry przy odczycie plikow TSV:
- `candidate_signals.csv`
- `learning_bucket_summary_v1.csv`
- `learning_observations_v2.csv`
- `tuning_deckhand.csv`

To naprawia realny problem procesu:
- tester konczyl bieg poprawnie
- ale chwilowy lock pliku mogl wysadzic eksport summary i knowledge

Ta poprawka jest bezpieczna i przydatna dla wszystkich kolejnych par.

## Co zostalo odrzucone lub wycofane
### EURUSD
Proba ulgi deckhanda dla `SETUP_TREND / BREAKOUT` nie dala realnej zmiany w wyniku ani w trust state.

Wniosek:
- poprawka zostala wycofana

### EURJPY
Proba odciecia `SETUP_RANGE / CHAOS / BAD spread` zostala uruchomiona, ale wynik nie byl epistemicznie czysty:
- summary wskazal skok probki i otwarc nieproporcjonalny do poprzedniego baseline
- zmiana nie zostala zostawiona w kodzie

Wniosek:
- poprawka zostala wycofana
- do dalszej pracy zostaje bardziej niezawodny runner, nie sama delta strategii

## Stan hostingu VPS
Z logu `hosting.6797020.terminal\\20260318.log`:
- `17 charts`
- `17 EAs`
- brak crash loopow
- brak samoczynnych shutdownow
- regularne heartbeat'y godzinowe
- ping stabilny mniej wiecej `1.75 - 2.18 ms`

Z logu `hosting.6797020.experts\\20260318.log`:
- wszystkie eksperty zaladowaly sie poprawnie po migracji porannej

## Wniosek
Przed zamknieciem dnia zostawiamy:
- dzialajacy i zdrowszy pipeline testera
- zaakceptowana wczesniejsza poprawke `GBPUSD`
- nowe baseline'y dla kolejnych par
- zdrowy i pracujacy VPS

Nie zostawiamy:
- niepotwierdzonej delty `EURUSD`
- niepotwierdzonej delty `EURJPY`
