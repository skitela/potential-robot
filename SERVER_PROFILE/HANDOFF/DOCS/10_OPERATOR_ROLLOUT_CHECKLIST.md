# Operator Rollout Checklist

## Cel

Ten dokument opisuje najkrotszy bezpieczny przebieg operatora przed attach aktywnej floty mikro-botow do wykresow `OANDA MT5`, obejmujacych:

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

Wszystkie raporty musza dawac `ok=true`.

## Krok 3

Sprawdz plan przypiecia:

- `DOCS\06_MT5_CHART_ATTACHMENT_PLAN.txt`
- `DOCS\06_MT5_CHART_ATTACHMENT_PLAN.json`

To jest zrodlo prawdy dla:

- symbolu,
- nazwy eksperta,
- presetu,
- `magic number`.

## Krok 3A

Nazwy nie sa zamienne. Przed attach kazdy operator musi rozrozniac:

- `symbol_alias` - nazwa kanoniczna w repo, auditach i supervision, np. `COPPER-US`
- `broker_symbol` - nazwa wykresu i Market Watch w `OANDA TMS MT5`, np. `COPPER-US.pro`
- `code_symbol` - nazwa plikowa dla `Profile_*.mqh`, `Strategy_*.mqh` i `MicroBot_*`, np. `COPPERUS`
- `state_alias` - katalog runtime pod `MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\state\<alias>`

Do attachu uzywaj zawsze `broker_symbol` z chart planu. Do walidacji plikow i runtime uzywaj `code_symbol` oraz `state_alias`. Nie zamieniaj recznie `COPPER-US`, `COPPERUS` i `COPPER-US.pro`.

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
- raportu bezpieczenstwa presetow,
- baseline statusu `MT5 pretrade/execution truth`,
- instrukcji instalacji na zdalnym terminalu `MT5`.

## Krok 4B

Jesli pakiet ma byc przenoszony jako archiwum, uzyj osobnego ZIP operatorskiego:

- `BACKUP\MAKRO_I_MIKRO_BOT_HANDOFF_*.zip`

## Krok 5

W `MetaTrader 5`:

- otworz wykresy dla `broker_symbol` z aktualnego chart planu,
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

## Krok 5C

Jesli rollout idzie przez `MetaTrader VPS`, obowiazuja dodatkowe zasady z dokumentacji MetaQuotes:

- synchronizacja jest jednokierunkowa: lokalny terminal -> wirtualny terminal, nigdy odwrotnie
- nie ma auto-resynchronizacji; po kazdej zmianie wykresow, `Market Watch`, `EA`, presetow, `WebRequest`, `FTP`, `Email` lub signalu trzeba wykonac nowa synchronizacje
- migruja tylko wykresy z przypietym `EA`; puste wykresy nie przejda
- limit to `32` wykresy z `EA` na hostingu platnym i `16` na darmowym; nasza aktywna flota `13` miesci sie, ale dodatkowe wykresy tez zuzywaja sloty
- skrypty nie migruja
- `Algo Trading` jest zawsze wlaczone na terminalu wirtualnym, nawet jesli lokalnie bylo wylaczone
- wykresy z niestandardowymi symbolami albo niestandardowymi timeframe'ami nie migruja
- pierwszy sync dociaga historie dla otwartych wykresow; boty musza poprawnie przezyc dogrzanie historii
- wywolania `DLL` sa zabronione na `MetaTrader VPS`

## Krok 6

Po attach potwierdz:

- brak bledow inicjalizacji,
- brak blokady `magic`,
- brak blokady `kill-switch`,
- poprawny heartbeat i lokalny status bota.

## Krok 6A

Po pierwszym heartbeat sprawdz pierwszy zywy zapis do spoola truth:

- `MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\spool\pretrade_truth`
- `MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\spool\execution_truth`

Jesli katalogi pozostaja puste albo timestamp CSV nie rusza po attach, sekcja 3 nadal jest dormant i rollout parity nie jest domkniety.

## Krok 6B

Po attach i ewentualnej synchronizacji `VPS` sprawdz dodatkowo:

- `EVIDENCE\OPS\mt5_active_symbol_deployment_audit_latest.md`
- `EVIDENCE\OPS\mt5_symbol_metadata_profile_audit_latest.md`
- `EVIDENCE\OPS\mt5_first_wave_server_parity_latest.md`
- w `MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\state\<state_alias>` obecnosci `teacher_package_contract.csv` i `broker_profile.json`
- w logach terminala albo `VPS` brakow migracji, brakow indikatorow i brakow bibliotek

## Krok 7

Jesli raport gotowosci wskazuje `TOKEN_STALE`, najpierw odswiez tokeny:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\SYNC_ALL_OANDAKEY_TOKENS.ps1
```

Potem ponow preflight.

## Znane Kruczki 2026-04-01

- audit aktywnego terminala pokazal brak `MicroBot_AUDUSD.ex5` w instancji `OANDA TMS MT5`, mimo zgodnosci zrodel `.mq5` i presetow
- `teacher_package_contract.csv` brakowal dla `12/13` symboli; tylko `EURUSD` byl w pelni domkniety deploymentowo
- profile repo nadal nie importuja `volume_min/volume_step/volume_max`, `tick_size/tick_value` oraz `stops_level/freeze_level`; audit metadata oznacza to jako stale `import_gaps`
- bezposredni odczyt `bases\OANDATMS-MT5\symbols\symbols-*.dat` nie daje jeszcze stabilnego potwierdzenia mapowania nazw, wiec zrodlem prawdy operacyjnej pozostaja `chart plan` + `broker_profile.json`
- presety `ActiveLive` sa oczekiwane tylko dla `paper_live_first_wave`; brak takich presetow dla pozostalych symboli nie jest bledem instalacji

## Konkluzja

Operator ma jeden glowny punkt wejscia:

- `RUN\PREPARE_MT5_ROLLOUT.ps1`

To ma byc standardowa droga przed wdrozeniem lub wznowieniem pracy aktywnej floty MT5 zgodnej z aktualnym registry i chart planem. Po kazdej zmianie lokalnego srodowiska albo synchronizacji `MetaTrader VPS` wracaj do tej checklisty i ponawiaj audyty parity.
