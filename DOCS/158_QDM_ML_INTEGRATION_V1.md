# 158 QDM ML Integration V1

## Cel
- wlaczyc kupione dane `QDM` do lokalnej petli research i uczenia maszynowego
- nie opierac ML tylko na biezacych logach `MT5`, ale laczyc:
- `paper/runtime history`
- `tester history`
- `QDM market history`

## Co zostalo zrobione
- `EXPORT_MT5_RESEARCH_DATA.py` buduje teraz:
- `qdm_tick_inventory_latest`
- `qdm_minute_bars_latest`
- cache minutowych barow `QDM`
- `TRAIN_PAPER_GATE_ACCEPTOR_MODEL.py` dolacza cechy `QDM` do `candidate_signals`

## Nowe cechy QDM
- `qdm_tick_count`
- `qdm_spread_mean`
- `qdm_spread_max`
- `qdm_mid_range_1m`
- `qdm_mid_return_1m`
- `qdm_data_present`

## Krytyczna poprawka
- eksport logow research nie moze brac tylko biezacych plikow z `logs\<symbol>\*.csv`
- archiwa w `logs\<symbol>\archive\...\*.csv` zostaly wlaczone do eksportu
- bez tego ML widzial tylko ostatni wycinek runtime i tracil miliony rekordow historii

## Stan po integracji
- `candidate_signals`: `4086426`
- `decision_events`: `4549897`
- `qdm_minute_bars`: `11412206`
- `QDM coverage` w aktualnym modelu: `0.0823`

## Symbole z aktywnym pokryciem QDM
- `EURUSD`
- `GBPUSD`
- `USDJPY`

## Ograniczenia na teraz
- `QDM` jest jeszcze pobrane tylko dla 3 symboli
- pozostale symbole dostana pokrycie dopiero po dalszym syncu `QDM`
- model juz korzysta z `QDM`, ale pelny efekt przyjdzie dopiero po rozszerzeniu pobran na reszte grup

## Wniosek
- kupione dane `QDM` sa juz wlaczone do lokalnej petli research i ML
- teraz trzeba konsekwentnie rozszerzac pobrania `QDM`, bo wraz z nimi bedzie roslo pokrycie i wartosc modelu
