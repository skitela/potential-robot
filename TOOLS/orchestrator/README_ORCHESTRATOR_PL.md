# Orchestrator Codex <-> GPT-5.4 Pro

To jest dodatkowy mechanizm wspolpracy oparty o:

- plikowa skrzynke wymiany w `C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox`
- automatyzacje ChatGPT w Chrome przez `Chrome DevTools Protocol`
- archiwizacje promptow i odpowiedzi
- wspolne notatki w `notes\inbox`
- jawne claimy pracy w `coordination\claims`

## Kluczowe ograniczenie produktu GPT-5.4 Pro

GPT-5.4 Pro w przegladarkowej rozmowie nie ma natywnego dostepu do twojego lokalnego dysku.
To oznacza, ze sam produkt webowy:

- nie uruchomi lokalnego PowerShella,
- nie zapisze arbitralnego pliku bezposrednio do `orchestrator_mailbox`,
- nie wykona lokalnego API IDE tak jak agent pracujacy w repo.

Dlatego realny zapis na dysk musi przejsc przez jedna z warstw lokalnych:

- Orchestrator Chrome DevTools, ktory odbiera odpowiedz i zapisuje ja do mailboxa,
- reczny import odpowiedzi przez PowerShell,
- albo zwykle pobranie / skopiowanie tresci i wstrzykniecie jej do mailboxa lokalnym skryptem.

To nie jest brak "inteligencji" GPT-5.4 Pro, tylko ograniczenie produktu webowego i jego uprawnien do lokalnego systemu plikow.

## Co robi ta wersja

Ta wersja automatyzuje:

1. odczyt plikow z kolejki `requests\pending`
2. otwarcie / znalezienie watku ChatGPT
3. wyslanie tresci promptu do wskazanego watku
4. poczekanie na stabilna odpowiedz
5. zapis odpowiedzi do `responses\ready`
6. parsowanie odpowiedzi do wielu plikow, jesli GPT odpowie w formacie:

````text
FILE: nazwa_pliku.ext
```lang
...zawartosc...
```
````

1. zapis statusu i manifestu

## Czego ta wersja nie robi automatycznie

Ta wersja **nie steruje bezposrednio oknem rozmowy Codex w VS Code**.
To jest celowe.

Powod:

- nie mamy tu stabilnego API do tej rozmowy,
- automatyzacja UI VS Code bylaby znacznie bardziej krucha niz wymiana plikowa,
- plikowy mailbox jest bardziej odporny i latwiejszy do audytu.

Czyli rekomendowany obieg jest taki:

1. Codex zapisuje raport / pytanie / prompt do pliku
2. helper `QUEUE_FILE_FOR_GPT54_PRO.ps1` wrzuca to do kolejki
3. orchestrator wysyla to do GPT-5.4 Pro
4. odpowiedz wraca do `responses\ready`
5. Codex czyta odpowiedz z pliku i wdraza zmiany

Teraz dochodzi tez bezpieczny odbior:

1. `IMPORT_GPT54_READY_RESPONSE.ps1` pokazuje najnowsza odpowiedz i moze odlozyc ja do `responses\consumed`
1. `BUILD_CODEX_REQUEST_FROM_REPORT.ps1` buduje request bezposrednio z raportu technicznego
1. `START_ORCHESTRATOR_RESPONSE_WATCH.ps1` stale nasluchuje nowych odpowiedzi i zapisuje sygnal do `status\gpt_inbox_latest.json`
1. `START_ORCHESTRATOR_AUTOFLOW.ps1` podnosi w tle obie petle naraz: wysylke i nasluch odpowiedzi
1. `IMPORT_GPT54_MANUAL_RESPONSE.ps1` pozwala recznie zassac odpowiedz GPT-5.4 Pro z pliku albo schowka do tego samego mailboxa
1. `WRITE_ORCHESTRATOR_NOTE.ps1` i `GET_ORCHESTRATOR_NOTES.ps1` obsluguja wspolne notatki w moscie
1. `QUEUE_TEXT_FOR_GPT54_PRO.ps1` pozwala wrzucac do kolejki czysty tekst albo clipboard bez tworzenia pliku zrodlowego

## Struktura katalogow

Po uruchomieniu tworzone sa m.in.:

- `requests\pending`
- `requests\in_progress`
- `requests\done`
- `requests\failed`
- `requests\hold`
- `responses\ready`
- `responses\consumed`
- `responses\archive`
- `responses\extracted`
- `notes\inbox`
- `notes\archive`
- `ack\executor`
- `ack\reviewer`
- `status`
- `logs`

## Szybki start

### Jedno miejsce do klikania

Jesli chcesz obslugiwac ten most z jednego miejsca, bez pamietania nazw skryptow:

1. Dwukliknij `C:\MAKRO_I_MIKRO_BOT\URUCHOM_GPT54_PRO_MOST.cmd`
2. W panelu kliknij `1. Start most i otworz GPT-5.4 Pro`
3. Gdy chcesz przeniesc aktualny tekst do warstwy komunikacji, skopiuj go i kliknij `3. Wyslij schowek do warstwy komunikacji`
4. Gdy masz odpowiedz GPT-5.4 Pro do wstrzykniecia z powrotem, kliknij `9. Importuj odpowiedz ze schowka`
5. Jesli chcesz z tego samego miejsca odebrac gotowa odpowiedz z mailboxa, kliknij `6. Pokaz najnowsza gotowa odpowiedz`
6. Jesli chcesz miec trwaly punkt klikniecia na pulpicie, kliknij `13. Utworz skrot na pulpicie`
7. Jesli chcesz sprawdzic, czy odpowiedz nadaje sie do dalszego wdrozenia, kliknij `7. Waliduj najnowsza gotowa odpowiedz`
8. Jesli chcesz domknac obieg i odlozyc odpowiedz do archiwum `consumed`, kliknij `8. Archiwizuj najnowsza gotowa odpowiedz`
9. Jesli chcesz z tego samego panelu sterowac brygadami, wybierz lane w polu `Wybrana brygada`, a potem uzyj `15. Szczegoly brygady`, `16. Taskboard brygad`, `17. Pauza brygady`, `18. Wznow brygade` albo `19. Autostart brygad`.

To jest najszybsza sciezka pracy w jednym miejscu.

### Rownolegla praca bez wchodzenia sobie w droge

Jesli dwa strumienie pracy maja dzialac rownolegle na tym samym repo i tym samym raporcie, uzyj lokalnej warstwy claims:

1. `CLAIM_ORCHESTRATOR_WORK.ps1` zajmuje zakres pracy na raport albo konkretne sciezki.
2. `GET_ORCHESTRATOR_WORKBOARD.ps1` pokazuje aktywne i wygasle claimy.
3. `RELEASE_ORCHESTRATOR_WORK.ps1` zwalnia claim po zakonczeniu zakresu.
4. Szczegoly postepu nadal ida przez `WRITE_ORCHESTRATOR_NOTE.ps1` i `GET_ORCHESTRATOR_NOTES.ps1`.

To jest najbezpieczniejszy sposob, zeby Codex i drugi tor pracy wymieniali informacje szybciej i nie dotykali tego samego zakresu przez przypadek.

Jesli claim jest zwiazany z juz zalozonym taskiem, przekaz `-TaskId` do `CLAIM_ORCHESTRATOR_WORK.ps1`.
Wtedy task zostanie automatycznie podniesiony do `ACTIVE` razem z claime.

Jesli chcesz podzielic jedna duza robote na dwa tory, uzyj taskboardu rownoleglego:

Jesli chcesz podzielic caly system na stale brygady, nie wymyslaj actorow ad hoc. Uzyj jawnego rejestru brygad:

- `CONFIG\orchestrator_brigades_registry_v1.json`
- `TOOLS\orchestrator\ORCHESTRATOR_BRIGADES_PL.md`
- `RUN\GET_ORCHESTRATOR_BRIGADES.ps1`
- `RUN\ASSIGN_ORCHESTRATOR_BRIGADE_TASK.ps1`

Najwazniejsza zasada: `Actor` i `AssignedTo` dla lane'ow wielobrygadowych powinny brac `actor_id` z rejestru brygad, np. `brygada_rozwoj_kodu`, `brygada_audyt_cleanup`, `brygada_ml_migracja_mt5`.

Szybki podglad brygad:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_BRIGADES.ps1
```

Taskboard pogrupowany po brygadach:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_TASKBOARD.ps1 -ByBrigade
```

Pauza albo wznowienie jednej brygady:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\SET_ORCHESTRATOR_BRIGADE_STATE.ps1 -BrigadeId ml_migracja_mt5 -DesiredState PAUSED -Reason "Pauza operatorska"
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\SET_ORCHESTRATOR_BRIGADE_STATE.ps1 -BrigadeId ml_migracja_mt5 -DesiredState RUNNING
```

Przydzial tasku do brygady przez wrapper:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\ASSIGN_ORCHESTRATOR_BRIGADE_TASK.ps1 -BrigadeId rozwoj_kodu -Title "Dopnij poprawke MQL5" -SourceActor brygada_architektura_innowacje -ReportPath "C:\MAKRO_I_MIKRO_BOT\README.md"
```

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\ASSIGN_ORCHESTRATOR_PARALLEL_TASK.ps1 -Title "Audit zmian po koncepcie" -AssignedTo codex -SourceActor gpt54_pro -RequestId "20260329_120000_BIG_TASK" -ParentClaimId "20260329_115225_codex_MicroBot_EURUSD_patch" -ReportPath "C:\MAKRO_I_MIKRO_BOT\README.md" -ScopePaths "MQL5/Experts/MicroBots/MicroBot_EURUSD.mq5" -Instructions "Sprawdz regresje i ryzyka po zmianach koncepcyjnych"
```

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\START_ORCHESTRATOR_PARALLEL_TASK.ps1 -TaskId "20260329_120500_codex_Audit_zmian_po_koncepcie" -Actor codex -Notes "Start audytu"
```

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\WRITE_ORCHESTRATOR_ACTIVITY.ps1 -Actor codex -TaskId "20260329_120500_codex_Audit_zmian_po_koncepcie" -Title "Halfway audit" -Notes "Sprawdza runtime i grep skali zmian"
```

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_TASKBOARD.ps1 -ShowDone
```

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\COMPLETE_ORCHESTRATOR_PARALLEL_TASK.ps1 -TaskId "20260329_120500_codex_Audit_zmian_po_koncepcie" -Actor codex -Outcome COMPLETED -Notes "Audyt zakonczony"
```

Przykladowe komendy:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\CLAIM_ORCHESTRATOR_WORK.ps1 -Actor codex -TaskId "20260329_120500_codex_Audit_zmian_po_koncepcie" -WorkTitle "MicroBot EURUSD patch" -ReportPath "C:\MAKRO_I_MIKRO_BOT\README.md" -ScopePaths "MQL5/Experts/MicroBots/MicroBot_EURUSD.mq5","TOOLS/orchestrator/README_ORCHESTRATOR_PL.md" -Notes "Bierze tylko EURUSD i README mostu"
```

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_WORKBOARD.ps1
```

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\RELEASE_ORCHESTRATOR_WORK.ps1 -ClaimId "20260329_115225_codex_MicroBot_EURUSD_patch" -Outcome COMPLETED -ReleaseNotes "Zakres zakonczony i oddany"
```

1. Uruchom Chrome przez launcher:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\START_CHATGPT_CODEX_ORCHESTRATOR.ps1 -Mode open-chat
```

1. Jesli to pierwszy raz, zaloguj sie recznie do ChatGPT w otwartym profilu Chrome.

1. Uruchom petle:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\START_CHATGPT_CODEX_ORCHESTRATOR.ps1 -Mode run
```

1. Wrzuć plik do kolejki:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\QUEUE_FILE_FOR_GPT54_PRO.ps1 -SourcePath "C:\Users\skite\Desktop\strojenie agenta\PROMPT_GPT54_PRO_KONCEPCYJNE_ULEPSZENIA_NOWEGO_STOSU_ML_v1.md" -Title "Analiza i plan"
```

1. Odbierz najnowsza odpowiedz:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\IMPORT_GPT54_READY_RESPONSE.ps1
```

Wariant reczny: jesli odpowiedz GPT-5.4 Pro masz tylko w oknie przegladarki albo w pobranym pliku, a nie przez DevTools, zaimportuj ja recznie:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\IMPORT_GPT54_MANUAL_RESPONSE.ps1 -FromClipboard
```

albo:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\IMPORT_GPT54_MANUAL_RESPONSE.ps1 -ResponsePath "C:\Users\skite\Desktop\strojenie agenta\gpt_odpowiedz.md" -RequestId "20260329_101010_TWOJ_REQUEST"
```

1. Jesli chcesz stalego nasluchu odpowiedzi:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\START_ORCHESTRATOR_RESPONSE_WATCH.ps1 -Mode run
```

1. Jesli chcesz uruchomic obie petle naraz w tle:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\START_ORCHESTRATOR_AUTOFLOW.ps1
```

1. Uruchom kontrolowany smoke test end-to-end:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\RUN_ORCHESTRATOR_SMOKE_TEST.ps1
```

1. Jesli chcesz przetworzyc tylko jeden request, zamiast stalej petli:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\START_CHATGPT_CODEX_ORCHESTRATOR.ps1 -Mode process-once
```

1. Jesli wiadomosc zostala wyslana, ale odbior odpowiedzi urwal sie po stronie DevTools, odzyskaj ostatnia odpowiedz z zywego watku:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\START_CHATGPT_CODEX_ORCHESTRATOR.ps1 -Mode recover-last-response
```

1. Jesli chcesz zbudowac request z gotowego raportu Codex:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_CODEX_REQUEST_FROM_REPORT.ps1 -ReportPath "C:\Users\skite\Desktop\strojenie agenta\raport.md" -Title "Diagnoza i plan" -Phase analysis
```

1. Jesli chcesz od razu wrzucic do kolejki sama tresc albo clipboard, bez posredniego pliku:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\QUEUE_TEXT_FOR_GPT54_PRO.ps1 -FromClipboard -Title "Analiza koncepcyjna" -CopyToClipboard
```

1. Jesli chcesz zapisac wspolna notatke do mostu:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\WRITE_ORCHESTRATOR_NOTE.ps1 -Title "Notatka do GPT i Codex" -FromClipboard -Author codex
```

1. Jesli chcesz zobaczyc ostatnie notatki:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\GET_ORCHESTRATOR_NOTES.ps1 -Limit 10
```

## Format odpowiedzi dla GPT

Jesli chcesz, aby odpowiedz zostala automatycznie rozbita na wiele plikow, pros GPT o uzycie formatu:

````text
FILE: nazwa_pliku_1.md
```md
...
```

FILE: nazwa_pliku_2.ps1
```powershell
...
```
````

Wtedy orchestrator zapisze te pliki do:

- `responses\extracted\<request_id>\...`

Jesli plik trafi pod prefiks:

- `notes\...`
- `shared_notes\...`
- `bridge_notes\...`

to odpowiedz zostanie dodatkowo opublikowana jako wspolna notatka w `notes\inbox`.

## Uwagi praktyczne

- Jesli `latest.json` na tej maszynie jest przepisywany w tej samej chwili, orchestrator tego nie naprawia; on tylko transportuje tresc.
- Jesli ChatGPT zmieni DOM i selektory przestana pasowac, trzeba poprawic sekcje JavaScript w `chatgpt_codex_orchestrator.py`.
- Jesli Chrome nie ma jeszcze sesji logowania, orchestrator zapisze blad `composer_not_found_or_not_logged_in`.
- Jesli problem z sesja albo chwilowa gotowoscia watku jest odzyskiwalny, request moze trafic do `requests\hold` zamiast do twardej porazki.
- Request ma teraz tez metadane `.json`, wiec mozna bezpiecznie sledzic, co wyslalismy i z jakiego pliku to pochodzilo.
- Warstwa `ack\...` jest na razie przygotowana strukturalnie; to fundament pod dojrzalszy obieg executor/reviewer.
- GPT-5.4 Pro moze byc w praktyce pelnoprawnym dostawca tresci do mostu, ale tylko przez transport lokalny: automatyczny albo reczny import. Sam produkt webowy nie wykona zapisu na dysk bez tej warstwy posredniej.

## Utwardzony launcher Chrome

Launcher:

- wykrywa Chrome w `Program Files` albo `Program Files (x86)`
- otwiera dedykowany profil przez `--user-data-dir`
- startuje DevTools na `127.0.0.1:9222`
- dodaje `--remote-allow-origins=http://127.0.0.1:9222,http://localhost:9222`
- nie miesza sie z istniejacymi oknami uzytkownika, bo otwiera osobne okno z wlasnym profilem

Status launchera trafia do:

- `orchestrator_mailbox\status\launcher_latest.json`

## Najczestsze usterki

### 403 Forbidden przy WebSocket

Objaw:

- `WebSocketBadStatusException`
- `Handshake status 403 Forbidden`

Znaczenie:

- Chrome DevTools odrzucil polaczenie z powodu origin albo zlego profilu.

Naprawa:

- uruchomic przez `START_CHATGPT_CODEX_ORCHESTRATOR.ps1`
- upewnic sie, ze dedykowany profil otworzyl poprawny thread
- nie otwierac przypadkowego Chrome bez flag debugowych na tym samym porcie

### `composer_not_found_or_not_logged_in`

Znaczenie:

- w dedykowanym profilu nie ma zalogowanej sesji ChatGPT albo DOM nie zawiera pola wpisu

Naprawa:

- uruchomic `-Mode open-chat`
- zalogowac sie recznie
- ponowic `process-once`

### `response_timeout`

Znaczenie:

- GPT nie oddal stabilnej odpowiedzi w zadanym limicie

Naprawa:

- skrocic prompt
- ponowic request
- sprawdzic czy thread nie utknal na spinnerze / stop button

### `Connection timed out`

Znaczenie:

- polaczenie DevTools urwalo sie w trakcie wysylki albo odbioru

Naprawa:

- najpierw sprawdzic, czy wiadomosc nie weszla juz do watku
- w razie potrzeby uruchomic `-Mode recover-last-response`

## Dodatkowe dokumenty

- `C:\MAKRO_I_MIKRO_BOT\TOOLS\orchestrator\ORCHESTRATOR_PROTOCOL_PL.md`
- `C:\MAKRO_I_MIKRO_BOT\TOOLS\orchestrator\ORCHESTRATOR_ROADMAP_PL.md`
- `C:\MAKRO_I_MIKRO_BOT\TOOLS\orchestrator\ORCHESTRATOR_GPT54_ALIGNMENT_PL.md`
- `C:\MAKRO_I_MIKRO_BOT\TOOLS\orchestrator\orchestrator_mailbox_schema.json`
