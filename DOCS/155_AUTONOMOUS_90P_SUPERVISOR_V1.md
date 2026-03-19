# Autonomous 90P Supervisor V1

## Cel

Uruchomic lekki nadzor automatyczny, ktory bez rozmowy z AI pilnuje najwazniejszych pasow pracy:
- raport priorytetow weakest-first
- snapshot operatorski
- weakest-first MT5 batch
- QDM weakest sync
- ML refresh + train

## Co robi supervisor

W kazdym cyklu:
- przebudowuje `tuning_priority_latest`
- zapisuje lokalny snapshot operatorski
- sprawdza czy dziala archiver
- sprawdza czy dziala `qdmcli`
- sprawdza czy dziala `refresh_and_train_ml`
- sprawdza czy dziala weakest-first `MT5`
- zapisuje wlasny status do `EVIDENCE\OPS`

## Pliki

- `RUN\RUN_AUTONOMOUS_90P_SUPERVISOR.ps1`
- `RUN\START_AUTONOMOUS_90P_SUPERVISOR_BACKGROUND.ps1`
- `RUN\GET_AUTONOMOUS_90P_STATUS.ps1`
- `RUN\STOP_AUTONOMOUS_90P_SUPERVISOR.ps1`

## Efekt

To nie jest silnik decyzji tradingowych. To jest warstwa porzadku i ciaglosci pracy, ktora:
- wykorzystuje zainstalowane narzedzia
- zmniejsza reczne odpalanie rutyn
- redukuje potrzebne tokeny AI do podstawowej kontroli
- utrzymuje weakest-first jako glowna kolejke laboratorium
