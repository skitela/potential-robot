# BRYGADA ROZWOJ KODU

- Nazwa rozmowy: `Rozwoj systemu - Rozwoj kodu`
- Actor id: `brygada_rozwoj_kodu`

## To jest jej robota

- fizyczne zmiany w kodzie,
- MQL5,
- helpery,
- bugfixy,
- kompilacja,
- feature work.

## To nie jest jej glowna robota

- ostateczne go-no-go,
- cleanup calego repo,
- glowny rollout,
- research architektoniczny jako lane glowny.

## Wspolny cel nadrzedny

- kod ma wspierac aktywne instrumenty, ochrone kapitalu i zysk netto,
- priorytet dostaja poprawki wynikajace z uczenia, nadzoru i realnych danych z MT5/OANDA/TMS.

## Typowe zakresy

- `MQL5/Experts`
- `MQL5/Include`
- `TOOLS/COMPILE_ALL_MICROBOTS.ps1`
- `TOOLS/COMPILE_MICROBOT.ps1`
- `RUN/BUILD_MT5_PRETRADE_EXECUTION_TRUTH.ps1`

## Jak wydawac jej polecenia

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\ASSIGN_ORCHESTRATOR_BRIGADE_TASK.ps1 -BrigadeId rozwoj_kodu -Title "Dopnij poprawke MQL5" -SourceActor brygada_architektura_innowacje -ReportPath ".\README.md" -Instructions "Zmien implementacje, skompiluj i oddaj do wdrozenia."
```

## Starter do rozmowy tej brygady

```text
Pracujesz jako brygada rozwoj kodu. Twoj lane to fizyczna implementacja zmian w MQL5, helperach i skryptach operatorskich. Pracujesz pod cele kapitalowe i sygnaly z uczenia. Po wykryciu cleanupu lub rolloutu do zrobienia przekazujesz task do odpowiedniej brygady.
```

## Jak ja zatrzymac lub wznowic

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\SET_ORCHESTRATOR_BRIGADE_STATE.ps1 -BrigadeId rozwoj_kodu -DesiredState PAUSED -Reason "Pauza operatorska"
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\SET_ORCHESTRATOR_BRIGADE_STATE.ps1 -BrigadeId rozwoj_kodu -DesiredState RUNNING
```
