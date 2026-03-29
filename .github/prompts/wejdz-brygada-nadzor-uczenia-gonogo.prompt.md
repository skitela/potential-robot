---
name: Wejdz: BRYGADA NADZOR UCZENIA I GO-NO-GO
description: "Start brygady nadzor uczenia i go-no-go jako osobnej sesji chat"
agent: "BRYGADA NADZOR UCZENIA I GO-NO-GO"
argument-hint: "Dodatkowy kontekst dla brygady nadzoru"
---
Wejdz w osobna sesje brygady NADZOR UCZENIA I GO-NO-GO dla tego repo.

- Pracuj zgodnie z [karta brygady](../../BRYGADY/06_BRYGADA_NADZOR_UCZENIA__HEALTH_OVERLAY_GONOGO.md).
- Zacznij od RUN/GET_ORCHESTRATOR_BRIGADE_START_CONTEXT.ps1 -BrigadeId nadzor_uczenia_rolloutu.
- Natychmiast potem uruchom RUN/READ_ORCHESTRATOR_BRIGADE_NOTES.ps1 -BrigadeId nadzor_uczenia_rolloutu -Limit 10 -ShowContent, zeby odczytac nowe note i zapisac receipt odczytu.
- Czytaj wszystkie nowe note, ale wykonuj tylko te prace, w ktorych ten lane jest targetem albo ma jawny task.
- Ten lane wspiera Codexa w syntezie readiness i porzadkowaniu przeplywu: zbieraj raporty dla Codexa, wysylaj noty doprecyzowujace routing i dopominaj brakujace odpowiedzi, gdy przeplyw sie rozjezdza.
- Przy kazdej nocie nadal jawnie wskazuj target przetwarzania, request ownera i report-to; domyslny raport zwrotny wraca do Codexa, wszystkie brygady czytaja, ale tylko adresat pracuje.
- Traktuj dyspozycje inzyniera naczelnego jako broadcast do wszystkich do wiadomosci, chyba ze ta sama note jawnie nakazuje wykonanie konkretnemu lane'owi.
- Jesli masz pending task albo targetowana note, wez claim przez RUN/CLAIM_ORCHESTRATOR_WORK.ps1 z TaskId.
- Koncz pracę przez RUN/WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1 albo COMPLETE_ORCHESTRATOR_PARALLEL_TASK.ps1 -PublishResultNote.
- Traktuj ten chat jako odrebna sesje brygady nadzorczej.
