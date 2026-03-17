# INDICES Runtime Rollout V1

## Cel

Wlaczyc domene `INDICES` do tego samego organizmu runtime, w ktorym dzialaja juz
`FX` i `METALS`, bez budowania osobnego projektu i bez naruszania wspolnego
kontraktu kapitalowego, koordynatora sesji oraz hierarchii strojenia.

## Zakres V1

Do runtime zostaly dodane dwa pierwsze indeksowe mikro-boty:

- `DE30.pro` jako rodzina `INDEX_EU`
- `US500.pro` jako rodzina `INDEX_US`

To jest seed domeny `INDICES`, nie koniec dojrzewania genotypu indeksowego.

## Co zostalo dodane

- profile:
  - `MQL5/Include/Profiles/Profile_DE30.mqh`
  - `MQL5/Include/Profiles/Profile_US500.mqh`
- strategie:
  - `MQL5/Include/Strategies/Strategy_DE30.mqh`
  - `MQL5/Include/Strategies/Strategy_US500.mqh`
- mikro-boty:
  - `MQL5/Experts/MicroBots/MicroBot_DE30.mq5`
  - `MQL5/Experts/MicroBots/MicroBot_US500.mq5`
- presety:
  - `MQL5/Presets/MicroBot_DE30_Live.set`
  - `MQL5/Presets/MicroBot_US500_Live.set`

## Genotyp runtime

### DE30.pro / INDEX_EU

- okno aktywne: `12:00-14:00` PL
- `ready_trigger_abs = 0.82`
- `caution_trigger_abs = 0.98`
- `max_spread_points = 110`
- profil bardziej noon-cash niż metalowy futures clone

### US500.pro / INDEX_US

- okno aktywne: `17:00-20:00` PL
- `ready_trigger_abs = 0.84`
- `caution_trigger_abs = 1.00`
- `max_spread_points = 95`
- profil mocno selektywny pod otwarcie i rytm cash US

## Integracja organizmu

Rollout objal nie tylko pliki MQL5, ale tez caly uklad wspolny:

- `CONFIG/microbots_registry.json`
- `CONFIG/strategy_variant_registry.json`
- `CONFIG/family_policy_registry.json`
- `CONFIG/family_reference_registry.json`
- `CONFIG/tuning_fleet_registry.json`
- `CONFIG/session_capital_coordinator_v1.json`
- `CONFIG/domain_architecture_registry_v1.json`
- `CONFIG/project_config.json`
- `CONFIG/indices_family_blueprint_v1.json`

`INDICES` zostaly ustawione jako aktywna domena runtime pod wspolnym
`GLOBAL_SESSION_AND_CAPITAL_COORDINATOR`.

## Hierarchia strojenia

Po przebudowie seedow i aplikacji hierarchii:

- `INDEX_EU` ma juz swoj stan rodzinny i journal
- `INDEX_US` ma juz swoj stan rodzinny i journal
- koordynator floty widzi juz `7` rodzin

Na ten moment obie rodziny indeksowe sa uczciwie oznaczone jako:

- `trusted_data = 0`
- `freeze_new_changes = 1`
- `last_action_code = FREEZE_FAMILY`

To jest poprawne i oczekiwane, bo indeksy nie maja jeszcze lokalnej historii
probek do strojenia.

## Walidacja

Potwierdzone po rolloutcie:

- `17/17 compile_ok=true`
- `VALIDATE_PROJECT_LAYOUT.ps1 -> ok=true`
- `VALIDATE_FAMILY_POLICY_BOUNDS.ps1 -> ok=true`
- `VALIDATE_FAMILY_REFERENCE_REGISTRY.ps1 -> ok=true`
- `VALIDATE_TUNING_HIERARCHY.ps1 -> ok=true`
- `VALIDATE_SESSION_CAPITAL_COORDINATOR.ps1 -> ok=true`
- `VALIDATE_CORE_CAPITAL_CONTRACT.ps1 -> ok=true`

## Uwagi operacyjne

- `INDICES` sa juz aktywna domena runtime, ale jeszcze bez dojrzalej probki.
- Tuning dla indeksow zaczyna z pozycji defensywnej i zamrozonej.
- Nastepny sensowny etap to:
  - playbook pierwszej godziny dla `INDEX_EU` i `INDEX_US`,
  - albo dalsze rozwijanie logiki `reserve -> paper -> reentry` na poziomie domen.

## Zrodla nazewnictwa symboli

Nazwy runtime zostaly zachowane jako:

- `DE30.pro`
- `US500.pro`

To jest zgodne z:

- audytem starego systemu `OANDA_MT5_SYSTEM`
- oraz z biezacym materialem OANDA/TMS, gdzie te aliasy byly mapowane do tych
  symboli jako wlasciwy runtime MT5
