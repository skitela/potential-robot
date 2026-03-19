# 142 QuantDataManager Install V1

## Cel
- zainstalowac `QuantDataManager` lokalnie na dysku `C:`
- przygotowac porzadny punkt startowy pod:
  - dane historyczne
  - eksport do `MT5`
  - dalsza warstwe badawcza offline

## Co zrobiono
### 1. Oficjalne pliki pobrane
Z oficjalnego kanału StrategyQuant pobrano:
- installer `QuantDataManager_setup.exe`
- archiwum `QDM_125_win_20251215.zip`

W praktyce do wdrozenia wybrano archiwum ZIP, bo:
- jest oficjalnie wspierane przez producenta
- nie wymaga klikania instalatora
- daje czysta, przewidywalna instalacje na wybranej sciezce

### 2. Instalacja na dysku C
Program zostal rozpakowany do:
- [C:\TRADING_TOOLS\QuantDataManager](C:\TRADING_TOOLS\QuantDataManager)

W tej lokalizacji znajduja sie m.in.:
- [QuantDataManager.exe](C:\TRADING_TOOLS\QuantDataManager\QuantDataManager.exe)
- [QDataManager_nocheck.exe](C:\TRADING_TOOLS\QuantDataManager\QDataManager_nocheck.exe)
- [qdmcli.exe](C:\TRADING_TOOLS\QuantDataManager\qdmcli.exe)

### 3. Katalogi danych
Przygotowano tez katalogi robocze na `C:`:
- [C:\TRADING_DATA\QDM](C:\TRADING_DATA\QDM)
- [C:\TRADING_DATA\QDM_EXPORT\MT5](C:\TRADING_DATA\QDM_EXPORT\MT5)

Uwaga praktyczna:
bieżąca wersja ZIP trzyma swoje dane i ustawienia w:
- [C:\TRADING_TOOLS\QuantDataManager\user](C:\TRADING_TOOLS\QuantDataManager\user)

To jest normalne zachowanie portable ZIP od producenta.

### 4. Weryfikacja uruchomienia
Program uruchamia sie poprawnie z lokalizacji `C:`.
Na tym etapie zatrzymuje sie na sprawdzeniu licencji:
- `Exit app - Failed to check license.`

To nie jest blad instalacji.
To oznacza, ze fizyczna instalacja jest gotowa, ale trzeba jeszcze:
- zalogowac sie
  albo
- aktywowac licencje `Free` / `Pro`

## Co zostalo dodane do projektu
Dodano launcher:
- [OPEN_QUANT_DATA_MANAGER.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\OPEN_QUANT_DATA_MANAGER.ps1)

Jego rola:
- otwierac `QDM` z wlasciwej sciezki
- bez szukania exe recznie po dysku

## Co jest gotowe na teraz
- instalacja na `C:`: gotowa
- katalogi danych: gotowe
- launcher: gotowy
- etap platnosci / aktywacji: pozostaje po stronie uzytkownika

## Zalecenia
1. Nie instalowac `QDM` na `D:`
   - `D:` ma za malo miejsca
   - i jest `exFAT`
2. Trzymac `QDM` i jego glowne dane na `C:`
3. Po aktywacji licencji od razu ustawic workflow eksportu do:
   - [C:\TRADING_DATA\QDM_EXPORT\MT5](C:\TRADING_DATA\QDM_EXPORT\MT5)
4. Nie mieszac danych `QDM` z aktywnym runtime `MAKRO_I_MIKRO_BOT`

## Następny sensowny krok
Po aktywacji:
1. uruchomic `QDM`
2. skonfigurowac pierwsze pobieranie danych
3. zrobic pierwszy eksport dla jednego instrumentu testowego
4. sprawdzic import do `MT5 Custom Symbols`
