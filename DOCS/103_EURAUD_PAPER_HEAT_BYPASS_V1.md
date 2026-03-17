# 103 EURAUD Paper Heat Bypass V1

Data: 2026-03-16

## Cel
Po pierwszym odetkaniu `EURAUD` nadal tracil zbyt wiele lekcji paper przez:
- `ARBITRATION / SKIP / PORTFOLIO_HEAT_BLOCK`

Rynek pracowal, sygnaly `SETUP_RANGE` byly swieze, ale lokalny agent dalej zywil sie glownie starym materialem breakoutowym.

## Zmiana
W `MicroBot_EURAUD.mq5` dodano bardzo waski bypass tylko dla `paper`:
- tylko dla `PORTFOLIO_HEAT_BLOCK`
- tylko dla `SETUP_RANGE`
- tylko przy mocnym score
- tylko przy dobrej egzekucji
- tylko gdy spread nie jest zly
- tylko gdy swieca nie jest `POOR`

Nie dotyka to `live`.

## Efekt po wdrozeniu
Po kompilacji `17/17` i restarcie MT5:
- `EURAUD` nadal zostawia czesc blokad `PORTFOLIO_HEAT_BLOCK`,
- ale juz nie jest przez nie calkowicie duszony,
- pojawil sie swiezy `PAPER_OPEN / OK`,
- rosnie liczba:
  - `paper_open`
  - `observations`
  - `bucket_rows`

To oznacza, ze symbol zaczal szybciej produkowac nowe lekcje paper dla setupow `range`.

## Ograniczenie
Lokalny agent wciaz ma historyczny fokus na `SETUP_BREAKOUT / BREAKOUT`, bo stary material nadal dominuje w bucketach. Ta poprawka nie zmienia jeszcze samej doktryny fokusu, tylko odtyka doplyw nowych lekcji.

