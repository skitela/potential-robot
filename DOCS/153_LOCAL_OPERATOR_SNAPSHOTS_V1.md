# 153 Local Operator Snapshots V1

## Cel

Przeniesc podstawowa kontrole laboratorium z rozmowy do lokalnych snapshotow na dysku.

Chodzi o to, zeby rutyna typu:

- czy lab zyje,
- jaki jest ostatni status testera,
- jakie sa ostatnie metryki ML,
- ile danych siedzi juz w `QDM`,
- jaki jest stan pagefile,

zapisywala sie automatycznie lokalnie, bez pytania AI.

## Co dodano

- [SAVE_LOCAL_OPERATOR_SNAPSHOT.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\SAVE_LOCAL_OPERATOR_SNAPSHOT.ps1)
- [START_LOCAL_OPERATOR_ARCHIVER_BACKGROUND.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_LOCAL_OPERATOR_ARCHIVER_BACKGROUND.ps1)

## Gdzie laduja snapshoty

- `C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\local_operator_snapshot_latest.json`
- `C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\local_operator_snapshot_latest.md`
- oraz wersje timestampowane obok

## Co zawiera snapshot

- wynik `GET_LOCAL_OPERATOR_SUMMARY.ps1`
- wynik `GET_FX_LAB_STATUS.ps1`
- footprint historii `QDM`
- stan pagefile

## Integracja

Archiver jest dopiety do:

- [START_FX_LAB_3_WINDOWS.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_FX_LAB_3_WINDOWS.ps1)
- [START_PARALLEL_90P_LAB.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_PARALLEL_90P_LAB.ps1)

To znaczy:

- po starcie labu snapshoty zaczynaja same splywac na dysk,
- lokalna operatywka nie musi juz przechodzic przez rozmowe,
- AI zostaje do interpretacji, zmian i decyzji.
