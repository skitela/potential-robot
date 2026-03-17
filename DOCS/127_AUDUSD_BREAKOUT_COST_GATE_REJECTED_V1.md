# AUDUSD Breakout Cost Gate Rejected V1

## Cel

Sprawdzic, czy odciecie breakoutow z `CAUTION/BAD spread` poprawi `AUDUSD` w
testerze bez utraty materialu.

## Hipoteza

W czystej bazie `audusd_strategy_tester_20260317_185018` tylko kilka otwartych
breakoutow mialo `spread_regime != GOOD`, a wszystkie takie lekcje byly stratne.
Na malej probce wygladalo to jak tani filtr kosztowy.

## Zmiana testowana

W `MicroBot_AUDUSD.mq5` dodano lokalna bramke paper:

- jesli `setup_type == SETUP_BREAKOUT`
- oraz `spread_regime != GOOD`
- to kandydat byl blokowany reasonem
  `AUDUSD_BREAKOUT_COST_GATE_BLOCK`

## Biegi porownawcze

- baza:
  - `audusd_strategy_tester_20260317_185018`
- po zmianie:
  - `audusd_strategy_tester_20260317_192246`

## Wynik

Eksperyment odrzucony.

Po pelnym biegu filtr nie dal malej poprawy kosztowej, tylko rozjechal przebieg:

- `realized_pnl_lifetime: -3.30 -> -17.26`
- `learning_sample_count: 246 -> 534`
- `paper_open_rows: 252 -> 542`
- `paper_score_gate_rows: 146 -> 357`
- `paper_conversion_ratio: 1.7260 -> 1.5182`

To znaczy, ze bramka nie odciela tylko kilku toksycznych wejsc. Zmieniala tez
globalny przebieg kandydata i wpychala system w zly stan porownawczy.

## Decyzja

Zmiana wycofana.

Kod wraca do stanu po:

- `AUDUSD deckhand dirty accounting relief`

## Wniosek

Koszt nie jest tutaj dobrym miejscem na szybka chirurgiczna blokade breakoutow w
warstwie paper. Dla `AUDUSD` taka bramka daje za duzo skutkow ubocznych wzgledem
korzysci.
