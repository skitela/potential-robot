# Operator Rollout Checklist

## Cel

Ten dokument opisuje najkrotszy bezpieczny przebieg operatora przed attach `17` mikro-botow do wykresow `OANDA MT5`, obejmujacych:

- `FX`
- `METALS`
- `INDICES`

## Zasada

Nie przypinaj botow do wykresow przed wykonaniem preflightu rolloutowego.

## Krok 1

Uruchom wrapper:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\PREPARE_MT5_ROLLOUT.ps1
```

## Krok 2

Sprawdz raport:

- `EVIDENCE\prepare_mt5_rollout_report.json`
- `EVIDENCE\deployment_readiness_report.json`
- `EVIDENCE\preset_safety_report.json`

Oba raporty musza dawac `ok=true`.

## Krok 3

Sprawdz plan przypiecia:

- `DOCS\06_MT5_CHART_ATTACHMENT_PLAN.txt`
- `DOCS\06_MT5_CHART_ATTACHMENT_PLAN.json`

To jest zrodlo prawdy dla:

- symbolu,
- nazwy eksperta,
- presetu,
- `magic number`.

## Krok 4

Skopiuj lub odswiez paczke serwerowa:

- `SERVER_PROFILE\PACKAGE`

## Krok 4A

Skopiuj lub zachowaj pakiet operatorski:

- `SERVER_PROFILE\HANDOFF`

To jest komplet:

- checklist,
- chart planu,
- raportow gotowosci,
- raportu bezpieczenstwa presetow.
- instrukcji instalacji na zdalnym terminalu `MT5`.

## Krok 4B

Jesli pakiet ma byc przenoszony jako archiwum, uzyj osobnego ZIP operatorskiego:

- `BACKUP\MAKRO_I_MIKRO_BOT_HANDOFF_*.zip`

## Krok 5

W `MetaTrader 5`:

- otworz `17` wykresow,
- przypnij wlasciwy `MicroBot_*` do wlasciwego symbolu,
- zaladuj odpowiadajacy preset `*_Live.set` jako bezpieczny attach startowy,
- upewnij sie, ze `Algo Trading` jest wlaczone.

## Krok 5A

Jesli operator chce swiadomie przygotowac presety z aktywnym live-send, generuje je osobno:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\GENERATE_ACTIVE_LIVE_PRESETS.ps1
```

Wygenerowane presety trafiaja do:

- `SERVER_PROFILE\PACKAGE\MQL5\Presets\ActiveLive`

To jest swiadomy krok operatorski.
Domyslne presety w repo pozostaja bezpieczne i maja `InpEnableLiveEntries=false`.

## Krok 5B

Jesli operator chce zbudowac lub odswiezyc caly profil wykresow automatycznie, moze uzyc:

```powershell
python C:\MAKRO_I_MIKRO_BOT\TOOLS\setup_mt5_microbots_profile.py --launch
```

To buduje profil `MAKRO_I_MIKRO_BOT_AUTO` z jednym mikro-botem na wykres i moze od razu uruchomic `MT5` na tym profilu.

## Krok 6

Po attach potwierdz:

- brak bledow inicjalizacji,
- brak blokady `magic`,
- brak blokady `kill-switch`,
- poprawny heartbeat i lokalny status bota.

## Krok 7

Jesli raport gotowosci wskazuje `TOKEN_STALE`, najpierw odswiez tokeny:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\SYNC_ALL_OANDAKEY_TOKENS.ps1
```

Potem ponow preflight.

## Konkluzja

Operator ma jeden glowny punkt wejscia:

- `RUN\PREPARE_MT5_ROLLOUT.ps1`

To ma byc standardowa droga przed wdrozeniem lub wznowieniem pracy calej partii `11`.
To ma byc standardowa droga przed wdrozeniem lub wznowieniem pracy calej partii `17`.
