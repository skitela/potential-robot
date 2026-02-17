OANDAKEY USB - szybki runbook
=================================

Cel:
- system startuje tylko, gdy jest podpiety pendrive z etykieta OANDAKEY
- pendrive musi miec plik: TOKEN\BotKey.env

Co jest teraz wdrozone:
1) start.bat -> RUN\START_WITH_OANDAKEY.ps1
2) pre-check etykiety OANDAKEY, formatu pendrive i pliku TOKEN\BotKey.env
3) dopiero po PASS uruchamiany jest TOOLS\SYSTEM_CONTROL.ps1 -Action start
4) gdy pendrive nie ma etykiety, a jest jedyny w USB: etykieta jest nadawana automatycznie jako OANDAKEY
5) przy pierwszym starcie (brak loginu/hasla): skrypt pyta o MT5_LOGIN i MT5_PASSWORD i zapisuje haslo jako DPAPI

Przygotowanie pendrive:
- uruchom:
  RUN\PREPARE_OANDAKEY_USB.cmd E
  (gdzie E to litera pendrive)

Przygotowanie bez podawania sekretow (bootstrap):
- uruchom:
  powershell -NoProfile -ExecutionPolicy Bypass -File RUN\PREPARE_OANDAKEY_USB.ps1 -DriveLetter E -BootstrapOnly
- alternatywnie:
  RUN\PREPARE_OANDAKEY_USB.cmd E bootstrap
- skrypt tworzy szablon TOKEN\BotKey.env; login/haslo podasz dopiero przy pierwszym starcie

Skrypt przygotowania:
- ustawia etykiete woluminu na OANDAKEY
- sprawdza format pendrive (wymagane: NTFS/FAT32/exFAT)
- tworzy TOKEN\BotKey.env
- tworzy launchery na pendrive:
  - START_OANDA_SYSTEM.cmd
  - START_OANDA_SYSTEM.ps1

Szyfrowanie hasla MT5:
- domyslnie `RUN\PREPARE_OANDAKEY_USB.ps1` zapisuje haslo jako `MT5_PASSWORD_DPAPI`
- jest to DPAPI (`CurrentUser`), czyli odczyt dziala tylko na tym samym laptopie i koncie Windows
- kompatybilnosc wsteczna zostaje: `BIN/safetybot.py` dalej obsluguje stary wpis `MT5_PASSWORD=...`
- tryb awaryjny plaintext (niezalecany): uruchom skrypt z `-PlaintextPassword`

Wazne:
- BotKey.env zawiera haslo MT5 i ma zostac tylko na pendrive
- nie kopiuj BotKey.env do repozytorium
- zalecane: wlacz BitLocker To Go dla pendrive
