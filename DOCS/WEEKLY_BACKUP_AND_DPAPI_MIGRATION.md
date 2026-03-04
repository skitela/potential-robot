# Weekly Backup + DPAPI Migration

## Cel
- Pelny backup systemu raz w tygodniu (preferowana noc z soboty na niedziele).
- Catch-up: jesli komputer byl wylaczony, backup wykona sie kolejnej nocy, gdy komputer jest wlaczony.
- Bez wpisywania sekretow do repo.

## Co backupuje narzedzie
- Folder systemu: `C:\OANDA_MT5_SYSTEM` -> `oanda_mt5_system.zip`
- Folder LAB: `C:\OANDA_MT5_LAB_DATA` -> `oanda_mt5_lab_data.zip` (jesli istnieje)
- Domyslnie **bez** kopiowania `TOKEN/BotKey.env` do archiwum.

Backupy zapisuja sie domyslnie do:
- `C:\OANDA_MT5_BACKUPS\weekly_backup_<UTC_STAMP>\...`

Raporty:
- `EVIDENCE/backups/weekly_backup_<UTC_STAMP>.json`
- `EVIDENCE/backups/weekly_backup_latest.json`
- Stan harmonogramu backupu:
  - `RUN/weekly_backup_state.json`

## Reczne uruchomienie backupu
```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\run_weekly_backup.ps1 `
  -Root C:\OANDA_MT5_SYSTEM `
  -LabDataRoot C:\OANDA_MT5_LAB_DATA `
  -BackupRoot C:\OANDA_MT5_BACKUPS `
  -PreferredWeekday sunday `
  -MaxDaysWithoutBackup 7
```

Wymuszenie backupu:
```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\run_weekly_backup.ps1 -Force
```

## Rejestracja zadania harmonogramu (user-level)
```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\register_weekly_backup_task_user.ps1 `
  -Root C:\OANDA_MT5_SYSTEM `
  -LabDataRoot C:\OANDA_MT5_LAB_DATA `
  -BackupRoot C:\OANDA_MT5_BACKUPS `
  -TaskName OANDA_MT5_WEEKLY_BACKUP `
  -StartTime 03:30 `
  -PreferredWeekday sunday `
  -MaxDaysWithoutBackup 7
```

Usuniecie zadania:
```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\unregister_weekly_backup_task.ps1 `
  -TaskName OANDA_MT5_WEEKLY_BACKUP
```

## DPAPI i przeniesienie na inny komputer
`MT5_PASSWORD_MODE=DPAPI_CURRENT_USER` oznacza:
- haslo jest zaszyfrowane i zwiazane z aktualnym uzytkownikiem Windows / maszyna.
- po przeniesieniu systemu na inny komputer trzeba ponownie zaszyfrowac haslo na nowym komputerze.

Do tego sluzy:
```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\reseal_mt5_dpapi_secret.ps1 -UsbLabel OANDAKEY
```

Skrypt:
- zrobi backup `BotKey.env`,
- poprosi o haslo MT5,
- zapisze nowe `MT5_PASSWORD_DPAPI` w trybie `DPAPI_CURRENT_USER`.

## Uwagi bezpieczenstwa
- Nie zapisuj jawnego hasla MT5 (`MT5_PASSWORD=`) jesli nie musisz.
- Trzymaj `TOKEN/BotKey.env` na dedykowanym woluminie i nie commituj go do repo.
- Backupy kodu i danych runtime synchronizuj osobno od sekretow.

