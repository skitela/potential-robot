# Project Guidelines

## Mission

- Chron kapital powierzony do scalpingu przed wszystkim innym.
- Po ochronie kapitalu priorytetem jest zysk netto i realistyczna praca na aktywnych instrumentach.
- Pilnuj parity miedzy labem na laptopie a runtime na VPS OANDA MT5 i TMS Brokers.

## Brigade Workflow

- Traktuj jedna sesje czatu jako jedna brygade albo jeden lane pracy.
- Przed wieksza zmiana przeczytaj [BRYGADY/00_START_BRYGADY.md](../BRYGADY/00_START_BRYGADY.md) oraz karte konkretnej brygady.
- Wszystkie brygady czytaja nowe notatki z mostu, ale wykonuje tylko brygada jednoznacznie wskazana jako adresat albo wlasciciel tasku.
- Traktuj monitoring mostu jako stala zasade: sprawdzaj czy sa nowe note i czy receipts potwierdzaja ich doreczenie do brygad.
- Przed wykonaniem polecenia z note albo tasku zrob review bezpieczenstwa, zgodnosci z kontraktami i zgodnosci z aktualnym stanem runtime.
- Jezeli polecenie jest sprzeczne, ryzykowne albo destrukcyjne, eskaluj przez note albo task zamiast wykonywac je slepo.

## Operational Sources

- Za glowna prawde o brygadach uznawaj [CONFIG/orchestrator_brigades_registry_v1.json](../CONFIG/orchestrator_brigades_registry_v1.json) i [TOOLS/orchestrator/ORCHESTRATOR_BRIGADES_PL.md](../TOOLS/orchestrator/ORCHESTRATOR_BRIGADES_PL.md).
- Przed szeroka praca operacyjna sprawdz stan taskow i claimow przez RUN/GET_ORCHESTRATOR_TASKBOARD.ps1 oraz RUN/GET_ORCHESTRATOR_WORKBOARD.ps1.
- Do stalej synchronizacji not i receipt brygad uzywaj RUN/SYNC_ORCHESTRATOR_BRIGADE_NOTES.ps1 albo RUN/PUBLISH_BRIGADE_AUTOMATIC_REPORTS.ps1.
- Do szybkiego statusu lane i watcherow readiness/truth uzywaj RUN/BUILD_BRIGADE_DAILY_STATUS.ps1.

## Change Discipline

- Preferuj male, odwracalne zmiany zamiast szerokich przetasowan.
- Nie rozszerzaj rolloutow ani fali modeli, gdy readiness albo truth pozostaja czerwone, chyba ze task wyraznie tego wymaga.
- Dokumentuj istotne skutki operacyjne w istniejacych panelach brygad, zamiast rozrzucac zasady po nowych plikach.