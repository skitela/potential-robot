# JAK BRYGADY PRZEKAZUJA ZADANIA

Najwazniejsza zasada: brygady nie przekazuja sobie roboty tylko w rozmowie. Robia to przez note plus task.

Kazde zadanie powinno pozostac przypisane do konkretnej brygady, nawet jezeli wykonuje je Codex albo inna brygada na polecenie operatora.

Nowa zasada operacyjna:

- wszystkie brygady czytaja note handoffowa,
- wykonuje tylko brygada docelowa po review bezpieczenstwa, kapitalu i zgodnosci z zasadami scalpingu,
- tylko execution owner moze zrobic dalszy handoff do kolejnej brygady,
- po wykonaniu, blokadzie albo delegacji execution owner publikuje note wynikowa dla wszystkich brygad i dla Codexa, a raport zwrotny domyslnie wraca do Codexa.

Druga zasada: handoff i note sa widoczne dla wszystkich brygad, ale wykonanie nalezy tylko do brygady wskazanej jako adresat albo wlasciciel tasku.

Trzecia zasada: adresat nie wykonuje polecenia slepo. Najpierw sprawdza, czy:

- polecenie jest bezpieczne,
- nie lamie kontraktow kapitalowych i sesyjnych,
- nie jest sprzeczne z aktywnym stanem systemu,
- i ma sens w aktualnym lane pracy.

Jesli nie, robi eskalacje zamiast bezmyslnego wykonania.

## Gdy jedna brygada znajduje problem u drugiej

Przyklad:

- brygada rozwoj kodu znajduje stare artefakty po usunietych instrumentach,
- nie czyści tego sama po calym repo,
- przekazuje zadanie do brygady audyt i cleanup.

## Gotowa komenda

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\HANDOFF_ORCHESTRATOR_BRIGADE_TASK.ps1 -FromBrigadeId rozwoj_kodu -ToBrigadeId audyt_cleanup -Title "Cleanup residue po starych instrumentach" -Instructions "W MQL5 i raportach znalazlem stare slady. Przejrzyj EVIDENCE, LOGS, BACKUP i dokumenty." -ReportPath ".\README.md" -ScopePaths "EVIDENCE","LOGS","BACKUP"
```

## Co robi ten wrapper

1. Zapisuje note handoffowy do `notes/inbox`.
2. Zaklada task dla docelowej brygady.
3. Ustawia `SourceActor` na brygade zglaszajaca.
4. Oznacza note jako targetowana dla konkretnej brygady i widoczna dla wszystkich lane'ow.
5. Zostawia audytowalny slad, kto komu i co przekazal.
6. Oznacza, kto tylko czyta, a kto jest wykonawca po review.
7. Ustawia Codexa jako domyslnego odbiorce raportu zwrotnego, chyba ze operator jawnie wskazal inaczej.

## Kiedy uzywac

- gdy kod znajdzie residue albo stare artefakty,
- gdy ML potrzebuje rolloutu,
- gdy wdrozenia wykryja brak readiness,
- gdy architektura chce zlecic konkretna implementacje,
- gdy nadzor blokuje przejscie i chce tasku naprawczego,
- gdy brygada uczaca albo nadzor uczenia wskazuje pilny task pod ochrone kapitalu lub aktywne instrumenty.

## Kiedy nie uzywac

- do drobnego pytania bez pracy,
- do zmian w swoim wlasnym lane,
- zamiast claimu, gdy dotykasz wspolnych plikow.

## Jak zamknac wynik po wykonaniu

Po wykonaniu, blokadzie albo delegacji execution owner publikuje note wynikowa dla wszystkich brygad i dla Codexa:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1 -TaskId <task_id> -Actor brygada_audyt_cleanup -Outcome COMPLETED -Summary "Cleanup zakonczony, residue usuniete." -NextAction "Brak dalszych krokow."
```

Gdy brygada nadzoru zbiera relacje zbiorcza, warto uzupelnic tez:

- `-Checked` co sprawdzono,
- `-Confirmed` co potwierdzono,
- `-Blockers` co nadal blokuje,
- `-DelegateWork` co trzeba zlecic dalej,
- `-CodexAction` czy Codex ma wejsc z implementacja.

Jesli zamykasz task przez wrapper kompletacji, mozesz od razu dolaczyc note wynikowa:

```powershell
pwsh -File C:\MAKRO_I_MIKRO_BOT\RUN\COMPLETE_ORCHESTRATOR_PARALLEL_TASK.ps1 -TaskId <task_id> -Actor brygada_audyt_cleanup -Outcome COMPLETED -Notes "Cleanup zakonczony." -PublishResultNote -Checked "EVIDENCE","LOGS","BACKUP" -Confirmed "stare residue oznaczone" -Blockers "brak" -DelegateWork "brak" -CodexAction "nie" -NextAction "Brak dalszych krokow."
```
