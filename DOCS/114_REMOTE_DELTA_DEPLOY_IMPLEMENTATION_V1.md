# Remote Delta Deploy Implementation V1

## Co zostalo wdrozone

Dodano dwa nowe narzedzia:

- `TOOLS\DEPLOY_MT5_PACKAGE_TO_REMOTE.ps1`
- `TOOLS\COLLECT_REMOTE_MT5_RUNTIME_DIAGNOSTICS.ps1`

## Zakres deployu

Deploy zarzadza:

- `SERVER_PROFILE\PACKAGE\**`
- `CONFIG\*.json`
- `TOOLS\INSTALL_MT5_SERVER_PACKAGE.ps1`
- `TOOLS\VALIDATE_MT5_SERVER_INSTALL.ps1`

Wdrzazany jest tylko podzbior potrzebny do:

- instalacji pakietu na VPS
- walidacji instalacji
- utrzymania spojnosc konfiguracji

## Model synchronizacji

Domyslnie:

- porownanie hashy lokalnych i zdalnych plikow
- kopiowanie tylko zmienionych plikow
- opcjonalny prune tylko dla plikow zarzadzanych przez manifest

Nie ma domyslnego `wipe all`.

## Model diagnostyki

Snapshot runtime zbiera zdalne artefakty do lokalnego:

- `EVIDENCE\REMOTE_RUNTIME_SNAPSHOTS\<target>\<timestamp>`

To trzyma ciezsza diagnostyke poza hot-path.

## Ograniczenie tej rundy

Repo nie zawiera jawnego:

- `CONFIG\remote_deployment_targets.json`

dlatego realny push na VPS nie zostal wykonany w tej iteracji.

Kod i workflow sa gotowe, ale wymagaja uzupelnienia opisu targetu.
