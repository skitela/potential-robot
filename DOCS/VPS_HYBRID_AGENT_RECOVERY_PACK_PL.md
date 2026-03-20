# VPS HybridAgent Recovery Pack

## Cel

Ten pakiet zbiera w jednej sciezce:

- walidacje lokalnego odpiecia `HybridAgent`,
- diagnoze `WinRM`,
- diagnoze kanalow zdalnych do VPS,
- najkrotsza droge do recznego odpiecia na serwerze.

## Jedna komenda

Uruchom:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\PREPARE_VPS_HYBRID_AGENT_RECOVERY.ps1
```

Skrypt:

1. potwierdza lokalne odpiecie `HybridAgent`,
2. testuje `WinRM auth`,
3. testuje kanaly `RDP`, `WinRM` i `SSH`,
4. zapisuje raport zbiorczy.

Raport:

- `C:\OANDA_MT5_SYSTEM\EVIDENCE\prepare_vps_hybrid_agent_recovery_report.json`

## Gdy WinRM nadal zwraca Access denied

To oznacza blocker autoryzacyjny, nie sieciowy.

Wtedy:

1. otworz `RDP`:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\RUN\CONNECT_VPS_RDP.ps1
```

2. po zalogowaniu na VPS uruchom:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\DETACH_HYBRID_AGENT_ON_VPS.ps1
```

3. od razu po tym uruchom walidacje:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\VALIDATE_HYBRID_AGENT_DETACHED_ON_VPS.ps1
```

4. jesli trzeba, napraw poświadczenia `RDP/WinRM`:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\reseal_vps_admin_dpapi_secret.ps1 -UsbLabel OANDAKEY -VpsHost 185.243.55.55 -VpsAdminLogin Administrator
```

5. ponow pelny pakiet recovery:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\PREPARE_VPS_HYBRID_AGENT_RECOVERY.ps1
```

## Powiazane pliki

- `C:\OANDA_MT5_SYSTEM\DOCS\HYBRID_AGENT_DETACH_RUNBOOK_PL.md`
- `C:\OANDA_MT5_SYSTEM\DOCS\VPS_WINRM_ACCESS_BLOCKER_PL.md`
- `C:\OANDA_MT5_SYSTEM\TOOLS\TEST_VPS_WINRM_AUTH.ps1`
- `C:\OANDA_MT5_SYSTEM\TOOLS\TEST_VPS_REMOTE_CHANNELS.ps1`
- `C:\OANDA_MT5_SYSTEM\TOOLS\DETACH_HYBRID_AGENT_ON_VPS.ps1`
- `C:\OANDA_MT5_SYSTEM\TOOLS\VALIDATE_HYBRID_AGENT_DETACHED_ON_VPS.ps1`
- `C:\OANDA_MT5_SYSTEM\RUN\CONNECT_VPS_RDP.ps1`

## Konkluzja

Ten pakiet nie udaje, ze zdalne odpiecie sie udalo.
Najpierw daje twarda diagnoze.
Jesli `WinRM` pozostaje zablokowany, prowadzi operatora najkrotsza sciezka do recznego wejscia na VPS i wykonania odpiecia.
