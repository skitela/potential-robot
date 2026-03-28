# Roadmap Orchestratora

To jest plan dojrzewania Orchestratora bez robienia kruchego automatu klikajacego po wszystkich oknach naraz.

## Etap 1: Transport i archiwum

Status: zrobione

Mamy juz:

- kolejke requestow do GPT-5.4 Pro
- wysylke przez Chrome DevTools
- odbior odpowiedzi
- rozbijanie odpowiedzi na wiele plikow
- statusy i logi
- helper importu odpowiedzi

## Etap 2: Protokol i rytm pracy

Status: w toku

Mamy juz:

- request `.md` + `.json`
- `process-once` do kontrolowanych przebiegow
- `responses\consumed` jako archiwum przeczytanych odpowiedzi
- szkic warstwy `ACK` w strukturze skrzynki
- helper `BUILD_CODEX_REQUEST_FROM_REPORT.ps1`

Do domkniecia:

- helper porownujacy odpowiedz GPT z ostatnim requestem
- jawne zasady priorytetu, gdy w kolejce sa dwa requesty jednoczesnie
- realne zapisy `ACK` po stronie executor/reviewer

## Etap 3: Bezpieczny most wdrozeniowy

Cel:

- nie tylko przeczytac odpowiedz GPT,
- ale przygotowac z niej bezpieczny pakiet wdrozeniowy dla Codex.

Docelowe elementy:

- walidacja formatu odpowiedzi
- lista proponowanych plikow do zmiany
- oddzielny katalog `responses\review`
- helper `BUILD_IMPLEMENTATION_BATCH.ps1`

## Etap 4: Poldautomatyczna petla Codex <-> GPT

Cel:

- ograniczyc prace reczna,
- ale nie uzalezniac sie od kruchego klikania po VS Code.

Najrozsadniejszy wariant:

- Codex tworzy raport do pliku
- helper wrzuca request
- Orchestrator pobiera odpowiedz
- helper importuje odpowiedz
- Codex wdraza i tworzy nowy raport

To nadal jest polautomatyczne, ale odporne.

## Etap 5: Opcjonalny most UI VS Code

Cel:

- tylko jesli naprawde bedzie potrzebny
- i tylko jako warstwa dodatkowa

Ryzyka:

- zmienny DOM VS Code / webview
- brak stabilnego API rozmowy
- latwe rozjechanie klikacza po aktualizacji

Wniosek:

To nie powinien byc nastepny krok. To powinien byc krok opcjonalny i pozny.

## Rekomendowany nastepny ruch

Najpierw:

1. uzywac stabilnie obecnej wersji
2. dopisac helper do budowania requestow z raportow
3. dopisac helper do walidacji odpowiedzi GPT przed wdrozeniem

Dopiero potem:

4. myslec o glębszej automatyzacji interfejsu

## Co bedzie sukcesem

- Codex i GPT-5.4 Pro wymieniaja sie pakietami bez recznego przepisywania tresci
- kazdy request ma slady, metadane i odpowiedz
- da sie przejsc wstecz po logach
- nie mieszamy transportu, diagnozy i wdrozenia w jednym kroku
