# Orchestrator Codex <-> GPT-5.4 Pro

To jest dodatkowy mechanizm wspolpracy oparty o:

- plikowa skrzynke wymiany w `C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox`
- automatyzacje ChatGPT w Chrome przez `Chrome DevTools Protocol`
- archiwizacje promptow i odpowiedzi

## Co robi ta wersja

Ta wersja automatyzuje:

1. odczyt plikow z kolejki `requests\pending`
2. otwarcie / znalezienie watku ChatGPT
3. wyslanie tresci promptu do wskazanego watku
4. poczekanie na stabilna odpowiedz
5. zapis odpowiedzi do `responses\ready`
6. parsowanie odpowiedzi do wielu plikow, jesli GPT odpowie w formacie:

```text
FILE: nazwa_pliku.ext
```lang
...zawartosc...
```
```

7. zapis statusu i manifestu

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

6. `IMPORT_GPT54_READY_RESPONSE.ps1` pokazuje najnowsza odpowiedz i moze odlozyc ja do `responses\consumed`
7. `BUILD_CODEX_REQUEST_FROM_REPORT.ps1` buduje request bezposrednio z raportu technicznego

## Struktura katalogow

Po uruchomieniu tworzone sa m.in.:

- `requests\pending`
- `requests\in_progress`
- `requests\done`
- `requests\failed`
- `responses\ready`
- `responses\consumed`
- `responses\archive`
- `responses\extracted`
- `ack\executor`
- `ack\reviewer`
- `status`
- `logs`

## Szybki start

1. Uruchom Chrome przez launcher:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\START_CHATGPT_CODEX_ORCHESTRATOR.ps1 -Mode open-chat
```

2. Jesli to pierwszy raz, zaloguj sie recznie do ChatGPT w otwartym profilu Chrome.

3. Uruchom petle:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\START_CHATGPT_CODEX_ORCHESTRATOR.ps1 -Mode run
```

4. Wrzuć plik do kolejki:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\QUEUE_FILE_FOR_GPT54_PRO.ps1 -SourcePath "C:\Users\skite\Desktop\strojenie agenta\PROMPT_GPT54_PRO_KONCEPCYJNE_ULEPSZENIA_NOWEGO_STOSU_ML_v1.md" -Title "Analiza i plan"
```

5. Odbierz najnowsza odpowiedz:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\IMPORT_GPT54_READY_RESPONSE.ps1
```

8. Uruchom kontrolowany smoke test end-to-end:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\RUN_ORCHESTRATOR_SMOKE_TEST.ps1
```

6. Jesli chcesz przetworzyc tylko jeden request, zamiast stalej petli:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\START_CHATGPT_CODEX_ORCHESTRATOR.ps1 -Mode process-once
```

7. Jesli chcesz zbudowac request z gotowego raportu Codex:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_CODEX_REQUEST_FROM_REPORT.ps1 -ReportPath "C:\Users\skite\Desktop\strojenie agenta\raport.md" -Title "Diagnoza i plan" -Phase analysis
```

## Format odpowiedzi dla GPT

Jesli chcesz, aby odpowiedz zostala automatycznie rozbita na wiele plikow, pros GPT o uzycie formatu:

```text
FILE: nazwa_pliku_1.md
```md
...
```

FILE: nazwa_pliku_2.ps1
```powershell
...
```
```

Wtedy orchestrator zapisze te pliki do:

- `responses\extracted\<request_id>\...`

## Uwagi praktyczne

- Jesli `latest.json` na tej maszynie jest przepisywany w tej samej chwili, orchestrator tego nie naprawia; on tylko transportuje tresc.
- Jesli ChatGPT zmieni DOM i selektory przestana pasowac, trzeba poprawic sekcje JavaScript w `chatgpt_codex_orchestrator.py`.
- Jesli Chrome nie ma jeszcze sesji logowania, orchestrator zapisze blad `composer_not_found_or_not_logged_in`.
- Request ma teraz tez metadane `.json`, wiec mozna bezpiecznie sledzic, co wyslalismy i z jakiego pliku to pochodzilo.
- Warstwa `ack\...` jest na razie przygotowana strukturalnie; to fundament pod dojrzalszy obieg executor/reviewer.

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

## Dodatkowe dokumenty

- `C:\MAKRO_I_MIKRO_BOT\TOOLS\orchestrator\ORCHESTRATOR_PROTOCOL_PL.md`
- `C:\MAKRO_I_MIKRO_BOT\TOOLS\orchestrator\ORCHESTRATOR_ROADMAP_PL.md`
- `C:\MAKRO_I_MIKRO_BOT\TOOLS\orchestrator\ORCHESTRATOR_GPT54_ALIGNMENT_PL.md`
- `C:\MAKRO_I_MIKRO_BOT\TOOLS\orchestrator\orchestrator_mailbox_schema.json`
