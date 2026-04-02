RUN

Ten katalog jest przeznaczony na skrypty uruchomieniowe i pomocnicze wrappery:

- lokalny compile/deploy
- eksport paczki serwerowej
- szybkie walidatory katalogow
- operatorski preflight rolloutowy
- panel operatorski i dashboardy po polsku

Na etapie bootstrapu logika runtime pozostaje w MQL5.

Najprostsze uruchomienie dla operatora:

- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\URUCHOM_PANEL_I_DASHBOARD.ps1`

Ten launcher:

- otwiera natywne okno `Panel operatora`
- otwiera `dashboard dzienny`
- otwiera `dashboard wieczorny`

Dodatkowe launchery operatorskie:

- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\URUCHOM_TYLKO_PANEL.ps1`
- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\URUCHOM_TYLKO_DASHBOARDY.ps1`
- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\OTWORZ_DASHBOARD_DZIENNY.ps1`
- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\OTWORZ_RAPORT_WIECZORNY.ps1`
- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\URUCHOM_MT5_PANEL_I_DASHBOARD.ps1`
- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\UTWORZ_SKROTY_NA_PULPICIE.ps1`

Wersje do zwyklego dwukliku:

- `C:\MAKRO_I_MIKRO_BOT\RUN\START_OPERATOR.bat`
- `C:\MAKRO_I_MIKRO_BOT\RUN\START_TYLKO_PANEL.bat`
- `C:\MAKRO_I_MIKRO_BOT\RUN\START_TYLKO_DASHBOARDY.bat`
- `C:\MAKRO_I_MIKRO_BOT\RUN\START_DASHBOARD_DZIENNY.bat`
- `C:\MAKRO_I_MIKRO_BOT\RUN\START_RAPORT_WIECZORNY.bat`
- `C:\MAKRO_I_MIKRO_BOT\RUN\START_MT5_PANEL_I_DASHBOARD.bat`

Przeznaczenie:

- `URUCHOM_TYLKO_PANEL.ps1` otwiera tylko natywne okno operatora
- `URUCHOM_TYLKO_DASHBOARDY.ps1` otwiera tylko oba dashboardy HTML
- `OTWORZ_DASHBOARD_DZIENNY.ps1` otwiera tylko dashboard dzienny
- `OTWORZ_RAPORT_WIECZORNY.ps1` otwiera tylko raport wieczorny
- `URUCHOM_MT5_PANEL_I_DASHBOARD.ps1` uruchamia `OANDA MT5`, a potem panel i dashboardy
- `UTWORZ_SKROTY_NA_PULPICIE.ps1` tworzy na pulpicie Windows skroty do panelu, dashboardow i startu `OANDA MT5`
- odpowiadajace im pliki `.bat` robia to samo, ale sa wygodne do dwukliku w Windows
- po uruchomieniu skryptu tworzenia skrotow te same wejscia sa dostepne tez bezposrednio z pulpitu Windows

Pozostale najwazniejsze skróty:

- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\PANEL_OPERATORA_PL.ps1`
- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\WLACZ_TRYB_NORMALNY_SYSTEMU.ps1`
- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\WLACZ_CLOSE_ONLY_SYSTEMU.ps1`
- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\ZATRZYMAJ_SYSTEM.ps1`
- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\SPRAWDZ_I_NAPRAW_SYSTEM.ps1`
- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\OPEN_OANDA_MT5_WITH_MICROBOTS.ps1`

Rekomendowany preflight rollout:

- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\PREPARE_MT5_ROLLOUT.ps1`

Ten wrapper:

- synchronizuje tokeny `kill-switch`,
- kompiluje cala aktywna flote `13`,
- waliduje uklad projektu,
- waliduje bezpieczenstwo presetow,
- waliduje gotowosc wdrozenia,
- regeneruje chart plan,
- eksportuje paczke serwerowa,
- eksportuje pakiet operatorski `HANDOFF`,
- waliduje komplet transferowy `PACKAGE + HANDOFF`,
- symuluje instalacje pakietu na testowym katalogu `MT5`,
- zapisuje ZIP backup projektu,
- zapisuje osobny ZIP `HANDOFF`.

Wazne przy `MetaTrader VPS`:

- synchronizacja jest jednokierunkowa lokalny terminal -> `VPS`; brak auto-resyncu po zmianach w repo
- migruja tylko wykresy z przypietym `EA`; skrypty nie sa przenoszone

Po stronie docelowego serwera mozna potem uzyc:

- `TOOLS\INSTALL_MT5_SERVER_PACKAGE.ps1`
- `TOOLS\VALIDATE_MT5_SERVER_INSTALL.ps1`

Przygotowanie wspolnej paczki do bezpiecznej propagacji z bota wzorcowego:

- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\PREPARE_SHARED_PROPAGATION_PACKAGE.ps1`
- `powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\VALIDATE_PROPAGATION_PACKAGE.ps1`
