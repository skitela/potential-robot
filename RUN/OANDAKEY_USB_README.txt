OANDAKEY USB - szybki runbook
=================================

Cel:
- system startuje tylko, gdy jest podpiety pendrive z etykieta OANDAKEY
- pendrive musi miec plik: TOKEN\BotKey.env

Co jest teraz wdrozone:
1) start.bat -> RUN\START_WITH_OANDAKEY.ps1
2) pre-check etykiety OANDAKEY i pliku TOKEN\BotKey.env
3) dopiero po PASS uruchamiany jest TOOLS\SYSTEM_CONTROL.ps1 -Action start

Przygotowanie pendrive:
- uruchom:
  RUN\PREPARE_OANDAKEY_USB.cmd E
  (gdzie E to litera pendrive)

Skrypt przygotowania:
- ustawia etykiete woluminu na OANDAKEY
- tworzy TOKEN\BotKey.env
- tworzy launchery na pendrive:
  - START_OANDA_SYSTEM.cmd
  - START_OANDA_SYSTEM.ps1

Wazne:
- BotKey.env zawiera haslo MT5 i ma zostac tylko na pendrive
- nie kopiuj BotKey.env do repozytorium
- zalecane: wlacz BitLocker To Go dla pendrive
