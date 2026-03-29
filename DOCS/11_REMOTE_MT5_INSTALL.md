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

## Krok 2

Uruchom instalator pakietu:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\INSTALL_MT5_SERVER_PACKAGE.ps1 -TargetTerminalDataDir "<MT5_DATA_DIR>" -CreateRuntimeFolders
```

## Krok 3

Zweryfikuj wynik:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\VALIDATE_MT5_SERVER_INSTALL.ps1 -TargetTerminalDataDir "<MT5_DATA_DIR>"
```

Raport musi dawac `ok=true`.

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

## Krok 5

Jesli trzeba, skompiluj eksperta bezposrednio w docelowym terminalu przez:

- `TOOLS\COMPILE_MICROBOT.ps1`

## Krok 6

Po stronie projektu lokalnego mozna wczesniej wykonac symulacje instalacji:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\SIMULATE_MT5_SERVER_INSTALL.ps1
```

To tworzy testowy katalog `SERVER_PROFILE\REMOTE_SIM` i potwierdza, ze pakiet da sie rozlozyc.

## Konkluzja

Docelowy przeplyw to:

- `PACKAGE` rozklada kod i presety do katalogu danych `MT5`
- `HANDOFF` dostarcza operatorowi komplet decyzji i raportow
