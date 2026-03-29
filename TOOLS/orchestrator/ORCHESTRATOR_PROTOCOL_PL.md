# Protokol Pracy Orchestratora

Ten dokument ustala prosty, przewidywalny obieg miedzy:

- Codex / operator
- Orchestrator Chrome <-> GPT-5.4 Pro
- katalogiem `C:\Users\skite\Desktop\strojenie agenta\orchestrator_mailbox`

## Cel

Nie klikamy chaotycznie po dwoch interfejsach. Zamiast tego kazda wymiana ma:

- identyfikator requestu
- plik tresci `.md`
- metadane `.json`
- status
- odpowiedz gotowa do importu

## Struktura skrzynki

- `requests\pending`
- `requests\in_progress`
- `requests\done`
- `requests\failed`
- `coordination\claims\active`
- `coordination\claims\released`
- `coordination\activity`
- `ack\executor`
- `ack\reviewer`
- `responses\ready`
- `responses\consumed`
- `responses\archive`
- `responses\extracted`
- `notes\inbox`
- `notes\archive`
- `status`
- `logs`

## Ograniczenie produktu GPT-5.4 Pro

Produkt przegladarkowy GPT-5.4 Pro nie ma bezposredniego dostepu do lokalnego systemu plikow operatora.
W praktyce oznacza to, ze sam z siebie nie zapisze pliku do `orchestrator_mailbox` i nie uruchomi lokalnego PowerShella.

Dlatego zapis do mostu moze nastapic tylko przez:

- warstwe automatyczna Orchestratora Chrome DevTools,
- lokalny import reczny odpowiedzi z clipboard albo pliku,
- albo manualne pobranie tresci i wstrzykniecie jej do mailboxa przez lokalny skrypt.

## Jednostka pracy

Pojedynczy request sklada sie z:

- `YYYYMMDD_HHMMSS_nazwa.md`
- `YYYYMMDD_HHMMSS_nazwa.json`

Plik `.md` zawiera tresc wysylana do GPT.
Plik `.json` zawiera metadane:

- `request_id`
- `title`
- `source_path`
- `source_file_name`
- `source_sha256`
- `extra_instructions_present`
- `queued_at_local`
- opcjonalnie: `topic`, `phase`, `source_role`, `target_role`, `attachments`, `requires_ack_from`, `status`

## Przejscia stanu

1. `pending`
   Request czeka na obsluge.

2. `in_progress`
   Orchestrator przeniosl request do obslugi i probuje wyslac go do GPT.

3. `done`
   Tresc zostala wyslana, odpowiedz odebrana i zapisana.

4. `failed`
   Wysylka lub odbior nie powiodly sie. Request nie znika, tylko trafia do katalogu bledu.

5. `responses\ready`
   Odpowiedz czeka na przeczytanie przez Codex / operatora.

6. `responses\consumed`
   Odpowiedz zostala odebrana i odlozona do archiwum roboczego.

7. `ack`
   Strony moga zostawic jawny sygnal, ze odpowiedz zostala przeczytana albo krok zostal wykonany.

8. `notes`
   Wspolne notatki robocze z obu stron, publikowane recznie albo automatycznie z blokow FILE.

9. `coordination\claims`
   Jawne zajecie zakresu pracy z TTL, zeby dwa strumienie pracy nie wchodzily sobie na te same pliki albo ten sam raport.

## Koordynacja pracy rownoleglej

Jesli Codex i drugi strumien pracy maja dzialac rownolegle na tym samym repo, nie polegamy na "pamieci rozmowy". Polegamy na lokalnych claimach i notatkach.

Jezeli chcesz zrobic z tego staly model wielobrygadowy, to role musza byc zdefiniowane jawnie w rejestrze brygad, a nie wymyslane za kazdym razem od nowa:

- `CONFIG\orchestrator_brigades_registry_v1.json`
- `TOOLS\orchestrator\ORCHESTRATOR_BRIGADES_PL.md`

W takim trybie `Actor` i `AssignedTo` dla prac lane'owych powinny uzywac `actor_id` z tego rejestru.

Minimalny rytm bezkolizyjny:

1. Strona bioraca zadanie robi claim przez `CLAIM_ORCHESTRATOR_WORK.ps1`.
2. Druga strona sprawdza `GET_ORCHESTRATOR_WORKBOARD.ps1` zanim wejdzie w ten sam raport albo te same pliki.
3. Postep i handoff ida przez `WRITE_ORCHESTRATOR_NOTE.ps1` albo przez odpowiedzi z blokami `notes\...`.
4. Po zakonczeniu zakresu claim jest zwalniany przez `RELEASE_ORCHESTRATOR_WORK.ps1`.

To nie daje wspolnej swiadomosci w czasie rzeczywistym, ale daje szybka i audytowalna koordynacje lokalna.

## Podzial jednej duzej roboty na dwa tory

To jest wariant pod twoj scenariusz: jedna strona robi koncept / implementacje, druga w tym samym czasie robi audyt, test albo monitoring.

Przyklad rytmu:

1. Strona prowadzaca bierze claim przez `CLAIM_ORCHESTRATOR_WORK.ps1` na glowny raport i glowny zakres plikow.
2. Ta sama strona tworzy task rownolegly przez `ASSIGN_ORCHESTRATOR_PARALLEL_TASK.ps1` dla drugiego toru, np. `audit`, `runtime-check`, `regression-review`.
3. Drugi tor startuje swoje zadanie przez `START_ORCHESTRATOR_PARALLEL_TASK.ps1`.
4. W trakcie dluzszego przebiegu zapisuje heartbeat lub status przez `WRITE_ORCHESTRATOR_ACTIVITY.ps1`.
5. `GET_ORCHESTRATOR_TASKBOARD.ps1` pokazuje, czy zadanie jest aktywne, zablokowane albo stale.
6. Po zakonczeniu zadanie jest domykane przez `COMPLETE_ORCHESTRATOR_PARALLEL_TASK.ps1`.

Tak da sie zrobic model: `chat robi koncept / zmiany`, a `codex robi audit`, albo odwrotnie.

Tak samo da sie zrobic model wielu brygad, np. osobny lane dla `brygada_ml_migracja_mt5`, `brygada_audyt_cleanup`, `brygada_wdrozenia_mt5`, `brygada_rozwoj_kodu`, `brygada_architektura_innowacje`, `brygada_nadzor_uczenia_rolloutu`.

Zasada operacyjna jest prosta:

1. Jedna rozmowa albo agent bierze jedna brygade na sesje.
2. Brygada publikuje claimy, taski i heartbeat pod swoim `actor_id`.
3. Handoff do innej brygady musi zostawic note plus task.
4. Globalne veto nadal nalezy do warstw kapitalowo-sesyjnych, a nie do pojedynczej brygady.

## Zasady operacyjne

### 1. Nie kasujemy requestow ani odpowiedzi bez sladu

Kazda operacja ma zostawic:

- log
- status
- albo archiwum odpowiedzi

### 2. Nie zakladamy, ze GPT zawsze odda jeden plik

Jezeli GPT zwroci odpowiedz w formacie:

````text
FILE: relative/path.ext
```lang
...
```
````

to Orchestrator rozbija to do:

- `responses\extracted\<request_id>\...`

Jesli prefiks pliku to `notes\`, `shared_notes\` albo `bridge_notes\`, tresc jest dodatkowo publikowana do `notes\inbox` jako wspolna notatka.

### 3. Nie laczymy warstwy transportu z warstwa wdrozenia

Orchestrator:

- transportuje prompt
- odbiera odpowiedz
- archiwizuje i znakuje stan

Codex / operator:

- czyta odpowiedz
- ocenia ja
- wdraza albo odrzuca

### 4. Bledy sa jawne

Najwazniejsze pliki statusowe:

- `status\codex_last_request.json`
- `status\gpt_last_response.json`
- `status\orchestrator_error.json`
- `status\orchestrator_heartbeat.json`
- `status\launcher_latest.json`
- `status\orchestrator_transport.json`

### 5. Retry i failover requestu

- WebSocket do Chrome DevTools ma lekki retry / backoff po stronie Pythona.
- Przy bledzie transportowym request nie znika: przechodzi do `failed` z czytelnym powodem.
- Przy bledzie 403 operator dostaje wprost wskazowke, ze problem dotyczy `remote-allow-origins` albo zlego profilu Chrome.

### 6. Dedykowany profil Chrome jest obowiazkowy

Launcher uruchamia Chrome z:

- `--remote-debugging-port=9222`
- `--remote-debugging-address=127.0.0.1`
- `--remote-allow-origins=http://127.0.0.1:9222,http://localhost:9222`
- `--user-data-dir=<profil_orchestratora>`

Ten profil jest oddzielony od zwyklych okien Chrome, zeby nie mieszac sesji operatora z sesja Orchestratora.

## Minimalny rytm pracy

1. Codex zapisuje raport / pytanie do pliku.
2. `QUEUE_FILE_FOR_GPT54_PRO.ps1` wrzuca request do `pending`.
3. Orchestrator w trybie `run` albo `process-once` obsluguje request.
4. `IMPORT_GPT54_READY_RESPONSE.ps1` pokazuje odpowiedz i opcjonalnie odkłada ja do `consumed`.
5. Codex wdraza zmiany albo generuje kolejny request.
6. `RUN_ORCHESTRATOR_SMOKE_TEST.ps1` daje szybka walidacje end-to-end po zmianach w moscie.

Sciezka reczna, gdy GPT-5.4 Pro odpowiedzial tylko w przegladarce:

1. Operator kopiuje odpowiedz albo pobiera ja do pliku.
2. `IMPORT_GPT54_MANUAL_RESPONSE.ps1` zapisuje odpowiedz do `responses\ready`.
3. Ten sam skrypt publikuje ewentualne `notes\...` do `notes\inbox`.
4. Status `gpt_last_response.json` i `gpt_inbox_latest.json` zostaje odswiezony tak samo jak w trybie automatycznym.

W bardziej dojrzalej wersji:

1. `executor` i / lub `reviewer` zostawiaja pliki ACK w `ack\...`

## Co uwazamy za sukces

Udany cykl to taki, w ktorym:

- request przeszedl do `done`
- odpowiedz jest w `responses\ready`
- opcjonalne pliki dodatkowe sa w `responses\extracted`
- nie ma aktywnego bledu w `orchestrator_error.json`
- smoke test zapisuje `orchestrator_smoke_latest.json` z `smoke_ok = true`

## Co uwazamy za rzecz do poprawy

- brak stabilnego selektora DOM po stronie ChatGPT
- brak osobnego helpera do budowania requestu z gotowego raportu Codex
- brak jeszcze automatycznego mostu z odpowiedzi GPT do konkretnego wdrozenia w repo

To sa juz kolejne etapy rozwoju, nie blokery obecnej wersji.

## Smoke test operatorski

Smoke test tworzy prosty prompt z oczekiwanym tokenem:

```text
RECEIVED: YES
TOKEN: ORCH_SMOKE_OK_20260328
MODE: REVIEWER
TOPIC: MAKRO_I_MIKRO_BOT
NEXT_STEP: READY_FOR_NEXT_REQUEST
```

Skrypt:

- kolejkuje prompt,
- uruchamia `process-once`,
- odbiera odpowiedz,
- sprawdza dokladny token,
- zapisuje wynik do:
  - `C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\orchestrator_smoke_latest.json`
  - `C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\orchestrator_smoke_latest.md`
