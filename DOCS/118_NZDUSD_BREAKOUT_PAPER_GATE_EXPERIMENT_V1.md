# 118 NZDUSD Breakout Paper Gate Experiment V1

## Cel
- sprawdzic, czy waskie odetkanie breakoutow w `NZDUSD` poprawi konwersje `paper`
- zrobic to bez rozwalania czystosci diagnozy po poprzedniej poprawce `CENTRAL_STATE_STALE + RANGE/CHAOS`

## Przebieg
- wdrozono waski eksperyment na lokalnym `paper score gate` dla `SETUP_BREAKOUT`
- wykonano dwa testy porownawcze na:
  - `NZDUSD.pro`
  - `M5`
  - `2026.03.01` -> `2026.03.16`

## Wynik
- eksperyment nie poprawil realnie `paper_open`
- liczba breakoutowych `paper_open` pozostala praktycznie bez zmiany
- eksperyment dodal duzo dodatkowej klasyfikacji typu `NZDUSD_BREAKOUT_CHAOS_WEAK`
- to zwiekszylo szum logow bez jasnej poprawy poznawczej albo wynikowej

## Decyzja
- eksperyment zostal wycofany
- pozostawiono tylko wartosciowa poprawke z poprzedniej rundy:
  - ignorowanie `CENTRAL_STATE_STALE` w Strategy Tester
  - ograniczenie `SETUP_RANGE` w `CHAOS`

## Wniosek
- breakout nie jest glownym korkiem `NZDUSD`
- glowny problem nadal lezy w:
  - niskiej jakosci materialu `CHAOS`
  - toksycznym `SETUP_RANGE / CHAOS`
  - slabym obrazie `FOREFIELD_DIRTY`

## Nastepny sensowny krok
- nie odtykac breakoutow na sile
- zamiast tego:
  - poprawic diagnostyke `FOREFIELD_DIRTY`
  - rozdzielic lepiej niski score od brudnego materialu
  - zrobic raport per `setup x regime x conversion`
