# 158 NZDUSD Dirty Breakout Gate V1

## Cel
- Przyciąć najbardziej toksyczne breakouty w `NZDUSD`, bez rozszerzania logiki na cały instrument.

## Wejście diagnostyczne
- Tester `2026-03-19 03:32` pokazał:
- `FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_HYBRID`
- najgorsze bucket-y:
- `SETUP_BREAKOUT / CHAOS` `10/10` strat
- `SETUP_BREAKOUT / BREAKOUT` `7/7` strat
- `SETUP_BREAKOUT / TREND` lekko ujemne, ale nie katastrofalne

## Zmiana
- W `MicroBot_NZDUSD.mq5` dodano wąski blok `NZDUSD_BREAKOUT_DIRTY_FOREGROUND_BLOCK` dla:
- `SETUP_BREAKOUT`
- `CHAOS` lub `BREAKOUT`
- słaba świeca
- oraz dodatkowo: słabe renko albo `LOW` confidence albo `BAD` spread
- Podniesiono też próg `paper_gate_abs` dla breakoutów z brudnym foregroundem:
- `0.84` dla `poor_candle + poor_renko`
- `0.78` dla `poor_candle` w `CHAOS/BREAKOUT`

## Intencja
- Nie ruszać `SETUP_RANGE`, bo to on dziś bardziej timeoutuje niż twardo przegrywa.
- Nie blokować szeroko breakoutów w `TREND`, bo tam materiał jest mieszany, nie jednoznacznie toksyczny.

## Następny krok
- Retest `NZDUSD` po zwolnieniu wtórnego toru `MT5`.
