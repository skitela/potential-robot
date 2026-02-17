# OANDA TMS MT5 (Polska) - setup i podlaczenie systemu

Data opracowania: 2026-02-17

## 1) Co jest potwierdzone lokalnie na Twoim laptopie

Skrót:
- `C:\Users\Public\Desktop\OANDA TMS MT5 Terminal.lnk`

Cel skrótu (sprawdzone lokalnie):
- `C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe`

To jest poprawna sciezka zgodna z polityka runtime w tym repo (`REQUIRED_OANDA_MT5_EXE`).

## 2) Dane logowania, ktore musza byc zgodne

Wedlug pomocy OANDA TMS dla MT5:
- `Login` = numer rachunku MT5 z HUB
- `Password` = haslo rachunku
- `Server` = `OANDATMS-MT5` (dla kont live)

Zrodla:
- https://help.oanda.com/eu/pl/faqs/mt5-user-guide-eu.htm
- https://help.oanda.com/eu/pl/faqs/find-mt5-login.htm

## 3) Krok po kroku: konfiguracja MT5 desktop pod OANDA TMS

1. Otworz HUB i sprawdz login MT5:
   - https://hub.oanda.com (PL/EN link z pomocy OANDA)
   - Dashboard -> wybierz konto -> odczytaj "Your MT5 login".
2. Otworz terminal MT5 z desktopowego skrotu.
3. `File -> Login to Trade Account`.
4. Wpisz:
   - Login: numer rachunku MT5
   - Password: haslo rachunku
   - Server: `OANDATMS-MT5`
5. Jesli serwera nie widac:
   - `File -> Open an Account`
   - wybierz `OANDA TMS Brokers S.A`
   - `Connect with an existing trade account`
   - ponow login/haslo/server.
6. Potwierdz polaczenie:
   - dolny prawy rog MT5 ma aktywne paski lacznosci,
   - rachunek i instrumenty sa widoczne.

Zrodla:
- https://help.oanda.com/eu/pl/faqs/mt5-user-guide-eu.htm
- https://www.metatrader5.com/en/terminal/help/startworking/authorization

## 4) 2FA dla MT5 (wymagane, jesli aktywujesz)

W OANDA TMS dla MT5 to proces dwuetapowy:
1. W HUB wlacz `Two-Factor Authentication` dla sekcji MT5 Platform (SMS confirm).
2. Nastepnie aktywuj 2FA wewnatrz MT5 (desktop lub mobile binding).

Przy logowaniu do MT5 po aktywacji 2FA podajesz OTP.

Zrodla:
- https://help.oanda.com/eu/en/faqs/two-factor-authentication-2fa-eu.htm
- https://help.oanda.com/eu/pl/faqs/mt5-user-guide-eu.htm

## 5) Przygotowanie OANDAKEY (USB) pod nasz system - DPAPI

W repo jest juz gotowy workflow:
- skrypt: `RUN/PREPARE_OANDAKEY_USB.ps1`
- runbook: `RUN/OANDAKEY_USB_README.txt`

Domyslnie skrypt tworzy `TOKEN/BotKey.env` z haslem MT5 jako:
- `MT5_PASSWORD_DPAPI=...`
- tryb `DPAPI_CURRENT_USER` (zaszyfrowane i zwiazane z tym samym uzytkownikiem Windows/laptopem).

Uruchomienie:
```powershell
RUN\PREPARE_OANDAKEY_USB.cmd E
```
(`E` zamien na litere pendrive)

Bootstrap bez sekretow (login/haslo podasz dopiero przy pierwszym starcie):
```powershell
RUN\PREPARE_OANDAKEY_USB.cmd E bootstrap
```

Wymagane pola w `BotKey.env`:
- `MT5_LOGIN`
- `MT5_PASSWORD_DPAPI` (albo legacy `MT5_PASSWORD`)
- `MT5_SERVER=OANDATMS-MT5`
- `MT5_PATH=C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe`

## 6) Start systemu po przygotowaniu klucza

1. Wloz pendrive z etykieta woluminu `OANDAKEY`.
2. Upewnij sie, ze istnieje `TOKEN\BotKey.env`.
3. Start:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File RUN\START_WITH_OANDAKEY.ps1 -Root C:\OANDA_MT5_SYSTEM
```

## 7) Test techniczny polaczenia MT5 bez handlu

```powershell
python -B TOOLS\online_smoke_mt5.py --mt5-path "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe"
```

Raport:
- `EVIDENCE/online_smoke/<run_id>_mt5_smoke.json`

## 8) Uwaga dla automatyzacji Python/EA w MT5

Jesli pojawia sie blad typu brak zgody na handel z Python API:
- sprawdz `Tools -> Options -> Expert Advisors`
- opcja `Disable automatic trading through the external Python API` musi byc ustawiona zgodnie z Twoim trybem pracy.

Zrodlo:
- https://www.metatrader5.com/en/terminal/help/startworking/settings
- https://www.mql5.com/en/docs/python_metatrader5/mt5initialize_py
- https://www.mql5.com/en/docs/python_metatrader5/mt5login_py
