# VPS WinRM Access Blocker

## Stan

Aktualny stan z tego komputera:

- `TCP 5985` do VPS odpowiada
- `New-PSSession` zwraca `Access denied`

To oznacza:

- lacznosc sieciowa jest,
- poświadczenia albo polityka `WinRM` po stronie VPS sa nieaktualne lub odrzucone.

## Co juz jest wykonane

Lokalnie:

- `HybridAgent` jest odpięty
- `SYSTEM_CONTROL` jest w `STOPPED`
- lokalne katalogi `MT5` nie maja aktywnego `HybridAgent`

## Jak sprawdzic blocker

Uruchom:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\TEST_VPS_WINRM_AUTH.ps1
```

Raport:

- `C:\OANDA_MT5_SYSTEM\EVIDENCE\test_vps_winrm_auth_report.json`
- `C:\OANDA_MT5_SYSTEM\EVIDENCE\prepare_vps_hybrid_agent_recovery_report.json`

## Jak odblokowac

Najkrotsza droga:

1. Wejdz na VPS przez `RDP` albo `VNC`
2. Zweryfikuj konto `Administrator`
3. W razie potrzeby ustaw nowe haslo:

```powershell
net user Administrator "NOWE_HASLO"
```

4. Na laptopie przepisz sekret DPAPI:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\reseal_vps_admin_dpapi_secret.ps1 -UsbLabel OANDAKEY -VpsHost 185.243.55.55 -VpsAdminLogin Administrator
```

5. Ponow test:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\TEST_VPS_WINRM_AUTH.ps1
```

## Po odzyskaniu dostepu

Wtedy uruchom na VPS:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\DETACH_HYBRID_AGENT_ON_VPS.ps1
```

## Konkluzja

To nie jest blocker sieciowy.
To jest blocker autoryzacyjny `WinRM`.
Najkrotszy zestaw diagnostyczny:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\PREPARE_VPS_HYBRID_AGENT_RECOVERY.ps1
```
