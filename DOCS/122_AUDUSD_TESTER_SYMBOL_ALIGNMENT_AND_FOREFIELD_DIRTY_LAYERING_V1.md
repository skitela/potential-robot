# AUDUSD Tester Symbol Alignment And Forefield Dirty Layering V1

## Cel

Domknac dwa elementy workflow testera dla kolejnych mikrobotow:
- wyrownac symbol testera z realnym srodowiskiem MT5 (`AUDUSD.pro`, nie gole `AUDUSD`)
- rozbic `FOREFIELD_DIRTY` o komponent spreadowy, bez psucia hot-path i bez mieszania runtime VPS

## Zmiany

### 1. Symbol testera

W [RUN_MICROBOT_STRATEGY_TESTER.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\RUN_MICROBOT_STRATEGY_TESTER.ps1):
- dodano `Resolve-TesterSymbol`
- dla par FX zapisanych w rejestrze bez sufiksu runner dopina `.pro`
- explicit override `-Symbol` nadal ma pierwszenstwo

To wyrownuje tester z lokalnym profilem MT5 i z hostingiem, gdzie charty pracuja na symbolach `.pro`.

### 2. Czystszy odczyt wyniku biegu

W tym samym runnerze:
- wynik biegu jest teraz czytany z logu testera dla biezacego `expert + symbol + zakres dat`
- nie opieramy sie juz na pierwszym historycznym dopasowaniu w dziennym logu
- timeout bez wyniku nie udaje sukcesu

### 3. Delta compare

W [COMPARE_STRATEGY_TESTER_RUNS.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\COMPARE_STRATEGY_TESTER_RUNS.ps1):
- poprawiono generowanie markdown
- delta raport moze byc juz uzywana jako staly artefakt po kolejnych przebiegach

### 4. `FOREFIELD_DIRTY` z komponentem spreadowym

W:
- [MbTuningTypes.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningTypes.mqh)
- [MbTuningDeckhand.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningDeckhand.mqh)
- [MbTuningEpistemology.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningEpistemology.mqh)
- [MbTuningStorage.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningStorage.mqh)
- [MbTuningLocalAgent.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningLocalAgent.mqh)

doszedl:
- `candidate_dirty_spread_rows`
- reason `FOREFIELD_DIRTY_BY_SPREAD_DISTORTION`

Spreadowy brud jest teraz widoczny w deckhandzie, reasoningu i raportach, ale nie dostal sztucznego priorytetu, jesli nie dominuje nad reszta brudu.

## Wniosek dla AUDUSD

Najwazniejsza poprawa poznawcza nie polega na tym, ze `AUDUSD` stalo sie nagle dobre, tylko na tym, ze:
- stary bieg na `AUDUSD` byl zanizony poznawczo przez zly symbol testera
- poprawny bieg na `AUDUSD.pro` pokazal duzo bogatszy material
- po dodaniu spread dirty okazalo sie, ze spread jest obecny, ale nie jest glownym winowajca

Na tym etapie glowny problem `AUDUSD` w testerze pozostaje:
- `FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_HYBRID`
- bardzo duzy wolumen `SCORE_BELOW_TRIGGER`

Czyli kolejny ruch powinien isc bardziej w oczyszczanie/jakosc materialu niz w dalsze obwinianie spreadu.
