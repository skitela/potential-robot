# 74. Session Capital Defensive and Reentry V2

## Cel

Ten etap zamienia architekture `paper -> reserve -> reentry` z warstwy opisowej w warstwe operacyjna.

Koordynator sesji i kapitalu potrafi teraz nie tylko:

- uspic domene,
- przelaczyc domene do `PAPER_ONLY`,
- oznaczyc rezerwe,

ale tez:

- ograniczyc realne ryzyko w trybie `LIVE_DEFENSIVE`,
- uruchomic `REENTRY_PROBATION` z bardzo ciasnym ryzykiem,
- promowac domene rezerwowa z `RESERVE_RESEARCH` do `RUN`, jesli domena glowna wypadla do `paper`.

## Najwazniejsza zasada

Nie budzimy dodatkowej domeny po to, zeby "cos robila".

Budzenie rezerwy jest dozwolone tylko wtedy, gdy:

- domena glowna jest aktywna i stracila prawo do live,
- domena rezerwowa jest w swoim sensownym oknie:
  - `LIVE`
  - `PREWARM`
  - `RESERVE_RESEARCH`
- domena rezerwowa nie ma blokady rodzinnej ani flotowej.

## Nowy lekki sygnal runtime

Do `runtime_control.csv` dochodzi teraz pole:

- `risk_cap`

Jest ono czytane przez:

- `MbRuntimeControl.mqh`
- `MbStrategyCommon.mqh`

I dziala jako wspolny, domenowy kaganiec ryzyka.

To oznacza:

- brak nowej ciezkiej logiki na ticku,
- brak nowych obliczen flotowych w MQL5,
- ale realny wplyw koordynatora na sizing.

## Nowe stany operacyjne

### `LIVE_DEFENSIVE`

Stan aktywny, ale z przycietym ryzykiem.

Wchodzi, gdy:

- domena jest w `LIVE`,
- nie ma jeszcze twardej blokady `paper`,
- ale zbliza sie do granicy bezpieczenstwa.

V2 uzywa progu:

- `family_max_daily_loss_pct >= 50% rodzinnego hard limitu`
  albo
- `fleet_daily_loss_pct >= live.account_soft_daily_loss_pct`

Domyslny `risk_cap`:

- `0.50`

czyli zgodny z `soft_loss_risk_factor` z kontraktu kapitalowego.

### `REENTRY_PROBATION`

Stan kontrolowanego powrotu z `paper` do `live`.

Wchodzi tylko wtedy, gdy:

- blokada byla rodzinna, nie flotowa,
- domena jest znowu w aktywnym oknie `LIVE`,
- rodzina i flota maja zaufane dane,
- strata rodziny spadla ponizej `60%` rodzinnego limitu hard,
- strata floty spadla ponizej `60%` limitu hard floty.

Domyslny `risk_cap`:

- `0.35`

To ma byc powrot probny, nie pelne odblokowanie.

### `PAPER_ACTIVE`

Stan domeny, ktora nadal patrzy na rynek i generuje dane, ale nie ma prawa otwierac live.

Jest to bardziej precyzyjne niz dawne "po prostu paper".

### `RESERVE takeover`

Jesli domena rezerwowa zyje w `RESERVE_RESEARCH`, koordynator moze awansowac ja do `RUN`.

Domyslny `risk_cap` takeover:

- `0.50`

Czyli rezerwa nie wchodzi od razu z pelna sila.

## Gdzie to jest wpiete

### PowerShell

- `CONFIG/session_capital_coordinator_v1.json`
- `TOOLS/APPLY_SESSION_CAPITAL_COORDINATOR.ps1`
- `TOOLS/VALIDATE_SESSION_CAPITAL_COORDINATOR.ps1`

### MQL5

- `MQL5/Include/Core/MbRuntimeTypes.mqh`
- `MQL5/Include/Core/MbRuntimeControl.mqh`
- `MQL5/Include/Core/MbStorage.mqh`
- `MQL5/Include/Strategies/Common/MbStrategyCommon.mqh`
- `MQL5/Include/Core/MbExecutionSummaryPlane.mqh`
- `MQL5/Include/Core/MbInformationalPolicyPlane.mqh`

## Co widac teraz w stanie domeny

`session_capital_state.csv` zapisuje teraz dodatkowo:

- `window_state`
- `requested_risk_cap`
- `defensive_mode`
- `reserve_requested_by`

Czyli operator i agent strojenia widza juz roznice miedzy:

- naturalnym stanem okna,
- stanem po ochronie kapitalu,
- i stanem po aktywacji rezerwy.

## Ograniczenia V2

- `INDICES` nadal nie sa runtime deployed, wiec moga byc widziane jako rezerwa logiczna, ale nadal nie przejda do faktycznego live bez kolejnego rolloutu.
- Reentry jest domenowe, nie per-symbol.
- Rezerwa nie jest budzona poza wlasnym sensownym oknem.
- Nie ma jeszcze licznika probacji wielokrotnej tego samego dnia.

## Najwazniejszy efekt

Od teraz koordynator nie tylko decyduje, czy domena ma grac.

Decyduje tez:

- z jaka sila ma grac,
- czy ma wracac probnie,
- i czy wolno uruchomic rezerwe zamiast martwego okna.
