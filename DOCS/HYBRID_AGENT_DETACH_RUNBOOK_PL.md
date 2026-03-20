# HybridAgent Detach Runbook

## Cel

Ten dokument opisuje bezpieczne odpiecie `HybridAgent`:

- lokalnie na laptopie,
- oraz recznie na `Windows VPS`, jesli zdalny `WinRM` jest zablokowany.

## Ustalony serwer docelowy

Na podstawie pakietu `EURUSD`:

- `target_server_name`: `VPS Warsaw 01`
- `target_server_id`: `#260303_1940`
- broker/terminal MT5: `OANDATMS-MT5`
- referencyjny root `EURUSD` na VPS: `C:\GH_EURUSD`

## Co juz zostalo wykonane lokalnie

- `SYSTEM_CONTROL` ustawiono na `STOPPED`
- aktywny `HybridAgent` zostal zdjety z lokalnych katalogow `MT5`
- pliki zostaly przeniesione do `DETACHED_HYBRID_AGENT`

Raport:

- `C:\OANDA_MT5_SYSTEM\EVIDENCE\detach_hybrid_agent_local_and_vps_report.json`
- `C:\OANDA_MT5_SYSTEM\EVIDENCE\prepare_vps_hybrid_agent_recovery_report.json`

Walidacja lokalna:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\VALIDATE_HYBRID_AGENT_DETACHED_LOCAL.ps1
```

## Dlaczego VPS nie zostal odparty automatycznie

Port `5985` odpowiada, ale `New-PSSession` do `185.243.55.55` zwraca:

- `Access denied`

To oznacza blocker po stronie autoryzacji `WinRM`, nie po stronie sieci.

Szczegoly i test:

- `C:\OANDA_MT5_SYSTEM\DOCS\VPS_WINRM_ACCESS_BLOCKER_PL.md`
- `C:\OANDA_MT5_SYSTEM\TOOLS\TEST_VPS_WINRM_AUTH.ps1`
- `C:\OANDA_MT5_SYSTEM\TOOLS\PREPARE_VPS_HYBRID_AGENT_RECOVERY.ps1`

## Reczne odpiecie na VPS

1. Wejdz na VPS przez:
   - `RDP`
   - albo `VNC`

2. Na VPS uruchom:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\DETACH_HYBRID_AGENT_ON_VPS.ps1
```

3. Skrypt:
   - zatrzyma `SYSTEM_CONTROL` w profilu `safety_only`,
   - zamknie `terminal64.exe`,
   - przeniesie `HybridAgent.mq5` i `HybridAgent.ex5` do `DETACHED_HYBRID_AGENT`

4. Zaraz po odpieciu uruchom walidacje na VPS:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\VALIDATE_HYBRID_AGENT_DETACHED_ON_VPS.ps1
```

## Po recznym odpieciu na VPS

Na VPS sprawdz:

- brak `HybridAgent.mq5` w aktywnym `MQL5\Experts`
- brak `HybridAgent.ex5` w aktywnym `MQL5\Experts`
- obecność folderu `DETACHED_HYBRID_AGENT`
- raport:
  - `C:\OANDA_MT5_SYSTEM\EVIDENCE\validate_hybrid_agent_detached_on_vps_report.json`

## Konkluzja

Lokalny etap jest wykonany.
Zdalny etap jest przygotowany, ale wymaga wejscia na VPS z poprawnymi poświadczeniami.
Najszybsza diagnoza calej sytuacji jest w:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\PREPARE_VPS_HYBRID_AGENT_RECOVERY.ps1
```
