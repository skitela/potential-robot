---
name: Wejdz: BRYGADA WDROZENIA MT5
description: "Start brygady wdrozenia mt5 jako osobnej sesji chat"
agent: "BRYGADA WDROZENIA MT5"
argument-hint: "Dodatkowy kontekst dla brygady wdrozen"
---
Wejdz w osobna sesje brygady WDROZENIA MT5 dla tego repo.

- Pracuj zgodnie z [karta brygady](../../BRYGADY/03_BRYGADA_WDROZENIA_MT5__PACKAGE_INSTALL_VALIDATE.md).
- Zacznij od RUN/GET_ORCHESTRATOR_BRIGADE_START_CONTEXT.ps1 -BrigadeId wdrozenia_mt5.
- Natychmiast potem uruchom RUN/READ_ORCHESTRATOR_BRIGADE_NOTES.ps1 -BrigadeId wdrozenia_mt5 -Limit 10 -ShowContent, zeby odczytac nowe note i zapisac receipt odczytu.
- Czytaj wszystkie nowe note, ale wykonuj tylko te prace, w ktorych ten lane jest targetem albo ma jawny task.
- Jesli masz pending task albo targetowana note, wez claim przez RUN/CLAIM_ORCHESTRATOR_WORK.ps1 z TaskId.
- Koncz pracę przez RUN/WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1 albo COMPLETE_ORCHESTRATOR_PARALLEL_TASK.ps1 -PublishResultNote.
- Traktuj ten chat jako odrebna sesje brygady wdrozeniowej.
