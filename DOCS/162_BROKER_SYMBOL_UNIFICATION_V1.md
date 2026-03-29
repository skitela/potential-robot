# Broker Symbol Unification V1

Data: `2026-03-20`

## Cel

Ujednolicenie mapowania symboli w `MAKRO_I_MIKRO_BOT`, tak aby:

- symbol kanoniczny byl wspolny dla logiki, stanu i raportow,
- symbol brokerski byl jawny i zawsze wskazywal wersje `.pro`,
- runtime laptopa, tester MT5 i panel operatorski nie mieszaly juz przypadkowo aliasow.

## Model po zmianie

Kazdy wpis w `CONFIG\microbots_registry.json` ma teraz trzy role:

- `symbol`
  - alias kanoniczny systemu, bez `.pro`
- `broker_symbol`
  - symbol terminalowy dla OANDA / MT5, z `.pro`
- `code_symbol`
  - alias kodowy do plikow ekspertow, presetow i scaffoldingu

Przyklad:

- `symbol = GOLD`
- `broker_symbol = GOLD.pro`
- `code_symbol = GOLD`

Przyklad futures/metali z aliasem kodowym:

- `symbol = COPPER-US`
- `broker_symbol = COPPER-US.pro`
- `code_symbol = COPPERUS`

## Co zostalo przepiete

Na `broker_symbol` lub wspolne helpery aliasow przeszly:

- generator planu wykresow MT5,
- profil chartow MT5,
- runner testera strategii,
- panel operatorski,
- runtime control dla par,
- watchdog runtime,
- walidator deploymentu,
- walidator zgodnosci registry vs variant registry,
- sync tokenow OANDA,
- raport rodzin operatorskich,
- runtime control summary,
- walidator session state machine,
- resilience drills.

## Najwazniejsze skutki

1. Chart-plan i setup profilu MT5 wiedza juz wprost, ze terminal ma dostac symbol `.pro`.
2. Tester nie zgaduje juz symbolu na podstawie regexu, tylko bierze `broker_symbol`.
3. Runtime i walidatory szukaja stanu po aliasach, wiec nie gubia symboli tam, gdzie na dysku wystepuje mix:
   - `GOLD`
   - `GOLD.pro`
   - `COPPER-US`
   - `COPPERUS`
4. Panel operatorski pokazuje instrumenty w wersji brokerskiej, ale sterowanie trafia poprawnie w alias kanoniczny i alias runtime.

## Twarda walidacja po zmianie

Po wdrozeniu:

- `GENERATE_MT5_CHART_PLAN.ps1` przechodzi poprawnie,
- `VALIDATE_SYMBOL_POLICY_CONSISTENCY.ps1` daje `ok = true`,
- `GENERATE_RUNTIME_CONTROL_SUMMARY.ps1` przechodzi poprawnie,
- `VALIDATE_SESSION_STATE_MACHINE.ps1` daje `ok = true`,
- `GENERATE_FAMILY_OPERATOR_REPORT.ps1` przechodzi poprawnie,
- helper aliasow poprawnie rozwiazuje m.in.:
  - `EURUSD.pro`
  - `GOLD.pro`
  - `COPPER-US.pro`
  - `MicroBot_GOLD`

## Co nadal zostaje do dopiecia

To nie jest juz problem unifikacji `.pro`, tylko warstwa operacyjna kluczy:

- `VALIDATE_DEPLOYMENT_READINESS.ps1` nadal pokazuje:
  - stale tokeny FX,

Czyli:

- mapowanie symboli jest juz spojne,
- ale odswiezenie / doszczelnienie kill-switch tokenow nadal trzeba zrobic osobnym krokiem.

## Wniosek

Rdzen systemu przestal mieszac:

- symbol kanoniczny,
- symbol brokerski,
- symbol kodowy.

To odcina jedna z glownych przyczyn chaosu miedzy:

- laptop runtime,
- testerem MT5,
- chart-planem,
- panelem operatorskim,
- walidatorami deploymentu i session state.
