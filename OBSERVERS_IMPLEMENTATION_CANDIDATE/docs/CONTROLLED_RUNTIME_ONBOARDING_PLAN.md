# CONTROLLED_RUNTIME_ONBOARDING_PLAN

## Cel
Przeprowadzic kontrolowany onboarding warstwy `OBSERVERS_IMPLEMENTATION_CANDIDATE` bez naruszenia decision loop (`SafetyBot/EA/bridge`).

## Zasady nienaruszalne
- NO TOUCH: brak zlecen, brak mutacji config live, brak write do execution path.
- NO ASK: brak runtime queries do procesow wykonawczych.
- READ PERSISTED ONLY: tylko artefakty zapisane na dysku.
- MANUAL CODEX INVOCATION ONLY: agent tworzy ticket, operator uruchamia Codexa recznie.

## Etap 1: Preflight (read-only)
1. Sprawdz status audytow `audit_1_self`, `audit_2_cross_architecture`, `audit_3_operational_auditability`.
2. Sprawdz obecność wymaganych dokumentów (`DECISIONS.md`, manifest, README, plan etapowy).
3. Sprawdz granice import/write przez skan AST (dodatkowy guard).
4. Wygeneruj raport GO/NO-GO do `docs/onboarding/`.

## Etap 2: Dry-run operatorski (manual, bez runtime integration)
1. Operator uruchamia pojedynczy cykl kazdego agenta na danych persisted (lokalnie).
2. Weryfikacja, ze raporty/alerty/tickety trafiaja wyłącznie do `outputs/`.
3. Weryfikacja, ze nie ma prob zapisu do execution path.
4. Konsola operatora prezentuje stan uslugi + liczniki + ostatnie alerty.
5. Popups tylko dla `HIGH` alertow (bez ingerencji w decision loop).

## Etap 3: Shadow onboarding (osobny prompt)
1. Podpiecie uruchamiania agentow do harmonogramu pomocniczego.
2. Nadal brak integracji z decision loop runtime.
3. Sledzenie stabilnosci przez minimum 1 okno sesyjne.

## Kryteria GO
- Wszystkie 3 audyty = PASS.
- Brak naruszen import/write boundaries.
- Testy lokalne observerow = PASS.
- Raport preflight = `status=GO`.

## Kryteria NO-GO
- Jakikolwiek audit != PASS.
- Wykryte importy runtime tradingowe.
- Wykryta sciezka zapisu poza `outputs/`.
- Brak wymaganych dokumentow/manifestu.
