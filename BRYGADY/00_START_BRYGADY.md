# TABLICA BRYGAD

Ten katalog jest zrobiony po to, zeby brygady byly widoczne po lewej stronie w Explorerze VS Code.

To nie sa automatycznie tworzone rozmowy w historii czatu. To jest praktyczny panel roboczy w repo:

- klikasz brygade po lewej,
- od razu widzisz czym sie zajmuje,
- widzisz jej actor_id,
- masz gotowy wzorzec polecenia,
- mozesz zlecic zadanie innej brygadzie przez task i note.

## Obowiazkowa obsluga wiadomosci

- wszystkie brygady czytaja kazda nowa note ze wspolnej listy,
- wykonuje tylko brygada wskazana jako target albo brygada jawnie przypisana przez operatora lub Codexa,
- kazda note, handoff, task i wynik musza jawnie wskazac target przetwarzania, wlasciciela zlecenia oraz kierunek raportu zwrotnego,
- domyslnym administratorem informacji i koordynatorem calego mostu jest Codex,
- report ownerem jest domyslnie Codex; request owner pozostaje widoczny w nocie albo tasku, ale raport zwrotny wraca do Codexa, chyba ze operator jawnie wskaze inaczej,
- brygady niewskazane pozostaja w trybie read-only, chyba ze dostana jawny task albo handoff,
- brygada nadzoru zbiera raporty dla Codexa, rozsyla doprecyzowania routingowe i dopomina brakujace odpowiedzi, jezeli przeplyw informacji sie rozjezdza,
- dyspozycje inzyniera naczelnego sa broadcastem do wszystkich brygad i Codexa do wiadomosci; dziala tylko adresat wskazany w tej nocie albo w tasku,
- tylko brygada bedaca execution owner moze zlecic dalsza prace innej brygadzie i robi to przez note plus task,
- po wykonaniu, blokadzie albo delegacji execution owner publikuje krotki wynik dla wszystkich brygad i dla Codexa.

Szybki bootstrap lane'u:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_BRIGADE_START_CONTEXT.ps1 -BrigadeId ml_migracja_mt5
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\READ_ORCHESTRATOR_BRIGADE_NOTES.ps1 -BrigadeId ml_migracja_mt5 -Limit 10 -ShowContent
```

Obowiazkowy rytm startu jednej brygady:

1. uruchom `GET_ORCHESTRATOR_BRIGADE_START_CONTEXT.ps1`,
2. odczytaj nowe notatki przez `READ_ORCHESTRATOR_BRIGADE_NOTES.ps1`,
3. jesli masz target albo pending task, wez claim przez `CLAIM_ORCHESTRATOR_WORK.ps1`,
4. przy kazdej nowej nocie albo handoffie jawnie wskaz target przetwarzania, request ownera i report ownera,
5. po wykonaniu albo blokadzie opublikuj wynik przez `WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1` albo `COMPLETE_ORCHESTRATOR_PARALLEL_TASK.ps1 -PublishResultNote`.

## Szybki start

- [00_PANEL_STEROWANIA_BRYGAD.md](00_PANEL_STEROWANIA_BRYGAD.md) - szybkie wejscia, komendy operatorskie i najnowsze wnioski ze wspolnej listy.

## Sesje Copilot brygad

- [../00_BRYGADY_TUTAJ.md](../00_BRYGADY_TUTAJ.md) - glowna tablica wejsc do sesji Copilot i opisow brygad.
- [Wejdz: BRYGADA ML I MIGRACJA MT5](../.github/prompts/wejdz-brygada-ml-migracja-mt5.prompt.md)
- [Wejdz: BRYGADA AUDYT I CLEANUP](../.github/prompts/wejdz-brygada-audyt-cleanup.prompt.md)
- [Wejdz: BRYGADA WDROZENIA MT5](../.github/prompts/wejdz-brygada-wdrozenia-mt5.prompt.md)
- [Wejdz: BRYGADA ROZWOJ KODU](../.github/prompts/wejdz-brygada-rozwoj-kodu.prompt.md)
- [Wejdz: BRYGADA ARCHITEKTURA I INNOWACJE](../.github/prompts/wejdz-brygada-architektura-innowacje.prompt.md)
- [Wejdz: BRYGADA NADZOR UCZENIA I GO-NO-GO](../.github/prompts/wejdz-brygada-nadzor-uczenia-gonogo.prompt.md)

Po kliknieciu promptu uruchamiasz oddzielny start sesji dla wybranej brygady, a nie tylko zwykly plik opisowy.

## Wspolna hierarchia celow

- nadrzedny cel calego systemu i wszystkich brygad to ochrona kapitalu powierzonego do scalpingu,
- zaraz po tym stoi zysk netto i bezpieczna praca na aktywnych instrumentach,
- brygada ML i brygada nadzoru uczenia sa lane'ami stale aktywnymi i ich sygnaly maja pierwszenstwo dla innych brygad,
- lab na laptopie ma byc mozliwie bliski temu, co dzieje sie na VPS OANDA MT5 i TMS Brokers,
- innowacje i cleanup sa wazne tylko wtedy, gdy wzmacniaja kapital, realizm testow albo wynik scalpingu.

## Kto moze robic co

- wszystkie taski maja byc przypisane do konkretnej brygady,
- Codex pozostaje wykonawca bazowym i moze robic prace kazdej brygady,
- kazda brygada moze wykonac prace spoza swojej specjalizacji, jezeli dostanie takie polecenie,
- mimo tego task powinien byc przypisany do actor_id brygady, zeby taskboard zostal czytelny i audytowalny.

## Jak czytac nowe wiadomosci

- wszystkie brygady czytaja nowe notatki z mostu,
- to, ze brygada przeczytala note, nie znaczy jeszcze, ze ma ja wykonywac,
- wykonanie nalezy do brygady albo actor_id wskazanego jako adresat,
- brygady niebedace adresatem maja tryb: przeczytaj, zrozum, nie wykonuj bez jawnego tasku albo polecenia operatora,
- kazda brygada przed wykonaniem ocenia, czy polecenie jest bezpieczne, zgodne z kontraktami kapitalowymi, nie jest sprzeczne z aktualnym stanem systemu i nie wykracza poza zdrowy sens,
- jezeli polecenie jest destrukcyjne, sprzeczne albo ryzykowne, brygada nie wykonuje go slepo, tylko eskaluje przez note, task albo warning,
- jezeli note albo task jest skierowany do Codexa i przechodzi ocene bezpieczenstwa, Codex ma je nie tylko otworzyc, ale i wykonac.

## Kolejnosc brygad

- [01 BRYGADA ML I MIGRACJA MT5](01_BRYGADA_ML_MT5__ONNX_QDM_GOTOWOSC_MIGRACJA.md) - actor_id: `brygada_ml_migracja_mt5` - ONNX, QDM, gotowosc modeli i migracja do MT5.
- [02 BRYGADA AUDYT I CLEANUP](02_BRYGADA_AUDYT_CLEANUP__RESIDUE_ARTEFAKTY_HIGIENA.md) - actor_id: `brygada_audyt_cleanup` - residue, stare artefakty i higiena repo.
- [03 BRYGADA WDROZENIA MT5](03_BRYGADA_WDROZENIA_MT5__PACKAGE_INSTALL_VALIDATE.md) - actor_id: `brygada_wdrozenia_mt5` - package, install i validate.
- [04 BRYGADA ROZWOJ KODU](04_BRYGADA_ROZWOJ_KODU__MQL5_HELPERY_BUGFIXY_KOMPILACJA.md) - actor_id: `brygada_rozwoj_kodu` - MQL5, helpery, bugfixy i kompilacja.
- [05 BRYGADA ARCH I INNOWACJE](05_BRYGADA_ARCH_INNOWACJE__KONCEPCJE_KONTRAKTY_PRZEPLYWY.md) - actor_id: `brygada_architektura_innowacje` - koncepcje, kontrakty i przeplywy.
- [06 BRYGADA NADZOR UCZENIA](06_BRYGADA_NADZOR_UCZENIA__HEALTH_OVERLAY_GONOGO.md) - actor_id: `brygada_nadzor_uczenia_rolloutu` - learning health, overlay i go/no-go.
- [07 HANDOFF BRYGAD](07_HANDOFF_BRYGAD.md) - zasady przekazywania taskow miedzy brygadami.
- [08 PLAN BRYGAD 20260329](08_PLAN_BRYGAD_20260329.md) - aktualny backlog operacyjny wszystkich lane'ow.

## Glowna zasada

Jedna rozmowa albo agent bierze jedna brygade na sesje.

Nie mieszamy lane'ow typu:

- troche cleanupu,
- troche wdrozen,
- troche ML,
- troche architektury

w jednym watku roboczym, jezeli da sie to rozdzielic.

## Szybkie komendy

Status wszystkich brygad i taskow pogrupowanych po brygadach:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_TASKBOARD.ps1 -ByBrigade
```

Podglad wszystkich brygad:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_BRIGADES.ps1
```

Szczegoly jednej brygady:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_BRIGADES.ps1 -BrigadeId rozwoj_kodu
```

Zlecenie tasku brygadzie:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\ASSIGN_ORCHESTRATOR_BRIGADE_TASK.ps1 -BrigadeId audyt_cleanup -Title "Sprawdz stare artefakty" -SourceActor brygada_rozwoj_kodu -ReportPath ".\README.md"
```

Przekazanie zadania od jednej brygady do drugiej z note plus task:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\HANDOFF_ORCHESTRATOR_BRIGADE_TASK.ps1 -FromBrigadeId rozwoj_kodu -ToBrigadeId audyt_cleanup -Title "Cleanup residue po starych instrumentach" -Instructions "Znalazlem stare slady i prosze o cleanup." -ReportPath ".\README.md"
```

Raport wyniku po wykonaniu albo blokadzie:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1 -TaskId <task_id> -Actor brygada_rozwoj_kodu -Outcome COMPLETED -Summary "Zmiana wdrozona i skompilowana." -NextAction "Przekazac do wdrozen MT5."
```

Pauza brygady:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\SET_ORCHESTRATOR_BRIGADE_STATE.ps1 -BrigadeId ml_migracja_mt5 -DesiredState PAUSED -Reason "Pauza operatorska"
```

Wznowienie brygady:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\SET_ORCHESTRATOR_BRIGADE_STATE.ps1 -BrigadeId ml_migracja_mt5 -DesiredState RUNNING
```

Ręczny bootstrap standing-taskow brygad:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\START_ORCHESTRATOR_BRIGADE_AUTOSTART.ps1
```

## Gdzie jest rejestr prawdy

- `CONFIG/orchestrator_brigades_registry_v1.json`
- `TOOLS/orchestrator/ORCHESTRATOR_BRIGADES_PL.md`

## Co dalej

Kliknij konkretna brygade po lewej stronie i pracuj juz w jej lane.

Przy kazdym otwarciu folderu VS Code workspace uruchamia autostart brygad przez `.vscode/tasks.json`, chyba ze dana brygada ma stan `PAUSED`.
