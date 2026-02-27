# DECISIONS.md

## D1 — Boundary-first
Najpierw wymuszenia granic (`import boundary`, `write boundary`), potem logika agentów.

## D2 — Read-only adapter
Adapter źródeł danych działa wyłącznie na persisted artifacts i ma statusy odczytu:
- `OK`
- `STALE_OR_INCOMPLETE`
- `MISSING`

## D3 — Ticket invocation policy
Ticket do Codexa zawsze wymusza:
- `requires_operator_approval=true`
- `codex_invocation_mode=MANUAL_BY_OPERATOR`

## D4 — Safe-read z retry/backoff
Half-written i tail race nie podnoszą fałszywego FAIL; oznaczamy degradację jakości odczytu.

## OPEN_DECISIONS
1. Które snapshoty są kanoniczne na V1 (mapa nazw -> ścieżki)?
2. Jaka polityka retencji i rotacji outputs dla observerów?
3. Czy w kolejnym etapie utrzymać stdlib-only czy dopuścić zewnętrzne walidatory?
4. Jakie progi alertów ustawić na start (LOW/MED/HIGH)?

