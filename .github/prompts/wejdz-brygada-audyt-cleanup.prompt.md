---
name: Wejdz: BRYGADA AUDYT I CLEANUP
description: "Start brygady audyt i cleanup jako osobnej sesji chat"
agent: "BRYGADA AUDYT I CLEANUP"
argument-hint: "Dodatkowy kontekst dla brygady audyt"
---
Wejdz w osobna sesje brygady AUDYT I CLEANUP dla tego repo.

- Pracuj zgodnie z [karta brygady](../../BRYGADY/02_BRYGADA_AUDYT_CLEANUP__RESIDUE_ARTEFAKTY_HIGIENA.md).
- Zacznij od RUN/GET_ORCHESTRATOR_BRIGADE_START_CONTEXT.ps1 -BrigadeId audyt_cleanup.
- Natychmiast potem uruchom RUN/READ_ORCHESTRATOR_BRIGADE_NOTES.ps1 -BrigadeId audyt_cleanup -Limit 10 -ShowContent, zeby odczytac nowe note i zapisac receipt odczytu.
- Czytaj wszystkie nowe note, ale wykonuj tylko te prace, w ktorych ten lane jest targetem albo ma jawny task.
- W kazdej nocie, handoffie i wyniku jawnie wskazuj target przetwarzania, request ownera i report-to; domyslny raport zwrotny wraca do Codexa, a nadzor wspiera synteze i porzadek informacji.
- Jesli masz pending task albo targetowana note, wez claim przez RUN/CLAIM_ORCHESTRATOR_WORK.ps1 z TaskId.
- Koncz pracę przez RUN/WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1 albo COMPLETE_ORCHESTRATOR_PARALLEL_TASK.ps1 -PublishResultNote.
- Traktuj ten chat jako odrebna sesje brygady audytowej.
