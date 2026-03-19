# 145 QDM Focus Pack Automation V1

## Cel
- zautomatyzowac pierwszy sensowny pakiet instrumentow pod `QDM`
- pobierac dane historyczne bez recznego klikania
- eksportowac je do bezpiecznych nazw dla `MT5 Custom Symbols`

## Profil instrumentow
Profil startowy:
- [qdm_focus_pack.csv](C:\MAKRO_I_MIKRO_BOT\TOOLS\qdm_focus_pack.csv)

Zawiera obecnie:
- `EURUSD`
- `GBPUSD`
- `USDJPY`
- `USDCHF`
- `USDCAD`
- `NZDUSD`
- `XAUUSD`
- `XAGUSD`
- `USA500.IDX`
- `DEU.IDX`
- `COPPER.CMD`

## Automatyzacja
### 1. Dodanie i pobranie danych
- [SYNC_QDM_FOCUS_PACK.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\SYNC_QDM_FOCUS_PACK.ps1)
- [START_QDM_FOCUS_SYNC_BACKGROUND.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_QDM_FOCUS_SYNC_BACKGROUND.ps1)
- [GET_QDM_FOCUS_STATUS.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\GET_QDM_FOCUS_STATUS.ps1)
- [STOP_QDM_FOCUS_SYNC.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\STOP_QDM_FOCUS_SYNC.ps1)

Skrypt:
- zamyka wiszace procesy `QDM`, jesli trzeba
- dodaje tylko brakujace symbole do `QDM`
- robi `add/update` sekwencyjnie, ale po kazdym kroku czeka az `QDM` calkowicie zwolni procesy
- przez to unika konfliktu portu `5050` i kolizji wielu instancji
- sprawdza baze `QDM` i nie tworzy duplikatow typu `EURUSD(2)`

Launcher background:
- uruchamia ten sam sync w osobnym oknie PowerShell
- zapisuje log do `C:\TRADING_DATA\QDM\logs`

Status:
- pokazuje, czy `QDM` jest uruchomiony
- pokazuje symbole obecne w `data.db`
- pokazuje ogon ostatniego logu sync
- pokazuje ogon logu silnika `QDM`

Stop:
- ucina aktywne wrappery `PowerShell`
- zatrzymuje `qdmcli / QDataManager_nocheck / QuantDataManager_ui`
- pozwala bezpiecznie przerwac dlugi sync i wystartowac go od nowa

### 2. Eksport do MT5
- [EXPORT_QDM_FOCUS_PACK_TO_MT5.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\EXPORT_QDM_FOCUS_PACK_TO_MT5.ps1)
- [RUN_QDM_FOCUS_PIPELINE.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\RUN_QDM_FOCUS_PIPELINE.ps1)
- [START_QDM_FOCUS_PIPELINE_BACKGROUND.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_QDM_FOCUS_PIPELINE_BACKGROUND.ps1)
- [WAIT_QDM_SYNC_AND_EXPORT.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\WAIT_QDM_SYNC_AND_EXPORT.ps1)
- [START_QDM_EXPORT_AFTER_SYNC_BACKGROUND.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_QDM_EXPORT_AFTER_SYNC_BACKGROUND.ps1)

Skrypt:
- bierze ten sam profil
- eksportuje dane w formacie `MT5`
- uzywa bezpiecznych nazw:
  - `MB_EURUSD_DUKA`
  - `MB_GOLD_DUKA`
  - `MB_US500_DUKA`
  - itd.

Pipeline:
- robi `sync -> export` w jednym przebiegu
- nadaje sie do dlugiego, nocnego uruchomienia w tle
- zapisuje osobny log pipeline do `C:\TRADING_DATA\QDM\logs`

Watcher:
- czeka na zakonczenie juz uruchomionego syncu
- nie przerywa trwajacego pobierania
- po zakonczeniu syncu sam odpala eksport do `MT5`

## Dlaczego takie nazwy
Nie chcemy:
- nadpisywac symboli brokera
- mieszac customowych danych z `*.pro`
- psuc aktywnego runtime

Dlatego customowy eksport dostaje osobne nazwy `MB_*`.

## Uwaga operacyjna
`QDM` nie pozwala na wiele instancji naraz.
Dlatego nasze skrypty domyslnie czyszcza stare procesy `qdmcli / QDataManager_nocheck / QuantDataManager_ui` przed nowym biegiem.
Do tego czyszcza tez stare wrappery `PowerShell` od wczesniejszych syncow, zeby nie odrastaly konflikty po tle.

Druga wazna obserwacja:
- przy `update` dla tego toru `QDM` pobiera pelna historie zrodla
- okna `date_from / date_to` wykorzystujemy przede wszystkim przy eksporcie do `MT5`

## Najbardziej sensowny workflow
1. pobrac focus pack:
   - [SYNC_QDM_FOCUS_PACK.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\SYNC_QDM_FOCUS_PACK.ps1)
2. sprawdzic status sync:
   - [GET_QDM_FOCUS_STATUS.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\GET_QDM_FOCUS_STATUS.ps1)
3. w razie potrzeby zatrzymac sync:
   - [STOP_QDM_FOCUS_SYNC.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\STOP_QDM_FOCUS_SYNC.ps1)
4. wyeksportowac focus pack do `MT5`:
   - [EXPORT_QDM_FOCUS_PACK_TO_MT5.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\EXPORT_QDM_FOCUS_PACK_TO_MT5.ps1)
5. albo uruchomic caly tor `sync -> export`:
   - [RUN_QDM_FOCUS_PIPELINE.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\RUN_QDM_FOCUS_PIPELINE.ps1)
   - [START_QDM_FOCUS_PIPELINE_BACKGROUND.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_QDM_FOCUS_PIPELINE_BACKGROUND.ps1)
6. albo do aktywnego syncu dolaczyc sam eksport po zakonczeniu:
   - [WAIT_QDM_SYNC_AND_EXPORT.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\WAIT_QDM_SYNC_AND_EXPORT.ps1)
   - [START_QDM_EXPORT_AFTER_SYNC_BACKGROUND.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_QDM_EXPORT_AFTER_SYNC_BACKGROUND.ps1)
7. potem podpinac to do `Custom Symbols` i badan offline
