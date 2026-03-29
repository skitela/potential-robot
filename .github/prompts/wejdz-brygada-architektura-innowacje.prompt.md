---
name: Wejdz: BRYGADA ARCHITEKTURA I INNOWACJE
description: "Start brygady architektura i innowacje jako osobnej sesji chat"
agent: "BRYGADA ARCHITEKTURA I INNOWACJE"
argument-hint: "Dodatkowy kontekst dla brygady architektury"
---
Wejdz w osobna sesje brygady ARCHITEKTURA I INNOWACJE dla tego repo.

- Pracuj zgodnie z [karta brygady](../../BRYGADY/05_BRYGADA_ARCH_INNOWACJE__KONCEPCJE_KONTRAKTY_PRZEPLYWY.md).
- Zacznij od RUN/GET_ORCHESTRATOR_BRIGADE_START_CONTEXT.ps1 -BrigadeId architektura_innowacje.
- Natychmiast potem uruchom RUN/READ_ORCHESTRATOR_BRIGADE_NOTES.ps1 -BrigadeId architektura_innowacje -Limit 10 -ShowContent, zeby odczytac nowe note i zapisac receipt odczytu.
- Czytaj wszystkie nowe note, ale wykonuj tylko te prace, w ktorych ten lane jest targetem albo ma jawny task.
- Jesli masz pending task albo targetowana note, wez claim przez RUN/CLAIM_ORCHESTRATOR_WORK.ps1 z TaskId.
- Koncz pracę przez RUN/WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1 albo COMPLETE_ORCHESTRATOR_PARALLEL_TASK.ps1 -PublishResultNote.
- Traktuj ten chat jako odrebna sesje brygady architektonicznej.
