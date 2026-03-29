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

## Wejscia Copilot

- [Wejdz: BRYGADA ML I MIGRACJA MT5](../.github/prompts/wejdz-brygada-ml-migracja-mt5.prompt.md)
- [Wejdz: BRYGADA AUDYT I CLEANUP](../.github/prompts/wejdz-brygada-audyt-cleanup.prompt.md)
- [Wejdz: BRYGADA WDROZENIA MT5](../.github/prompts/wejdz-brygada-wdrozenia-mt5.prompt.md)
- [Wejdz: BRYGADA ROZWOJ KODU](../.github/prompts/wejdz-brygada-rozwoj-kodu.prompt.md)
- [Wejdz: BRYGADA ARCHITEKTURA I INNOWACJE](../.github/prompts/wejdz-brygada-architektura-innowacje.prompt.md)
- [Wejdz: BRYGADA NADZOR UCZENIA I GO-NO-GO](../.github/prompts/wejdz-brygada-nadzor-uczenia-gonogo.prompt.md)

Te prompt files otwieraja start sesji dla konkretnej brygady. Najpierw wybierasz brygade, potem pracujesz juz w jednym lane.

## Sterowanie runtime

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

Otworz ostatni raport:

- [../EVIDENCE/OPS/brigade_daily_status_latest.md](../EVIDENCE/OPS/brigade_daily_status_latest.md)
- [../EVIDENCE/OPS/brigade_daily_status_latest.json](../EVIDENCE/OPS/brigade_daily_status_latest.json)

## Regula obslugi nowych wiadomosci

- kazda nowa note z mostu ma byc otwarta i przeczytana,
- wszystkie brygady czytaja, ale wykonuje tylko adresat tasku albo note,
- jezeli adresatem jest Codex, Codex ma po review przejsc do wykonania, a nie tylko do odczytu,
- kazda brygada przed wykonaniem robi review bezpieczenstwa i zgodnosci z kontraktami,
- jezeli polecenie jest destrukcyjne albo sprzeczne, brygada ma eskalowac zamiast wykonywac slepo.

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
