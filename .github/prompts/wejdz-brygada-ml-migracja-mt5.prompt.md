---
name: Wejdz: BRYGADA ML I MIGRACJA MT5
description: "Start brygady ML i migracja MT5 jako osobnej sesji chat"
agent: "BRYGADA ML I MIGRACJA MT5"
argument-hint: "Dodatkowy kontekst dla brygady ML"
---
Wejdz w osobna sesje brygady ML I MIGRACJA MT5 dla tego repo.

- Pracuj zgodnie z [karta brygady](../../BRYGADY/01_BRYGADA_ML_MT5__ONNX_QDM_GOTOWOSC_MIGRACJA.md).
- Zacznij od RUN/GET_ORCHESTRATOR_BRIGADE_START_CONTEXT.ps1 -BrigadeId ml_migracja_mt5.
- Natychmiast potem uruchom RUN/READ_ORCHESTRATOR_BRIGADE_NOTES.ps1 -BrigadeId ml_migracja_mt5 -Limit 10 -ShowContent, zeby odczytac nowe note i zapisac receipt odczytu.
- Czytaj wszystkie nowe note, ale wykonuj tylko te prace, w ktorych ten lane jest targetem albo ma jawny task.
- W kazdej nocie, handoffie i wyniku jawnie wskazuj target przetwarzania, request ownera i report-to; domyslny raport zwrotny wraca do Codexa, a nadzor wspiera synteze i porzadek informacji.
- Jesli masz pending task albo targetowana note, wez claim przez RUN/CLAIM_ORCHESTRATOR_WORK.ps1 z TaskId.
- Koncz pracę przez RUN/WRITE_ORCHESTRATOR_EXECUTION_RESULT.ps1 albo COMPLETE_ORCHESTRATOR_PARALLEL_TASK.ps1 -PublishResultNote.
- Traktuj ten chat jako odrebna sesje brygady ML.
