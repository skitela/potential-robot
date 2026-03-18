# 134 SECOND TRIO TESTER RERUN AND SUMMARY ALIGNMENT V1

## Cel
Domknac drugi pakiet par testera MT5:
- GBPUSD
- USDCAD
- USDCHF

oraz uszczelnic warstwe analizy tak, aby summary po kazdym biegu preferowalo biezacy obraz deckhanda, a nie tylko surowe `execution_summary`.

## Problem
W izolowanym testerze summary potrafilo raportowac mniej precyzyjny stan:
- `trust_state`
- `trust_reason`
- `execution_quality_state`
- `cost_pressure_state`

z `execution_summary`, mimo ze snapshot deckhanda juz widzial dokladniejsza prawde testera. To grozilo zlym priorytetem napraw:
- strojenie sygnalu zamiast kosztu,
- strojenie strategii zamiast reprezentatywnosci probki.

## Zmiana
W `TOOLS/RUN_MICROBOT_STRATEGY_TESTER.ps1` summary po biegu:
- preferuje `deckhandSnapshot.trust_state`
- preferuje `deckhandSnapshot.reason_code` jako `trust_reason`
- preferuje `deckhandSnapshot.execution_quality_state`
- preferuje `deckhandSnapshot.cost_pressure_state`

Jednoczesnie surowe wartosci z `execution_summary` pozostaja zachowane w polach:
- `execution_summary_trust_state`
- `execution_summary_trust_reason`
- `execution_summary_execution_quality_state`
- `execution_summary_cost_pressure_state`

To nie zmienia runtime botow ani VPS. To jest poprawka epistemologii i raportowania laboratorium MT5.

## Wynik rerunu
### GBPUSD
- repeatability: `STABLE`
- `trust_state = FOREFIELD_DIRTY`
- `trust_reason = FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_CANDLE`
- `cost_pressure_state = NON_REPRESENTATIVE`
- `sample_count = 241`
- `realized_pnl_lifetime = -18.07`
- tester readiness: `COST_SKEWED`

Wniosek:
- baseline jest juz stabilny
- nie stroic jeszcze logiki wejsc
- najpierw reprezentatywnosc kosztu i spreadu

### USDCAD
- repeatability: `STABLE`
- `trust_state = LOW_SAMPLE`
- `cost_pressure_state = NON_REPRESENTATIVE`
- `sample_count = 4`
- `realized_pnl_lifetime = -2.36`
- tester readiness: `INSUFFICIENT_SAMPLE`

Wniosek:
- nie stroic strategii
- najpierw zwiekszyc probe albo zmienic okno testowe

### USDCHF
- repeatability: `STABLE`
- `trust_state = FOREFIELD_DIRTY`
- `trust_reason = FOREFIELD_DIRTY_BY_SPREAD_DISTORTION`
- `cost_pressure_state = NON_REPRESENTATIVE`
- `sample_count = 12`
- `realized_pnl_lifetime = -9.56`
- tester readiness: `INSUFFICIENT_SAMPLE`

Wniosek:
- nie stroic logiki sygnalu
- najpierw walczyc z kosztem, spreadem i uboga probka

## Co z tego wynika dla systemu
Drugi pakiet trzech par nie pokazal nowego celu do agresywnej zmiany strategii. Pokazal za to cos rownie cennego:
- laboratorium testera jest juz stabilniejsze
- repeatability przestala byc slepym punktem
- i wiemy, ktore pary wymagaja kosztu/probki, a nie sygnalu

To skraca dalsza prace, bo kolejne iteracje beda zaczynac od poprawnej triage:
1. sample
2. koszt i spread
3. dopiero potem sygnal
