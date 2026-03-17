# AUDUSD Breakout Weak Renko Short Hold V1

## Cel

Ograniczyc straty w bucketach `SETUP_BREAKOUT / BREAKOUT` oraz
`SETUP_BREAKOUT / TREND` bez zmniejszania liczby lekcji przez twarde blokady wejsc.

## Dowod wejsciowy

Na czystej bazie `audusd_strategy_tester_20260317_175253` najbardziej toksyczne
kombinacje breakoutowe mialy wspolna ceche:

- slabe lub niepewne `renko`
- duzy udzial `PAPER_TIMEOUT`

Najbardziej problematyczne grupy:

- `BREAKOUT, GOOD, POOR`
- `BREAKOUT, FAIR, UNKNOWN`
- `BREAKOUT, POOR, FAIR`
- `TREND, POOR, FAIR`

## Zmiana

W `ResolveAUDUSDPaperHoldSeconds()` dodano węższy skrot czasu trzymania dla:

- `setup_type == SETUP_BREAKOUT`
- `market_regime == BREAKOUT`
- `renko_quality_grade == POOR`
  lub
- `renko_quality_grade == UNKNOWN` i swieca nie jest `GOOD`

Nowy `hold_seconds` dla tej klasy:

- `150`

## Bieg walidacyjny

- baza:
  - `audusd_strategy_tester_20260317_175253`
- po zmianie:
  - `audusd_strategy_tester_20260317_182049`

## Wynik

Zmiana jest mala, ale pozytywna:

- `realized_pnl_lifetime`: `-4.67 -> -3.98`
- `learning_sample_count`: `250 -> 249`
- `learning_loss_count`: `136 -> 135`
- `paper_open_rows`: `255 -> 255`
- `paper_conversion_ratio`: `1.7347 -> 1.7466`

Buckety breakoutowe tez lekko sie poprawily:

- `SETUP_BREAKOUT / BREAKOUT`: `-0.0749 -> -0.0676`
- `SETUP_BREAKOUT / TREND`: `-0.0678 -> -0.0537`

## Decyzja

Zmiane przyjmujemy.

To nie jest jeszcze przewaga, ale jest to poprawa lokalna bez utraty materialu
poznawczego i bez rozjechania reszty bota.
