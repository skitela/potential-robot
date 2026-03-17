# NZDUSD Context Layer V1

`NZDUSD` zostal przeniesiony na nowa sciezke paper/context learning zgodna z dopracowanym wzorcem `EURUSD`, ale bez naruszania lokalnego genotypu instrumentu.

Najwazniejsze potwierdzenia:

- `MicroBot_NZDUSD` laduje sie poprawnie w `MT5`
- potwierdzono pierwszy pelny cykl:
  - `PAPER_OPEN`
  - `PAPER_CLOSE`
  - zapis `learning_observations_v2.csv`
  - zapis `learning_bucket_summary_v1.csv`
- runtime po wdrozeniu:
  - `trade_permissions_ok=true`
  - `paper_runtime_override_active=true`
  - `market_regime=TREND`
  - `last_setup_type=SETUP_RANGE`

Pierwszy potwierdzony rekord `v2`:

- `SETUP_RANGE`
- `market_regime=TREND`
- `spread_regime=CAUTION`
- `execution_regime=GOOD`
- `confidence_bucket=LOW`
- `pnl=-2.17`
- `close_reason=PAPER_SL`

Pierwszy bucket summary:

- `SETUP_RANGE / TREND`
- `samples=1`
- `wins=0`
- `losses=1`
- `pnl_sum=-2.17`

Wazne:

- `NZDUSD` dostal nowa sciezke paper, kontekst i uczenie `v2`
- nie wdrazano jeszcze dalszego strojenia indywidualnego
- celem etapu bylo tylko doprowadzenie bota do tej samej klasy runtime co wzorzec techniczny

## Strojenie indywidualne 2026-03-13

Po obserwacji wykonano defensywne strojenie `NZDUSD`, bo byl to jeden z najbardziej stratnych instrumentow po przejsciu na nowa sciezke.

Najwazniejsze zmiany:

- dodano dodatkowa kare dla `SETUP_RANGE`, gdy:
  - swiece i `Renko` sa w konflikcie
  - `market_regime` nie jest `RANGE`
  - a spread jest w `CAUTION`
- utrzymano i wzmocniono capy defensywne przy:
  - dlugiej serii strat
  - mocno negatywnym `learning_bias`
- nie zmieniano lokalnego charakteru pary:
  - `SETUP_RANGE` pozostaje jej waznym elementem
  - ale nie moze juz dominowac w zlym srodowisku

Stan po strojeniu:

- `runtime_mode=READY`
- `market_regime=TREND`
- `spread_regime=CAUTION`
- `execution_regime=GOOD`
- `last_setup_type=SETUP_RANGE`
- `signal_confidence=0.2764`
- `signal_risk_multiplier=0.5500`
- `learning_sample_count=39`
- `wins/losses=0/39`

Najuczciwszy wniosek:

- `NZDUSD` zostal wyraznie schlodzony
- to nie jest jeszcze para "naprawiona", ale przestala byc pozostawiona bez obrony wobec bardzo zlego bucketu
- teraz potrzebuje obserwacji, czy nowa defensywna regulacja zacznie wreszcie odwracac trend
