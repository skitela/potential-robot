# Migracja Na Windows VPS

## Cel
- przenieść system na `Windows VPS` bez mieszania tego kroku z dużym refaktorem hot-path,
- najpierw uruchomić system na serwerze w stanie zgodnym z obecnym repo,
- dopiero po stabilnym starcie mierzyć opóźnienia i odchudzać `SafetyBot`.

To jest ważne:
- nie przenosimy teraz logiki z `Python` do `MQL5` na ślepo,
- najpierw robimy stabilne uruchomienie na VPS,
- potem mierzymy zysk z samej migracji,
- dopiero później decydujemy, co naprawdę warto wynieść bliżej `MQL5`.

## Co jest już gotowe lokalnie
- pakiet migracyjny kodu: `C:\OANDA_MT5_SYSTEM\EVIDENCE\vps_prep\vps_bundle_latest.txt`
- test łączności do VPS: `C:\OANDA_MT5_SYSTEM\EVIDENCE\vps_prep\vps_preflight_20260307T082444Z.txt`

Aktualny stan łączności:
- `RDP 3389` jest otwarte,
- `WinRM 5985` jest otwarte.

## Czego potrzebujesz
- dostępu do panelu `cyberfolks`,
- wejścia do `VNC`,
- hasła do `Administrator` na Windows VPS,
- pendrive `OANDAKEY`, żeby po zmianie hasła zapisać nowy sekret przez `DPAPI`.

## Zasada migracji
Najpierw:
1. wejście na VPS,
2. uruchomienie `RDP`,
3. zmiana hasła `Administrator`,
4. zapis nowego hasła na pendrive,
5. dopiero potem przeniesienie kodu i uruchomienie systemu.

## Jak wejść na VPS przez VNC
1. Zaloguj się do panelu `cyberfolks`.
2. Wejdź do VPS i otwórz `VNC`.
3. Zaloguj się jako:
   - użytkownik: `Administrator`
   - hasło: aktualne hasło Windows VPS

## Jak włączyć RDP na VPS
Na samym VPS, już po wejściu przez `VNC`:

1. Otwórz `PowerShell` jako administrator.
2. Uruchom:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\vps_enable_rdp.ps1
```

Jeśli katalog `C:\OANDA_MT5_SYSTEM` nie istnieje jeszcze na VPS, najpierw wklej sam skrypt albo uruchom ręcznie:

```powershell
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'
Set-Service -Name TermService -StartupType Automatic
Start-Service -Name TermService
```

## Jak uruchomić RDP z laptopa
Na laptopie:

1. Naciśnij `Win + R`
2. Wpisz:

```text
mstsc
```

3. Kliknij `Pokaż opcje`
4. W polu `Komputer` wpisz:

```text
185.243.55.55
```

5. Jeśli chcesz kopiować pliki z laptopa na VPS:
   - zakładka `Zasoby lokalne`
   - kliknij `Więcej`
   - zaznacz dysk lokalny z którego chcesz kopiować pliki
6. Kliknij `Połącz`
7. Zaloguj się jako:
   - użytkownik: `Administrator`
   - hasło: hasło Windows VPS

Po połączeniu przez RDP lokalne dyski będą widoczne na VPS jako:

```text
\\tsclient\C
```

albo odpowiednio inna litera dysku.

## Jak zmienić hasło Administrator na VPS
Na VPS, w `PowerShell` uruchomionym jako administrator:

```powershell
net user Administrator "NOWE_MOCNE_HASLO"
```

To zmienia hasło tylko dla konta `Administrator` na serwerze VPS.
Nie zmienia hasła do laptopa.
Nie zmienia hasła do panelu `cyberfolks`.

## Jak zapisać nowe hasło VPS na pendrive
Na laptopie, po zmianie hasła na VPS, włóż pendrive `OANDAKEY` i uruchom:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\reseal_vps_admin_dpapi_secret.ps1 -UsbLabel OANDAKEY -VpsHost 185.243.55.55 -VpsAdminLogin Administrator
```

Skrypt:
- zapyta o nowe hasło,
- zapisze je na pendrive w formie `DPAPI`,
- zrobi backup starego `BotKey.env`.

## Jak przenieść kod na VPS
Najprościej przez `RDP` z podpiętym lokalnym dyskiem.

Na laptopie gotowa paczka jest tutaj:

```text
C:\OANDA_MT5_SYSTEM\EVIDENCE\vps_prep\oanda_mt5_bundle_20260307T082445Z.zip
```

Na VPS:
1. utwórz katalog:

```powershell
New-Item -ItemType Directory -Force C:\OANDA_MT5_SYSTEM | Out-Null
```

2. skopiuj paczkę z `\\tsclient\C\...`
3. rozpakuj:

```powershell
Expand-Archive -Path C:\Users\Administrator\Desktop\oanda_mt5_bundle_20260307T082445Z.zip -DestinationPath C:\OANDA_MT5_SYSTEM -Force
```

## Jak przygotować VPS po rozpakowaniu
Na VPS:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\vps_bootstrap_windows.ps1 -ProjectRoot C:\OANDA_MT5_SYSTEM -LabDataRoot C:\OANDA_MT5_LAB_DATA
```

To zrobi:
- katalogi,
- plan zasilania,
- raport startowy bootstrapu.

## Gdy `HybridAgent` konczy `INIT_FAILED (-1)` po starcie MT5
Jesli w logu `MQL5` widzisz:

- `cannot load ... libzmq.dll [126]`
- `module 'libzmq.dll' is not loaded`

to na VPS brakuje systemowej zaleznosci dla `libzmq.dll`. Zainstaluj ja:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\vps_install_mt5_prereqs.ps1
```

Potem zamknij i uruchom `MT5` ponownie.

## Pierwsza walidacja po migracji
Na VPS sprawdź:

```powershell
py -3.12 C:\OANDA_MT5_SYSTEM\TOOLS\vps_preflight_local.py --host 185.243.55.55 --root C:\OANDA_MT5_SYSTEM
```

Potem:

```powershell
powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\SYSTEM_CONTROL.ps1 status -Root C:\OANDA_MT5_SYSTEM
```

## Czego nie robić w tym samym kroku
- nie przenosić od razu logiki z `Python` do `MQL5`,
- nie refaktorować ciężko `SafetyBot` w trakcie samej migracji,
- nie zmieniać jednocześnie architektury runtime i środowiska uruchomieniowego.

## Następny etap po stabilnym uruchomieniu na VPS
1. pomiar opóźnienia na VPS,
2. mapa hot-path `SafetyBot`,
3. decyzja co:
   - zostaje w `Python`,
   - idzie bliżej `MQL5`,
   - albo ma być liczone wcześniej poza gorącą ścieżką.
