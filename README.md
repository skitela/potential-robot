# MAKRO_I_MIKRO_BOT

Nowy projekt `100% MQL5` jest teraz glownym aktywnym systemem.

Historyczne repo i stare eksperymenty pozostaja tylko jako kontekst zrodlowy, a nie jako aktywna zaleznosc runtime.

Cel projektu:

- zbudowac cienki `Core` jako wspolna biblioteke,
- zachowac grube i autonomiczne `MicroBots`,
- wdrazac boty na serwerach `MT5-only`,
- ograniczyc redundancje bez centralizacji runtime.

## Zasada projektowa

`1 mikro-bot = 1 wykres = 1 symbol`

Kazdy mikro-bot:

- ma wlasny runtime,
- ma wlasny kill-switch,
- ma wlasne limity,
- handluje tylko jedna para,
- korzysta z `Core` jako biblioteki, a nie nadrzednego sterownika.

## Struktura

- `MQL5/Include/Core` - wspolne klocki i helpery
- `MQL5/Include/Profiles` - profile symboli
- `MQL5/Include/Strategies` - logika symbolowa
- `MQL5/Experts/MicroBots` - EA per symbol
- `MQL5/Presets` - presety botow
- `TOOLS` - generator, pakowanie, walidacja
- `SERVER_PROFILE` - przenoszalny profil serwerowy
- `SERVER_PROFILE/HANDOFF` - pakiet operatorski z checklistami, planem i raportami
- `RUN` - wrappers operatorskie i wejscie do preflightu rolloutowego
- `METALS_MAKRO_I_MIKRO_BOT` - katalog domenowy dla metali wewnatrz wspolnego organizmu
- `INDICES_MAKRO_I_MIKRO_BOT` - katalog domenowy dla indeksow wewnatrz wspolnego organizmu

## Domeny wspolnego organizmu

Projekt pozostaje jednym organizmem, ale rozwija sie w trzech domenach:

- `FX`
- `METALS`
- `INDICES`

To nie sa trzy osobne systemy. Te domeny:

- dziela wspolny kontrakt kapitalowy,
- dziela wspolny reczny kontrakt `core capital`,
- dziela wspolna polityke brokera,
- dziela wspolnego nadrzednego koordynatora sesji i kapitalu,
- ale zachowuja osobne rodziny, genotypy i okna czasowe.

Szczegoly architektury:

- `DOCS/68_DOMAIN_ARCHITECTURE_FX_METALS_INDICES_V1.md`
- `CONFIG/domain_architecture_registry_v1.json`
- `CONFIG/core_capital_contract_v1.json`
- `CONFIG/session_capital_coordinator_v1.json`
- `DOCS/71_GLOBAL_SESSION_CAPITAL_COORDINATOR_V1.md`
- `DOCS/72_RUNTIME_PERSISTENCE_AND_LOG_ROTATION_POLICY_V1.md`

## Stan bootstrapu

W projekcie utworzono:

- katalogi docelowe,
- dokumentacje architektury,
- pierwszy szkic `Core`,
- pierwszy profil i strategia `EURUSD`,
- pierwszy referencyjny `MicroBot_EURUSD`,
- podstawowy generator szkieletu nowego mikro-bota,
- pierwszy dodatkowy bot wygenerowany ze scaffolda: `AUDUSD`,
- rejestr planowanych mikro-botow,
- pelna pierwsza partia `11` FX mikro-botow oraz rozszerzenie do `17` mikro-botow po dodaniu domen `METALS` i `INDICES`,
- plan przypiecia botow do wykresow MT5 generowany z registry,
- pierwszy eksport paczki serwerowej i pierwszy ZIP backup projektu,
- potwierdzona kompilacja `MetaEditor` dla calej aktywnej partii `17` mikro-botow,
- pierwszy realny przeszczep dojrzalych modulow obserwowalnosci z `EURUSD` do nowego ukladu,
- pierwszy realny przeszczep dojrzalych guardow rynku z `EURUSD` do wspolnego `Core`,
- wspolny niskopoziomowy precheck wykonania przygotowany pod przyszle lokalne wejscia botow,
- wspolny lokalny wrapper `send/retry` i journaling `trade transaction`,
- pierwszy realny lokalny scoring `EURUSD` oparty o wskazniki, nadal poza `Core`,
- pierwszy suchy tor `EURUSD`: sygnal -> sizing -> execution precheck bez realnego `OrderSend`,
- kontrolowany lokalny live-send `EURUSD` pod bezpiecznym przelacznikiem `InpEnableLiveEntries`,
- pierwszy lokalny management pozycji `EURUSD` z trailingiem,
- ustandaryzowany kontrakt hookow strategii dla wszystkich mikro-botow,
- `GBPUSD` jako pierwsza para poza wzorcem dostala realny lokalny scoring,
- `GBPUSD` dostal tez pelny suchy tor wejscia bez live-send,
- `GBPUSD` jest juz drugim pelnym wzorcem z lokalnym live-send pod bezpiecznym przelacznikiem,
- `USDJPY` jest pierwszym rozwinietym archetypem azjatyckim z lokalnym scoringiem i suchym torem wejscia,
- `USDJPY` jest juz tez pelnym archetypem azjatyckim z live-send pod bezpiecznym przelacznikiem,
- `NZDUSD` jest juz drugim pelnym archetypem azjatyckim z lokalnym live-send pod bezpiecznym przelacznikiem,
- `USDCAD` jest juz trzecim pelnym wzorcem sesji glownej z lokalnym live-send pod bezpiecznym przelacznikiem,
- `USDCHF` jest juz czwartym pelnym wzorcem sesji glownej z lokalnym live-send pod bezpiecznym przelacznikiem,
- `AUDUSD` jest juz trzecim pelnym archetypem azjatycko-przejsciowym z lokalnym live-send pod bezpiecznym przelacznikiem,
- `EURJPY` jest juz pierwszym pelnym wzorcem crossowym z lokalnym live-send pod bezpiecznym przelacznikiem,
- `GBPJPY` jest juz drugim pelnym wzorcem crossowym z lokalnym live-send pod bezpiecznym przelacznikiem,
- `EURAUD` jest juz trzecim pelnym wzorcem crossowym z lokalnym live-send pod bezpiecznym przelacznikiem,
- `GBPAUD` jest juz czwartym pelnym wzorcem crossowym z lokalnym live-send pod bezpiecznym przelacznikiem,
- `GOLD`, `SILVER`, `PLATIN` i `COPPER-US` sa juz lokalnie przygotowane jako domena `METALS` z profilem, strategia, presetem, hierarchia strojenia i rodzinnymi seedami,
- `DE30` i `US500` sa juz lokalnie przygotowane jako domena `INDICES` z profilem, strategia, presetem, hierarchia strojenia i wspolnym koordynatorem dnia,
- cala aktywna partia `17` ma juz unikalne `magic numbers` oraz odswiezony plan przypiecia do wykresow,
- model `kill-switch` zostal doprowadzony do wzorca `EURUSD`, razem z cache runtime i skryptami odswiezania tokenow,
- projekt ma juz walidator gotowosci wdrozenia dla calej aktywnej partii `17`,
- narzedzie bezpiecznego przebudowania calej partii botow z aktualnego generatora,
- jeden wrapper operatorski `RUN\\PREPARE_MT5_ROLLOUT.ps1` do calosciowego preflightu,
- osobna checklista operatora rolloutowego.

## Najblizsze kroki

1. Uzgodnic finalny kontrakt integracyjny z dojrzewajacym `EURUSD`.
2. Przenosic dobre praktyki z `C:\\GLOBALNY HANDEL VER1\\EURUSD` tylko tam, gdzie nie oslabia to autonomii bota.
3. Wzbogacic lokalne strategie i profile bez centralizacji runtime.
4. Przygotowac bezpieczne rollouty `MT5-only` dla calej aktywnej partii `17`.
5. Dopiero potem rozwazac subtelne ulepszenia `Core`, bez zabierania edge z mikro-botow.

## Szybki Start Rolloutu

Najkrotsza bezpieczna sciezka operatorska:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\PREPARE_MT5_ROLLOUT.ps1
```

Potem sprawdz:

- `DOCS\10_OPERATOR_ROLLOUT_CHECKLIST.md`
- `EVIDENCE\prepare_mt5_rollout_report.json`
- `EVIDENCE\symbol_policy_consistency_report.json`
- `EVIDENCE\family_policy_bounds_report.json`
- `EVIDENCE\deployment_readiness_report.json`
- `EVIDENCE\preset_safety_report.json`

Pakiet operatorski po preflight:

- `SERVER_PROFILE\HANDOFF`
- osobny ZIP operatorski w `BACKUP`

Po stronie docelowego serwera:

- `TOOLS\INSTALL_MT5_SERVER_PACKAGE.ps1`
- `TOOLS\VALIDATE_MT5_SERVER_INSTALL.ps1`

W preflight jest tez juz:

- testowa symulacja instalacji `PACKAGE` do `SERVER_PROFILE\REMOTE_SIM`

Domyslne `*_Live.set` pozostaja bezpieczne i maja `InpEnableLiveEntries=false`.
Jesli potrzebne sa presety aktywne, generuj je swiadomie:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\GENERATE_ACTIVE_LIVE_PRESETS.ps1
```
## Risk Split

Projekt utrzymuje swiadomy podzial:

- `Core` przechowuje wspolne `hard guards` i wspolne helpery ryzyka
- mikro-boty przechowuja lokalne modele ryzyka symbolu

To jest celowe ze wzgledu na:

- latencje
- ochrone kapitalu
- zachowanie genow par walutowych

Szczegoly:

- `DOCS/14_RISK_POLICY_SPLIT.md`
- `DOCS/15_SYMBOL_POLICY_COORDINATION.md`
- `DOCS/16_PROPAGATION_WORKFLOW.md`
- `DOCS/17_FAMILY_REFERENCE_MODEL.md`
- `DOCS/18_SYSTEM_GLOSSARY_AND_ATLAS.md`
- `DOCS/25_DZIENNE_RAPORTY_I_DASHBOARD_PL.md`
- `DOCS/26_RAPORT_WIECZORNY_WLASCICIELA_PL.md`

Glowne artefakty planowania propagacji:

- `EVIDENCE/strategy_propagation_plan.json`
- `EVIDENCE/propagation_plan_matrix.json`
- `EVIDENCE/PROPAGATION_PLANS`
- `EVIDENCE/PROPAGATION_PACKAGE`
- `EURUSD` jest pierwszym botem referencyjnym z buforowanym `decision journal` i `execution telemetry`, aby ograniczyć I/O w hot-path bez centralizacji logiki strategii.
- Przegląd wzorca `EURUSD` i jego połączeń z `Core` jest zapisany w [DOCS/19_EURUSD_REFERENCE_AND_CORE_LINK.md](/C:/MAKRO_I_MIKRO_BOT/DOCS/19_EURUSD_REFERENCE_AND_CORE_LINK.md).
- Operator dostaje dwa widoki po polsku:
  - dzienny dashboard operatorski `EVIDENCE/DAILY/dashboard_dzienny_latest.html`
  - prostszy raport wieczorny wlasciciela `EVIDENCE/DAILY/dashboard_wieczorny_latest.html`
- Dashboard operatorski ma tez polskie sterowanie pol-interaktywne:
  - `Wlacz tryb normalny`
  - `Wlacz close-only`
  - `Zatrzymaj system`

Shared propagation package:

- `TOOLS/PREPARE_SHARED_PROPAGATION_PACKAGE.ps1`
- `TOOLS/VALIDATE_PROPAGATION_PACKAGE.ps1`
- `DOCS/30_SHARED_PROPAGATION_PACKAGE.md`

Ta warstwa przygotowuje wspolny pakiet zmian do rodziny bez naruszania lokalnych strategii, profili i genotypu symboli.
