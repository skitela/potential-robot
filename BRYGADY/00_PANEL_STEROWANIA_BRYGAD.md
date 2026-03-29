# PANEL STEROWANIA BRYGAD

To jest szybki pulpit operatorski dla brygad. Otwieraj ten plik, gdy chcesz szybko wejsc w lane, sprawdzic status, przeczytac wspolna liste albo uruchomic sterowanie.

## Szybkie wejscia

- [00_START_BRYGADY.md](00_START_BRYGADY.md) - tablica startowa i opis modelu brygad.
- [../00_BRYGADY_TUTAJ.md](../00_BRYGADY_TUTAJ.md) - glowna tablica opisow brygad i wejsc Copilot.
- [01 BRYGADA ML I MIGRACJA MT5](01_BRYGADA_ML_MT5__ONNX_QDM_GOTOWOSC_MIGRACJA.md)
- [02 BRYGADA AUDYT I CLEANUP](02_BRYGADA_AUDYT_CLEANUP__RESIDUE_ARTEFAKTY_HIGIENA.md)
- [03 BRYGADA WDROZENIA MT5](03_BRYGADA_WDROZENIA_MT5__PACKAGE_INSTALL_VALIDATE.md)
- [04 BRYGADA ROZWOJ KODU](04_BRYGADA_ROZWOJ_KODU__MQL5_HELPERY_BUGFIXY_KOMPILACJA.md)
- [05 BRYGADA ARCH I INNOWACJE](05_BRYGADA_ARCH_INNOWACJE__KONCEPCJE_KONTRAKTY_PRZEPLYWY.md)
- [06 BRYGADA NADZOR UCZENIA](06_BRYGADA_NADZOR_UCZENIA__HEALTH_OVERLAY_GONOGO.md)
- [07 HANDOFF BRYGAD](07_HANDOFF_BRYGAD.md)
- [08 PLAN BRYGAD 20260329](08_PLAN_BRYGAD_20260329.md)
- [09 SPIS Z NATURY BRYGAD I NARZEDZI](09_SPIS_Z_NATURY_BRYGAD_I_NARZEDZI_20260329.md)

## Wejscia Copilot

- [Wejdz: BRYGADA ML I MIGRACJA MT5](../.github/prompts/wejdz-brygada-ml-migracja-mt5.prompt.md)
- [Wejdz: BRYGADA AUDYT I CLEANUP](../.github/prompts/wejdz-brygada-audyt-cleanup.prompt.md)
- [Wejdz: BRYGADA WDROZENIA MT5](../.github/prompts/wejdz-brygada-wdrozenia-mt5.prompt.md)
- [Wejdz: BRYGADA ROZWOJ KODU](../.github/prompts/wejdz-brygada-rozwoj-kodu.prompt.md)
- [Wejdz: BRYGADA ARCHITEKTURA I INNOWACJE](../.github/prompts/wejdz-brygada-architektura-innowacje.prompt.md)
- [Wejdz: BRYGADA NADZOR UCZENIA I GO-NO-GO](../.github/prompts/wejdz-brygada-nadzor-uczenia-gonogo.prompt.md)

Te prompt files otwieraja start sesji dla konkretnej brygady. Najpierw wybierasz brygade, potem pracujesz juz w jednym lane.

## Sterowanie runtime

Szybki start kontekstu jednej brygady:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_BRIGADE_START_CONTEXT.ps1 -BrigadeId rozwoj_kodu
```

Szybki odczyt nowych notatek dla jednej brygady z zapisem sladu odczytu:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\READ_ORCHESTRATOR_BRIGADE_NOTES.ps1 -BrigadeId rozwoj_kodu -Limit 10 -ShowContent
```

Automatyczna synchronizacja not mostu dla wszystkich brygad:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\SYNC_ORCHESTRATOR_BRIGADE_NOTES.ps1 -PublishToNotes
```

Otworz panel mostu z kontrolkami brygad:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\OPEN_GPT54_PRO_BRIDGE_PANEL.ps1
```

Status wszystkich brygad i taskow:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_TASKBOARD.ps1 -ByBrigade
```

Raport dzienny brygad i watch krytycznych plikow:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_BRIGADE_DAILY_STATUS.ps1
```

Raport dzienny + publikacja skrotu na wspolna liste:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_BRIGADE_DAILY_STATUS.ps1 -PublishToNotes
```

Automatyczna publikacja obu raportow na most:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\PUBLISH_BRIGADE_AUTOMATIC_REPORTS.ps1
```

Manifest spiecia brygad do kontroli przez Codexa:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_BRIGADE_SYNC_MANIFEST.ps1
```

Manifest spiecia brygad + publikacja skrotu na wspolna liste:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_BRIGADE_SYNC_MANIFEST.ps1 -PublishToNotes
```

Otworz ostatni raport:

- [../EVIDENCE/OPS/bridge_note_delivery_latest.md](../EVIDENCE/OPS/bridge_note_delivery_latest.md)
- [../EVIDENCE/OPS/bridge_note_delivery_latest.json](../EVIDENCE/OPS/bridge_note_delivery_latest.json)
- [../EVIDENCE/OPS/brigade_daily_status_latest.md](../EVIDENCE/OPS/brigade_daily_status_latest.md)
- [../EVIDENCE/OPS/brigade_daily_status_latest.json](../EVIDENCE/OPS/brigade_daily_status_latest.json)
- [../EVIDENCE/OPS/brigade_sync_manifest_latest.md](../EVIDENCE/OPS/brigade_sync_manifest_latest.md)
- [../EVIDENCE/OPS/brigade_sync_manifest_latest.json](../EVIDENCE/OPS/brigade_sync_manifest_latest.json)

## Regula obslugi nowych wiadomosci

- kazda nowa note z mostu ma byc otwarta i przeczytana,
- preferowana komenda odczytu to `RUN/READ_ORCHESTRATOR_BRIGADE_NOTES.ps1`, bo zapisuje tez receipt brygady,
- wszystkie brygady czytaja, ale wykonuje tylko adresat tasku albo note,
- jezeli adresatem jest Codex, Codex ma po review przejsc do wykonania, a nie tylko do odczytu,
- Codex jest domyslnym koordynatorem i odbiorca raportow zwrotnych z brygad,
- brygady nie zadaja sobie pytan bezposrednio; pytania, konflikty i prosby o doprecyzowanie ida do Codexa,
- kazda brygada przed wykonaniem robi review bezpieczenstwa i zgodnosci z kontraktami,
- jezeli polecenie jest destrukcyjne albo sprzeczne, brygada ma eskalowac zamiast wykonywac slepo.

## Gdzie czytac i gdzie zapisywac

- notatki wspolne: `C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox\notes\inbox`
- receipt odczytu brygady: `C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox\status\brigade_note_receipts.json`
- taski pending/active/blocked/done: `C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox\coordination\tasks\...`
- claimy robocze: `C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox\coordination\claims\active`
- wynik pracy brygady: wraca do wspolnego inboxu przez `RUN/WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1`

Lista brygad:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_BRIGADES.ps1
```

Szczegoly jednej brygady:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_BRIGADES.ps1 -BrigadeId rozwoj_kodu
```

Pauza albo wznowienie brygady:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\SET_ORCHESTRATOR_BRIGADE_STATE.ps1 -BrigadeId ml_migracja_mt5 -DesiredState PAUSED -Reason "Pauza operatorska"
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\SET_ORCHESTRATOR_BRIGADE_STATE.ps1 -BrigadeId ml_migracja_mt5 -DesiredState RUNNING
```

Autostart standing-taskow brygad:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\START_ORCHESTRATOR_BRIGADE_AUTOSTART.ps1
```

## Wspolna lista notatek

Zasada pracy z notatkami:

- wszystkie brygady czytaja nowe note,
- system powinien cyklicznie sprawdzac czy latest note z mostu ma receipt dla kazdej brygady,
- wykonuje tylko brygada wskazana jako target po safety review,
- jesli execution owner potrzebuje innej brygady, robi handoff przez note plus task,
- wynik wykonania albo blokady wraca note do wszystkich brygad i do Codexa, a Codex pozostaje domyslnym report ownerem i koordynatorem mostu.

Publikacja wyniku execution ownera:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1 -TaskId <task_id> -Actor brygada_rozwoj_kodu -Outcome COMPLETED -Summary "Poprawka wdrozona i zwalidowana." -NextAction "Przekazac do wdrozen MT5."
```

Jesli nadzor zbiera relacje zbiorcza, dodaj tez pola:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1 -TaskId <task_id> -Actor brygada_rozwoj_kodu -Outcome STATUS -Summary "Hot-path truth przejrzany." -Checked "OnTradeTransaction","send order hook" -Confirmed "candidate_id jest juz w EURUSD" -Blockers "brak live spool write w MT5" -DelegateWork "wdrozenia_mt5: test terminalowy spool" -CodexAction "tak, dopiac brakujace hooki dla aktywnej 13" -NextAction "Oddac liste brakow integracji."
```

Podglad ostatnich wpisow:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_NOTES.ps1 -Limit 10
```

Podglad najnowszej notatki z trescia:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_NOTES.ps1 -Limit 1 -ShowContent
```

## Najnowsze ustalenia Codexa ze wspolnej listy

Na dzien 2026-03-29 na wspolnej liscie byly dwa swieze wpisy autora `codex`:

- `Ocena modelu brygad i podzialu pracy 20260329`
- `Stan parity ML MT5 i MT5 truth 20260329`

Najwazniejsze wnioski organizacyjne:

- model 6 brygad jest sensowny i wart utrzymania, bo rozdziela lane produkcyjny od diagnostycznego,
- lane `rozwoj_kodu` powinien zostac glownie przy kodzie, a szerokie audyty maja isc do `audyt_cleanup` albo `nadzor_uczenia_rolloutu`,
- brygady wykonawcze powinny wystawiac claim, heartbeat i krotki handoff, a task przy realnym starcie powinien przechodzic z `PENDING` do `ACTIVE`,
- przydalby sie krotki status dzienny brygady oraz watchery na pliki krytyczne readiness i truth.

Najwazniejsze wnioski techniczne:

- parity ML -> MT5 poprawilo sie po domknieciu runtime sync i odchudzeniu importow lekkich entrypointow,
- local readiness przestal mylic stan package i runtime, ale deployment pass nadal jest `0`,
- warstwa MT5 pre-trade i execution truth jest wszczepiona, ale nadal `IMPLANTED_BUT_DORMANT`, bo terminal nie produkuje jeszcze zywych rekordow spool,
- najblizszy sensowny krok to uruchomic realny zapis spool z runtime MT5, a nie rozszerzac teraz szerokiej fali modeli.

## Mapa actor_id

- `brygada_ml_migracja_mt5`
- `brygada_audyt_cleanup`
- `brygada_wdrozenia_mt5`
- `brygada_rozwoj_kodu`
- `brygada_architektura_innowacje`
- `brygada_nadzor_uczenia_rolloutu`
