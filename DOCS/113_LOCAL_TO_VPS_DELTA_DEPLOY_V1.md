# Local To VPS Delta Deploy V1

## Cel

Ten etap domyka dojrzaly workflow:

- lokalnie rozwijamy, czyscimy i walidujemy kod
- na VPS uruchamiamy runtime paper/shadow
- z VPS zbieramy prawde operacyjna
- wnioski wracaja lokalnie do kolejnej iteracji

To nie zastepuje lokalnego developmentu.
To przenosi runtime i diagnostyke do srodowiska blizszego docelowemu live.

## Nowe narzedzia

- `TOOLS\DEPLOY_MT5_PACKAGE_TO_REMOTE.ps1`
- `TOOLS\COLLECT_REMOTE_MT5_RUNTIME_DIAGNOSTICS.ps1`

## Zasada deploymentu

Domyslny model to:

1. lokalny export `SERVER_PROFILE\PACKAGE`
2. roznicowy deploy tylko zmienionych plikow na VPS
3. opcjonalne usuniecie tylko starych plikow zarzadzanych przez manifest
4. zdalny install pakietu do katalogu danych `MT5`
5. zdalna walidacja
6. lokalne pobranie diagnostyki runtime z VPS

Nie czyscimy calego VPS przy kazdym wdrozeniu.
Pelny clean deploy ma byc wyjatkiem, nie standardem.

## Konfiguracja targetu

Utworz:

- `CONFIG\remote_deployment_targets.json`

na podstawie:

- `CONFIG\remote_deployment_targets.example.json`

Minimalne pola:

- `computer_name` albo `connection_uri`
- `remote_project_root`
- `remote_terminal_data_dir`
- `remote_common_files_dir`

## Przykladowy deploy

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\DEPLOY_MT5_PACKAGE_TO_REMOTE.ps1 `
  -TargetName VPS_PRIMARY `
  -CreateRuntimeFolders:$true `
  -PruneStaleManagedFiles
```

Jesli chcesz puscic pelny lokalny preflight przed deployem:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\DEPLOY_MT5_PACKAGE_TO_REMOTE.ps1 `
  -TargetName VPS_PRIMARY `
  -RunPrepareRollout `
  -CreateRuntimeFolders:$true `
  -PruneStaleManagedFiles
```

## Przykladowe pobranie diagnostyki

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\COLLECT_REMOTE_MT5_RUNTIME_DIAGNOSTICS.ps1 `
  -TargetName VPS_PRIMARY
```

Snapshot trafia do:

- `EVIDENCE\REMOTE_RUNTIME_SNAPSHOTS\<target>\<timestamp>`

## Co zbieramy z VPS

Z katalogu projektu:

- `install_mt5_server_package_report.*`
- `validate_mt5_server_install_report.*`

Z `Common\Files\MAKRO_I_MIKRO_BOT`:

- `broker_profile.json`
- `execution_summary.json`
- `informational_policy.json`
- `paper_position.csv`
- `tuning_experiments.csv`
- `tuning_reasoning.csv`
- `tuning_deckhand.csv`
- `decision_events.csv`
- `latency_profile.csv`
- wybrane pliki globalne

## Zasady bezpieczenstwa

### Domyslnie

- deploy roznicowy
- bez kasowania calego VPS
- prune tylko w ramach plikow zarzadzanych przez manifest
- walidacja po instalacji jest obowiazkowa

### Clean deploy tylko gdy

- schemat runtime zostal twardo zmieniony
- manifest zarzadzanych plikow jest niespojny
- stare runtime artifacts zanieczyszczaja interpretacje
- instalacja po stronie VPS jest uszkodzona

### Czego nie nadpisywac bez potrzeby

- niezarzadzanych folderow operatorskich
- recznych artefaktow administracyjnych na VPS
- calego `Common\Files`, jesli problem dotyczy tylko wybranego podzbioru

## Co to daje

- runtime w srodowisku blizszym docelowemu VPS
- bardziej reprezentatywne `execution_quality`
- bardziej uczciwe `cost_pressure`
- lepsza diagnostyke latencji i tikow
- mniej zgadywania, czy problem lezy w kodzie lokalnym czy w srodowisku wykonania

## Konkluzja

Model docelowy brzmi:

- lokalnie budujemy i walidujemy
- na VPS uruchamiamy i obserwujemy
- evidence wraca lokalnie
- poprawki znow sa robione lokalnie

To jest naturalny nastepny etap dojrzewania systemu.
