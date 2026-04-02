# Remote MT5 Install

## Cel

Ten dokument opisuje, jak rozlozyc `PACKAGE` na docelowym serwerze `MT5-only`.

## Wejscia

Potrzebne sa:

- `SERVER_PROFILE\PACKAGE`
- `SERVER_PROFILE\HANDOFF`
- albo odpowiadajace im ZIP-y z `BACKUP`

## Krok 1

Na komputerze docelowym wybierz katalog danych terminala `MT5`.

To ma byc katalog typu:

- `...\\MetaQuotes\\Terminal\\<instance>`

## Krok 1A

Najwazniejsze rozroznienie sciezek:

- sciezka instalacyjna `MT5`, np. `C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe`, nie jest `TargetTerminalDataDir`
- `TargetTerminalDataDir` to katalog danych pod `AppData\Roaming\MetaQuotes\Terminal\<instance>`
- `TargetCommonFilesDir` to osobny wspoldzielony katalog `AppData\Roaming\MetaQuotes\Terminal\Common\Files`
- zgodnie z dokumentacja MetaQuotes prawidlowe sciezki mozna potwierdzic przez `File -> Open Data Folder` albo z kodu MQL5 przez `TerminalInfoString(TERMINAL_DATA_PATH)` i `TerminalInfoString(TERMINAL_COMMONDATA_PATH)`
- baza symboli i `Market Watch` dla konkretnego serwera zyja pod `bases\OANDATMS-MT5\symbols`, w plikach `selected-*.dat` oraz `symbols-*.dat`

## Krok 2

Uruchom instalator pakietu:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\INSTALL_MT5_SERVER_PACKAGE.ps1 -TargetTerminalDataDir "<MT5_DATA_DIR>" -TargetCommonFilesDir "<COMMON_FILES_DIR>" -CreateRuntimeFolders
```

Instalator rozklada kod i presety do `TargetTerminalDataDir`, a runtime do `TargetCommonFilesDir`. Skrypt czysci stale pliki zarzadzane w `MQL5\Experts\MicroBots`, `MQL5\Include\Profiles`, `MQL5\Include\Strategies`, `MQL5\Presets` i `MQL5\Presets\ActiveLive` zgodnie z aktualnym registry, wiec nie trzymaj tam recznych dodatkow spoza aktywnej floty.

## Krok 3

Zweryfikuj wynik:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\VALIDATE_MT5_SERVER_INSTALL.ps1 -TargetTerminalDataDir "<MT5_DATA_DIR>" -TargetCommonFilesDir "<COMMON_FILES_DIR>"
```

Raport musi dawac `ok=true`.

## Krok 3A

Przy walidacji trzymaj sie jednej mapy nazw:

- `broker_symbol` sluzy do wykresu i `Market Watch`
- `code_symbol` sluzy do nazw plikow `Profile_*.mqh`, `Strategy_*.mqh` i `MicroBot_*`
- `state_alias` sluzy do katalogu runtime w `Common\Files`
- `ActiveLive` preset jest wymagany tylko dla symboli z `paper_live_first_wave`

Szczegolnie pilnuj wyjatku `COPPER-US` -> `COPPERUS` -> `COPPER-US.pro`.

## Krok 4

Skorzystaj z pakietu operatorskiego `HANDOFF`:

- chart plan
- rollout checklist
- readiness reports
- preset safety reports
- baseline status report dla `MT5 pretrade/execution truth`

## Krok 4A

Po attach i pierwszym heartbeat sprawdz w katalogu Common Files:

- `...\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\spool\pretrade_truth`
- `...\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\spool\execution_truth`

Jesli nie pojawiaja sie swieze CSV albo czas modyfikacji stoi, truth pozostaje dormant i rollout parity nie jest jeszcze domkniete.

## Krok 4B

Po instalacji sprawdz takze w `MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\state\<state_alias>`:

- `runtime_control.csv`
- `runtime_status.json`
- `student_gate_contract.csv`
- `teacher_package_contract.csv`
- `broker_profile.json`

Brak `teacher_package_contract.csv` oznacza luke deploymentowa, a nie tylko brak raportu pomocniczego.

## Krok 4C

Jesli docelowym runtime jest `MetaTrader VPS`, obowiazuja dodatkowe ograniczenia MetaQuotes:

- sync jest jednokierunkowy z terminala lokalnego do `VPS`
- nie ma automatycznego odswiezania po zmianach w repo ani po zmianach na wykresach
- migruja tylko wykresy z przypietym `EA`
- limit to `32` wykresy z `EA` na hostingu platnym i `16` na darmowym
- skrypty nie sa przenoszone
- wykresy z custom symbols i niestandardowymi timeframe'ami nie sa przenoszone
- pierwszy sync wysyla historie dla wszystkich otwartych wykresow
- `Algo Trading` jest zawsze wlaczone na terminalu wirtualnym
- wywolania `DLL` sa zabronione

## Krok 5

Jesli trzeba, skompiluj eksperta bezposrednio w docelowym terminalu przez:

- `TOOLS\COMPILE_MICROBOT.ps1`

Sama kompilacja nie wystarcza. Po kompilacji `ex5` musi pojawic sie w `TargetTerminalDataDir\MQL5\Experts\MicroBots` i przejsc audit deploymentowy.

## Krok 6

Po stronie projektu lokalnego mozna wczesniej wykonac symulacje instalacji:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\SIMULATE_MT5_SERVER_INSTALL.ps1
```

To tworzy testowy katalog `SERVER_PROFILE\REMOTE_SIM` i potwierdza, ze pakiet da sie rozlozyc.

## Krok 6A

Jesli masz `PSRemoting` do zdalnej maszyny Windows, lepsza od recznego kopiowania jest automatyczna propagacja przez:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\DEPLOY_MT5_PACKAGE_TO_REMOTE.ps1 -RunPrepareRollout -PruneStaleManagedFiles
```

Ten tryb wymaga uzupelnienia `CONFIG\remote_deployment_targets.json`, ale daje lepszy kontrakt operacyjny niz reczne ZIP-y:

- wymusza jawny `remote_terminal_data_dir`
- wymusza jawny `remote_common_files_dir`
- kopiuje tylko zmienione pliki po hashach
- moze przyciac stale pliki zarzadzane
- potrafi uruchomic zdalne `install` i `validate`

Reczny `HANDOFF` pozostaje fallbackiem, nie standardem preferowanym.

## Znane Kruczki 2026-04-01

- aktywna instancja lokalna miala brak `MicroBot_AUDUSD.ex5`
- `teacher_package_contract.csv` brakowal dla `12/13` symboli
- audit metadata potwierdzil obecne `broker_profile.json` dla wszystkich `13` symboli, ale profile repo nadal nie importuja limitow wolumenu, kontraktu tickowego i poziomow stop/freeze
- presety `ActiveLive` powinny istniec tylko dla `paper_live_first_wave`; ich brak dla reszty nie jest bledem walidacji

## Konkluzja

Docelowy przeplyw to:

- `PACKAGE` rozklada kod i presety do katalogu danych `MT5`
- `Common Files` przechowuje runtime i dowody heartbeat/truth
- `HANDOFF` dostarcza operatorowi komplet decyzji i raportow
- `DEPLOY_MT5_PACKAGE_TO_REMOTE.ps1` jest preferowana droga, gdy masz stabilny dostep zdalny i chcesz uniknac recznego dryfu
