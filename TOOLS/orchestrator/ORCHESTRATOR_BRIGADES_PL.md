# Model Wielobrygadowy Orchestratora

Ten plik opisuje, jak rozdzielic MAKRO_I_MIKRO_BOT na stale brygady pracy, tak zeby kilka rownoleglych chatow albo agentow moglo pracowac nad jednym organizmem bez wchodzenia sobie w droge.

## Glowna zasada

Nie tworzymy kilku przypadkowych rozmow. Tworzymy stale lane'y pracy.

Jeden chat albo agent bierze jedna brygade na sesje i uzywa jej `actor_id` w:

- claimach pracy,
- taskboardzie rownoleglym,
- activity heartbeat,
- notatkach handoffowych.

Rejestr brygad jest zapisany w:

- `CONFIG/orchestrator_brigades_registry_v1.json`

Klikalna warstwa po lewej stronie w Explorerze jest zapisana w katalogu:

- `BRYGADY`

To jest praktyczny panel roboczy dla operatora: kazdy plik ma nazwe brygady i od razu pokazuje czym ona sie zajmuje.

## Hierarchia nadrzedna

Wszystkie brygady, bez wyjatku, sa podporzadkowane jednemu organizmowi i jednemu porzadkowi decyzji:

1. najpierw ochrona kapitalu powierzonego systemowi do scalpingu,
2. potem zysk netto i bezpieczna praca na aktywnych instrumentach,
3. potem ciagle uczenie i raportowanie stanu uczenia,
4. potem parity miedzy labem na laptopie a VPS OANDA MT5 i TMS Brokers,
5. dopiero na tym tle cleanup, rollout i innowacje.

To oznacza, ze zadanie technicznie ciekawe, ale niepoprawiajace kapitalu, wyniku albo realizmu testow, nie ma pierwszenstwa.

## Codex i specjalizacje brygad

Codex pozostaje podstawowym wykonawca i moze zrobic prace dowolnej brygady.

Kazda brygada takze moze dostac polecenie spoza swojej specjalizacji.

Specjalizacja nadal jest potrzebna, bo daje:

- czytelny lane odpowiedzialnosci,
- priorytet backlogu,
- jednoznaczny actor_id na taskboardzie,
- audytowalny handoff miedzy rozmowami.

Praktyczna zasada jest prosta: nawet jesli robote wykonuje Codex albo inna brygada, task i heartbeat maja byc przypisane do lane'u brygady, ktora odpowiada za ten typ pracy.

## Brygady zawsze aktywne

W tym modelu dwie brygady sa traktowane jako stale aktywne lane'y nadrzedne:

- `ml_migracja_mt5` prowadzi ciagle uczenie i migracje modelowe,
- `nadzor_uczenia_rolloutu` nadzoruje readiness, learning health, go-no-go i raportuje priorytety pozostalim brygadom.

Pozostale brygady powinny traktowac taski i raporty z tych dwoch lane'ow jako sygnal o wyzszym priorytecie, o ile nie lamie to veto kapitalowo-sesyjnego.

## Brygady dla MAKRO_I_MIKRO_BOT

### 1. Brygada ML i migracja MT5

- Actor id: `brygada_ml_migracja_mt5`
- Chat name: `Rozwoj systemu - ML i migracja MT5`
- Robi: trening, ONNX, QDM, migracje modeli i runtime state do MT5
- Nie robi samodzielnie: rolloutow produkcyjnych i cleanupu repo

### 2. Brygada audyt i cleanup

- Actor id: `brygada_audyt_cleanup`
- Chat name: `Rozwoj systemu - Audyt i cleanup`
- Robi: stale skany, residue po wycietych instrumentach, higiena EVIDENCE, BACKUP, LOGS i raporty auditowe
- Nie robi samodzielnie: zmian produkcyjnych w strategii bez handoffu

### 3. Brygada wdrozenia MT5

- Actor id: `brygada_wdrozenia_mt5`
- Chat name: `Rozwoj systemu - Wdrozenia MT5`
- Robi: package, install, validate, remote deploy, handoff operatorski
- Nie robi samodzielnie: zmian strategii i trenowania modeli

### 4. Brygada rozwoj kodu

- Actor id: `brygada_rozwoj_kodu`
- Chat name: `Rozwoj systemu - Rozwoj kodu`
- Robi: feature work, bugfixy, MQL5, helpery, fizyczne wykonanie zmian technicznych
- Nie robi samodzielnie: decyzji go-no-go i rollout veto

### 5. Brygada architektura i innowacje

- Actor id: `brygada_architektura_innowacje`
- Chat name: `Rozwoj systemu - Architektura i innowacje`
- Robi: nowe koncepcje, badanie MT5 i OANDA, kontrakty architektoniczne, usprawnienia mostu i przeplywow
- Nie robi samodzielnie: finalnych wdrozen bez tasku do odpowiedniej brygady wykonawczej

### 6. Brygada nadzor uczenia i rolloutow

- Actor id: `brygada_nadzor_uczenia_rolloutu`
- Chat name: `Rozwoj systemu - Nadzor uczenia i rolloutow`
- Robi: readiness, overlay audit, learning health, prelive go-no-go i pilnowanie bezpiecznego przejscia miedzy ML, kodem i rolloutem
- Nie robi samodzielnie: glownych zmian feature'owych

## Co spina wszystkie brygady

Wszystkie brygady musza pracowac przez jeden dziennik budowy, czyli przez lokalny most orchestratora:

- `coordination/claims`
- `coordination/tasks`
- `coordination/activity`
- `notes/inbox`
- `status`

To oznacza, ze brygady nie maja polegac na pamieci rozmowy ani na domyslaniu sie, co robi druga strona.

Kazde zadanie powinno byc rozpisane miedzy brygadami. Nie wrzucamy pracy do nieoznaczonej kolejki bez lane'u odpowiedzialnosci.

## Zasady ruchu miedzy brygadami

1. Brygada bierze claim na raport albo scope przed ruszeniem zmian.
2. Jesli praca ma trwac dluzej niz szybki fix, brygada zaklada task i heartbeat.
3. Handoff do innej brygady musi zostawic note plus task.
4. Kapital i session coordinator sa warstwa veto globalnego, niezaleznie od tego, ile brygad pracuje rownolegle.

## Jak tego uzywac praktycznie

Autostart standing-taskow brygad po otwarciu workspace:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\START_ORCHESTRATOR_BRIGADE_AUTOSTART.ps1
```

Pauza jednej brygady:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\SET_ORCHESTRATOR_BRIGADE_STATE.ps1 -BrigadeId ml_migracja_mt5 -DesiredState PAUSED -Reason "Pauza operatorska"
```

Wznowienie jednej brygady:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\SET_ORCHESTRATOR_BRIGADE_STATE.ps1 -BrigadeId ml_migracja_mt5 -DesiredState RUNNING
```

Taskboard pogrupowany po brygadach:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_TASKBOARD.ps1 -ByBrigade
```

Podglad brygad:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_BRIGADES.ps1
```

Przekazanie zadania od jednej brygady do drugiej przez note plus task:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\HANDOFF_ORCHESTRATOR_BRIGADE_TASK.ps1 -FromBrigadeId rozwoj_kodu -ToBrigadeId audyt_cleanup -Title "Cleanup residue po starych instrumentach" -Instructions "Znalazlem stare slady i prosze o cleanup." -ReportPath "C:\MAKRO_I_MIKRO_BOT\README.md"
```

Szczegoly jednej brygady:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_BRIGADES.ps1 -BrigadeId rozwoj_kodu
```

Przydzielenie tasku bez pamietania actor_id:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\ASSIGN_ORCHESTRATOR_BRIGADE_TASK.ps1 -BrigadeId audyt_cleanup -Title "Sprawdz residue po wycietych instrumentach" -SourceActor brygada_architektura_innowacje -ReportPath "C:\MAKRO_I_MIKRO_BOT\README.md"
```

## Zalecane stale nazwy rozmow

- `Rozwoj systemu - ML i migracja MT5`
- `Rozwoj systemu - Audyt i cleanup`
- `Rozwoj systemu - Wdrozenia MT5`
- `Rozwoj systemu - Rozwoj kodu`
- `Rozwoj systemu - Architektura i innowacje`
- `Rozwoj systemu - Nadzor uczenia i rolloutow`

## Najwazniejszy efekt

Po tym podziale nie pytamy juz: "kto teraz cos robi?".
Pytamy:

- ktora brygada ma claim,
- ktora brygada ma task,
- jaki jest heartbeat,
- jaki jest handoff,
- czy veto kapitalowo-sesyjne dopuszcza dalszy ruch.

Przy otwarciu workspace VS Code autostart brygad moze byc wywolany automatycznie z `.vscode/tasks.json`, a stan `PAUSED` zatrzymuje dokladanie nowych standing-taskow tylko dla wskazanej brygady.
