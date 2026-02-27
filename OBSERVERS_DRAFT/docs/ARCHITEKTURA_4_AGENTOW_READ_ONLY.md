# ARCHITEKTURA 4 AGENTÓW (READ-ONLY)

## Role
- `agent_informacyjny`: radar operacyjny, alerty i status.
- `agent_rozwoju_scalpingu`: analityka R&D na danych persisted.
- `agent_rekomendacyjny`: synteza i priorytetyzacja zaleceń.
- `agent_straznik_spojnosci`: wykrywanie dryfu kontraktów i trigger audytu.

## Granice
- Zakaz importów runtime tradingowych.
- Zakaz write do execution-adjacent katalogów.
- Dozwolony write wyłącznie do `OBSERVERS_DRAFT/outputs`.

## Adapter danych
`ReadOnlyDataAdapter`:
- czyta JSON/JSONL z retry/backoff,
- obsługuje przypadek half-written (`STALE_OR_INCOMPLETE`),
- nie posiada metod mutujących.

## Tickets do Codexa
- generowane wyłącznie jako plik persisted,
- zawsze:
  - `requires_operator_approval = true`
  - `codex_invocation_mode = MANUAL_BY_OPERATOR`

