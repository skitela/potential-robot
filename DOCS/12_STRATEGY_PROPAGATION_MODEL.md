# Strategy Propagation Model

## Cel

Ten etap porzadkuje przyszly rozwoj `11` mikro-botow tak, aby:

- rozwijac jedna wersje wzorcowa,
- propagowac tylko zmiany wspolne,
- nie niszczyc cech osobowych poszczegolnych par.

## Zasada

Nie utrzymujemy `11` niezaleznych kopii logiki.
Utrzymujemy:

1. `common strategy flow`
2. `symbol overrides`
3. `tooling do propagacji`

## Co jest wspolne

Do wspolnej warstwy powinno trafic tylko to, co daje sie aktualizowac globalnie bez utraty edge symbolowego:

- lifecycle strategii `Init / Deinit / Evaluate / ManagePosition`
- nowe-bar gating
- schemat pobierania `EMA / ATR / RSI`
- schemat budowy risk plan
- schemat trailing management
- wspolny flow:
  - `market -> guards -> evaluate -> risk_plan -> precheck -> send -> manage`

To jest dobry kandydat do przyszlych plikow typu:

- `MQL5/Include/Strategies/Common/MbStrategyIndicators.mqh`
- `MQL5/Include/Strategies/Common/MbStrategyRiskBase.mqh`
- `MQL5/Include/Strategies/Common/MbStrategyDecisionBase.mqh`
- `MQL5/Include/Strategies/Common/MbStrategyManageBase.mqh`

## Co ma zostac lokalne

W mikro-botach albo w lokalnym rejestrze override'ow powinny zostac:

- `session_profile`
- `trade_window_start_hour`
- `trade_window_end_hour`
- spread caps
- wspolczynniki `EMA fast/slow`
- `ATR` multipliers
- `risk_pct` base/min/max
- `trigger_abs`
- aktywne setupy:
  - `trend`
  - `pullback`
  - `breakout`
  - `rejection`
  - `range`
  - `reversal`
- trailing multipliers
- lokalne nazwy `SETUP_*`
- lokalne modele ryzyka symbolu:
  - `risk_pct_base/min/max`
  - `execution_floor`
  - `execution_decay`
  - `SL/TP` multipliers
  - `SL/TP` minima

## Obecny stan

Projekt ma juz wygenerowany rejestr wariantow:

- `CONFIG/strategy_variant_registry.json`
- `EVIDENCE/strategy_variant_audit.json`

Ten rejestr jest pierwszym krokiem do bezpiecznej propagacji, bo pokazuje:

- co jest naprawde wspolne,
- co jest override'em symbolowym,
- jakie sa roznice miedzy `EURUSD`, `FX_MAIN`, `FX_ASIA` i `FX_CROSS`.

## Docelowy workflow

1. Rozwijamy wzorzec lokalnie.
2. Aktualizujemy wspolny flow w plikach `Common`.
3. Regenerujemy albo walidujemy registry override'ow.
4. Mikro-boty pozostawiaja swoje lokalne profile i lokalne parametry.
5. Delta deploy przenosi tylko zmiany wspolne i tylko te pliki, ktore sie zmienily.

## Najwazniejsza zasada

Propagacja ma aktualizowac:

- kod wspolny,
- kontrakty wspolne,
- helpery wspolne.

Propagacja nie moze automatycznie nadpisywac:

- okien handlu,
- spreadu,
- setupow symbolowych,
- lokalnych progow wejscia,
- lokalnych multiplierow risk/trailing.

## Co dalej

Nastepny etap to refaktor:

1. wyciagniecie `common strategy flow` do wspolnych include'ow,
2. pozostawienie per-symbol override'ow w profilach albo registry,
3. dodanie narzedzia, ktore waliduje czy dany bot nadal jest zgodny z kontraktem wspolnym.

## Pierwszy wykonany refaktor

Pierwsze kroki zostaly juz wykonane:

- powstal wspolny helper `MQL5/Include/Strategies/Common/MbStrategyCommon.mqh`
- cale `11/11` zostalo przepiete na ten helper dla:
  - kopiowania ostatniej wartosci indikatorow
  - wspolnego liczenia lota/risku
- cale `11/11` zostalo przepiete na wspolny builder `risk planu`, ale:
  - mnozniki `SL/TP`
  - progi minimalne
  - model ryzyka symbolu
  zostaly lokalne dla kazdej pary
- cale `11/11` zostalo przepiete na wspolny helper trailing/position-management, ale:
  - `trail_atr_multiplier`
  - skala kroku pod `execution_pressure`
  zostaly lokalne dla kazdej pary
- cale `11/11` zostalo przepiete na wspolny helper `new-bar gate`, ale:
  - lokalne setupy
  - progi triggerow
  - scoring
  zostaly lokalne dla kazdej pary
- cale `11/11` zostalo przepiete na wspolny helper init/deinit wskaznikow, ale:
  - okresy `EMA`
  - okres `ATR`
  - okres `RSI`
  zostaly lokalne dla kazdej pary
- cale `11/11` zostalo juz przepiete na helper wyboru najlepszego wyniku po `best_abs`, ale:
  - same formuly scoringu
  - same etykiety setupow
  zostaly lokalne
- cale `11/11` zostalo juz przepiete na helper koncowego `trigger gate`, ale:
  - lokalne progi `trigger_abs`
  - lokalne `setup_reason`
  zostaly lokalne
- po tej zmianie pelna kompilacja `11/11` mikro-botow przeszla poprawnie

## Co to oznacza praktycznie

Od tego momentu poprawka wspolnego schematu:

- kopiowania indikatorow
- liczenia lota
- budowy risk planu
- trailing/position management
- new-bar gate / current bar resolution
- indicator init/deinit lifecycle
- setup winner selection (`best_abs`)
- final signal trigger gate / side resolution

moze byc wprowadzana raz w `Common`, a mikro-boty zachowuja swoje:

- okna handlu
- setupy
- wlasne wagi
- lokalne mnozniki i progi ryzyka

## Granica dla warstwy ryzyka

Wspolny moze byc:

- schemat obliczenia
- wspolny helper
- wspolny hard-guard runtime

Lokalne maja zostac:

- wartosci modelu ryzyka
- reakcja symbolu na execution pressure
- lokalny profil `SL/TP/trail`

## Workflow operatorski

Do praktycznego planowania sluzy:

- `TOOLS/PLAN_STRATEGY_PROPAGATION.ps1`

Skrypt pokazuje:

- ktore symbole sa celem propagacji
- co wolno rozlac
- czego nie wolno nadpisywac
## 2026-03-12 - First low-latency propagation candidate

Pierwszym bezpiecznym kandydatem do propagacji między rodzinami jest buforowany journaling:

- `MbDecisionJournal.mqh`
- `MbExecutionTelemetry.mqh`
- `MbIncidentJournal.mqh`
- `MbTradeTransactionJournal.mqh`

Zakres propagacji:

- wspólne dla wszystkich botów: kolejka w pamięci, flush na timerze, próg awaryjnego flush
- lokalne dla bota: fazy decyzji, reason codes, scoring, profile ryzyka

Cel:

- ograniczyć liczbę `FileOpen/FileClose` wykonywanych w `OnTick`
- ograniczyć liczbę `FileOpen/FileClose` wykonywanych w `OnTradeTransaction`
- utrzymać ten sam ślad audytowy
- nie naruszyć lokalnej logiki wejścia i ochrony kapitału
